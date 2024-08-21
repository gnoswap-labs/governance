package governor

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"std"
	"strconv"
	"strings"
	"time"

	"gno.land/p/demo/avl"
	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/json"
	"gno.land/p/demo/ufmt"
	u256 "gno.land/p/demo/uint256"
)

var (
	timeNow   = time.Now
	gGovernor *Governor
)

// Init initializes the governor contract with the given staker and configuration.
// It creates a new Governor instance and sets it as the global governor.
// This function should be called only once at the beginning of the contract's lifecycle.
func Init(staker IStakerDispatcher, config Config) {
	gGovernor = &Governor{
		staker:                   staker,
		config:                   config,
		configVersions:           avl.NewTree(),
		latestConfigVersion:      0,
		nonce:                    0,
		proposals:                avl.NewTree(),
		latestProposalByProposer: avl.NewTree(),
		vote:                     avl.NewTree(),
	}
}

// Propose creates a new proposal with the given set of calls.
// It checks if the proposer is eligible to create a proposal and if they don't have an active proposal.
// Returns the proposal ID and an error if the proposal creation fails.
func Propose(callsJSON string) (string, error) {
	if gGovernor == nil {
		panic("Governor not initialized")
	}

	proposer := std.GetOrigCaller()
	nonce := gGovernor.nonce
	gGovernor.nonce++

	id := getProposalID(std.GetOrigPkgAddr(), nonce)

	config := gGovernor.config
	timestampCurrent := uint64(timeNow().Unix())

	latestProposalID, exists := gGovernor.latestProposalByProposer.Get(proposer.String())
	if exists {
		latestProposalInfo, _ := gGovernor.proposals.Get(latestProposalID.(string))
		latestProposalState := latestProposalInfo.(ProposalInfo).ExecutionState

		if latestProposalState.Canceled == 0 {
			if latestProposalState.Created+config.VotingStartDelay+config.VotingPeriod > timestampCurrent {
				panic("PROPOSER_HAS_ACTIVE_PROPOSAL")
			}
		}
	}

	avgDelegated, err := gGovernor.staker.GetAverageDelegatedOverLast(proposer, config.VotingWeightSmoothingDuration)
	if err != nil {
		panic(err)
	}

	if avgDelegated.Uint64() < config.ProposalCreationThreshold {
		panic("THRESHOLD")
	}

	callsNode, err := json.Unmarshal([]byte(callsJSON))
	if err != nil {
		panic(ufmt.Sprintf("failed to unmarshal calls JSON: %v", err))
	}

	calls, err := parseCallsFromJSON(callsNode)
	if err != nil {
		panic(ufmt.Sprintf("failed to parsing calls from JSON: %v", err))
	}

	callsHash := hashCalls(calls)

	proposal := ProposalInfo{
		CallsHash: callsHash,
		Proposer:  proposer,
		ExecutionState: ExecutionState{
			Created:  timestampCurrent,
			Executed: 0,
			Canceled: 0,
		},
		Yea:           u256.NewUint(0),
		Nay:           u256.NewUint(0),
		ConfigVersion: gGovernor.latestConfigVersion,
		Title:         "",
		Description:   "",
	}

	gGovernor.proposals.Set(id, proposal)
	gGovernor.latestProposalByProposer.Set(proposer.String(), id)

	std.Emit(
		"Proposed",
		"id", id,
		"proposer", proposer.String(),
		"calls", ufmt.Sprintf("%v", calls),
	)

	return string(id), nil
}

// Describe adds a description to an existing proposal.
// Only the original proposer can add a description, and it must be done before the proposal is executed or canceled.
func Describe(id, title, description string) {
	if gGovernor == nil {
		panic("Governor not initialized")
	}

	proposalValue, exists := gGovernor.proposals.Get(id)
	if !exists {
		panic(ufmt.Sprintf("proposal %s does not exist", id))
	}

	proposal := proposalValue.(ProposalInfo)

	if proposal.ExecutionState.Executed != 0 {
		panic(ufmt.Sprintf("proposal %s has already been executed", id))
	}

	if proposal.ExecutionState.Canceled != 0 {
		panic(ufmt.Sprintf("proposal %s has already been canceled", id))
	}

	if proposal.Proposer != std.GetOrigCaller() {
		panic(ufmt.Sprintf("caller %s is not the proposer of proposal %s", std.GetOrigCaller().String(), id))
	}

	proposal.Title = title
	proposal.Description = description
	gGovernor.proposals.Set(id, proposal)

	std.Emit(
		"Described",
		"id", id, // Convert byte array to string for event emission
		"title", title,
		"description", description,
	)
}

// ProposeAndDescribe combines the functionality of Propose and Describe.
// It creates a new proposal and immediately adds a description to it.
// Returns the proposal ID and an error if either the proposal creation or description fails.
func ProposeAndDescribe(callsJSON, title, desc string) (string, error) {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	// 1. propose the calls
	id, err := Propose(callsJSON)
	if err != nil {
		return "", err
	}

	// 2. describe the proposal
	Describe(id, title, desc)

	return id, nil
}

// Vote allows a user to vote on a given proposal.
// The user's voting weight is determined by their average delegated stake over a specified period.
// Panics if the voting conditions are not met (e.g., voting period hasn't started, has ended, or user has already voted).
func Vote(id string, yes bool) {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	proposalValue, exists := gGovernor.proposals.Get(id)
	if !exists {
		panic(ufmt.Sprintf("Proposal %v does not exist", id))
	}

	proposal := proposalValue.(ProposalInfo)
	if proposal.ExecutionState.Executed != 0 {
		panic(ufmt.Sprintf("Proposal %v has already been executed", id))
	}

	config := GetConfigVersion(proposal.ConfigVersion)
	timestampCurrent := uint64(timeNow().Unix())
	votingStartTime := proposal.ExecutionState.Created + config.VotingStartDelay
	gGovernor.votingStartTime = votingStartTime

	voter := std.GetOrigCaller()

	if timestampCurrent < votingStartTime {
		panic(ufmt.Sprintf("voting has not started yet. Current time: %d, Voting start time: %d", timestampCurrent, votingStartTime))
	}

	votingEndTime := votingStartTime + config.VotingPeriod
	gGovernor.votingEndTime = votingEndTime

	if timestampCurrent >= votingEndTime {
		panic(ufmt.Sprintf("voting has ended. Current time: %d, Voting end time: %d", timestampCurrent, votingStartTime+config.VotingPeriod))
	}

	voteKey := id + ":" + voter.String()
	_, voted := gGovernor.vote.Get(voteKey)
	if voted {
		panic(ufmt.Sprintf("user %v has already voted on proposal %v", voter.String(), id))
	}

	weight, err := gGovernor.staker.GetAverageDelegated(
		voter,
		votingStartTime-config.VotingWeightSmoothingDuration,
		votingStartTime,
	)
	if err != nil {
		panic(ufmt.Sprintf("failed to get average delegated stake for voter %s: %v", voter.String(), err))
	}

	var overflow bool
	if yes {
		proposal.Yea, overflow = new(u256.Uint).AddOverflow(proposal.Yea, weight)
		if overflow {
			panic("OVERFLOW")
		}
	} else {
		proposal.Nay, overflow = new(u256.Uint).AddOverflow(proposal.Nay, weight)
		if overflow {
			panic("OVERFLOW")
		}
	}

	gGovernor.proposals.Set(id, proposal)
	gGovernor.vote.Set(voteKey, uint8(2+b2i(yes)))
	
	std.Emit(
		"Voted",
		"id", id,
		"voter", voter.String(),
		"weight", weight.ToString(),
		"yes", b2s(yes),
	)
}

// Cancel cancels the proposal with the given ID.
// Only callable by the proposer or if the proposer's stake has fallen below the threshold.
// Panics if the proposal doesn't exist, is already canceled, or if voting has already started.
func Cancel(id string) {
	if gGovernor == nil {
		panic("Governor not initialized")
	}

	proposalValue, exists := gGovernor.proposals.Get(id)
	if !exists {
		panic(ufmt.Sprintf("proposal %s does not exist", id))
	}

	proposal := proposalValue.(ProposalInfo)
	if proposal.ExecutionState.Canceled != 0 {
		panic(ufmt.Sprintf("proposal %s has already been canceled", id))
	}

	config := GetConfigVersion(proposal.ConfigVersion)
	timestampCurrent := uint64(timeNow().Unix())
	if timestampCurrent >= (proposal.ExecutionState.Created + config.VotingStartDelay) {
		panic(ufmt.Sprintf("voting has already started for proposal %s", id))
	}

	caller := std.GetOrigCaller()
	if caller != proposal.Proposer {
		// If the caller is not the proposer, check if the proposer's stake has fallen below the threshold
		avgDelegated, err := gGovernor.staker.GetAverageDelegatedOverLast(proposal.Proposer, config.VotingWeightSmoothingDuration)
		if err != nil {
			panic(ufmt.Sprintf("failed to get average delegated stake for proposer %s: %v", proposal.Proposer, err))
		}

		if avgDelegated.Uint64() >= config.ProposalCreationThreshold {
			panic(ufmt.Sprintf("caller %s is not the proposer and proposer's stake is above the threshold", caller))
		}
	}

	proposal.ExecutionState.Canceled = timestampCurrent
	gGovernor.proposals.Set(id, proposal)

	std.Emit("Canceled",
		"id", id,
	)
}

// Execute executes the given proposal.
// It checks various conditions such as voting period, execution window, quorum, and majority.
// Returns the results of the executed calls.
// Panics if any of the execution conditions are not met.
//
// XXX: Dynamic Call?
func Execute(id, callsJSON string) string {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	calls, err := parseCallsFromJSON(json.Must(json.Unmarshal([]byte(callsJSON))))
	if err != nil {
		panic("INVALID_CALLS_JSON")
	}

	callsHash := hashCalls(calls)

	proposalValue, exists := gGovernor.proposals.Get(id)
	if !exists {
		panic(ufmt.Sprintf("proposal %s does not exist. failed to execute", id))
	}

	proposal := proposalValue.(ProposalInfo)
	if proposal.CallsHash != callsHash {
		panic(ufmt.Sprintf("calls hash mismatch. expected %s, got %s", proposal.CallsHash, callsHash))
	}

	if proposal.ExecutionState.Executed != 0 {
		panic(ufmt.Sprintf("proposal %s has already been executed", id))
	}

	if proposal.ExecutionState.Canceled != 0 {
		panic(ufmt.Sprintf("proposal %s has already been canceled", id))
	}

	timestampCurrent := uint64(timeNow().Unix())
	if timestampCurrent == 0 {
		panic("current timestamp is 0. failed to execute")
	}

	config := GetConfigVersion(proposal.ConfigVersion)
	votingEnd := proposal.ExecutionState.Created + config.VotingStartDelay + config.VotingPeriod
	if timestampCurrent < votingEnd {
		panic("VOTING_NOT_ENDED")
	}

	windowStart := votingEnd + config.ExecutionDelay
	if timestampCurrent < windowStart {
		panic("EXECUTION_WINDOW_NOT_STARTED")
	}

	windowEnd := windowStart + config.ExecutionWindow
	if timestampCurrent >= windowEnd {
		panic("EXECUTION_WINDOW_OVER")
	}

	yeaUint := proposal.Yea.Uint64()
	nayUint := proposal.Nay.Uint64()
	quorumUint := config.Quorum

	if yeaUint < quorumUint {
		panic("QUORUM_NOT_MET")
	}

	if yeaUint < nayUint {
		panic("NO_MAJORITY")
	}

	proposal.ExecutionState.Executed = timestampCurrent
	gGovernor.proposals.Set(id, proposal)

	results := make([]string, 0, len(calls))
	for _, call := range calls {
		result := executeCall(call)
		results = append(results, result)
	}

	std.Emit(
		"Executed",
		"id", id,
	)

	return strings.Join(results, ",")
}

// registry stores registered functions
var registry = make(map[uint64]CallFunction)

// RegisterFunction registers a function with the given selector.
// This allows the governor to execute custom functions during proposal execution.
func RegisterFunction(selector uint64, fn CallFunction) {
	registry[selector] = fn
}

// executeCall executes a single call
func executeCall(call Call) string {
	fn, exists := registry[call.Selector]
	if !exists {
		panic("FUNCTION_NOT_REGISTERED")
	}

	args := strings.Split(call.Calldata, ",")

	result, err := fn(args...)
	if err != nil {
		panic("CALL_EXECUTION_FAILED: " + err.Error())
	}

	return string(result)
}

// GetConfigVersion returns the configuration for a specific version.
// If version is 0, it returns the current configuration.
func GetConfigVersion(version uint64) Config {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	if version == 0 {
		return gGovernor.config
	}

	configValue, exists := gGovernor.configVersions.Get(strconv.FormatUint(version, 10))
	if !exists {
		panic("DOES_NOT_EXIST")
	}

	return configValue.(Config)
}

// Reconfigure updates the Governor's configuration.
// This function can only be called by the Governor itself (via a proposal).
// Returns the new configuration version number.
func Reconfigure(newConfigJSON string) uint64 {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	// ensure called by the Governor itself
	if std.GetOrigCaller() != std.GetOrigPkgAddr() {
		panic("NOT_SELF_CALL")
	}

	newConfigNode, err := json.Unmarshal([]byte(newConfigJSON))
	if err != nil {
		panic("invalid confiquration JSON: " + err.Error())
	}

	newConfig, err := parseConfig(newConfigNode)
	if err != nil {
		panic("failed to parse configuration: " + err.Error())
	}

	gGovernor.latestConfigVersion++
	gGovernor.configVersions.Set(strconv.FormatUint(gGovernor.latestConfigVersion, 10), newConfig)
	gGovernor.config = newConfig

	std.Emit(
		"Reconfigured",
		"version", string(gGovernor.latestConfigVersion),
		"voting_start_delay", string(newConfig.VotingStartDelay),
		"voting_period", string(newConfig.VotingPeriod),
		"voting_weight_smoothing_duration", string(newConfig.VotingWeightSmoothingDuration),
		"quorum", string(newConfig.Quorum),
		"proposal_creation_threshold", string(newConfig.ProposalCreationThreshold),
		"execution_delay", string(newConfig.ExecutionDelay),
		"execution_window", string(newConfig.ExecutionWindow),
	)

	return gGovernor.latestConfigVersion
}

// getProposalID generates a unique proposal ID based on the contract address and nonce
func getProposalID(address std.Address, nonce uint64) string {
	data := make([]byte, len("governance::governor::Governor::get_proposal_id")+len(address)+8)
	copy(data, []byte("governance::governor::Governor::get_proposal_id"))
	copy(data[len("governance::governor::Governor::get_proposal_id"):], address[:])
	binary.BigEndian.PutUint64(data[len("governance::governor::Governor::get_proposal_id")+len(address):], nonce)
	sha := sha256.Sum256(data)

	var buf bytes.Buffer
	for _, b := range sha {
		buf.WriteString(strconv.FormatInt(int64(b), 16))
	}
	return buf.String()
}
