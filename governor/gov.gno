package governor

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"std"
	"strings"
	"strconv"
	"time"

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
		configVersions:           make(map[uint64]Config),
		latestConfigVersion:      0,
		nonce:                    0,
		proposals:                make(map[string]ProposalInfo),
		latestProposalByProposer: make(map[std.Address]string),
		vote:                     make(map[string]map[std.Address]uint8),
	}
}

// Propose creates a new proposal with the given set of calls.
// It checks if the proposer is eligible to create a proposal and if they don't have an active proposal.
// Returns the proposal ID and an error if the proposal creation fails.
// TODO: change to use primitive types. (getter/setter)
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

	latestProposalID, exists := gGovernor.latestProposalByProposer[proposer]
	if exists {
		latestProposalState := gGovernor.proposals[latestProposalID].ExecutionState

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
	if avgDelegated.Cmp(config.ProposalCreationThreshold) < 0 {
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
	}

	gGovernor.proposals[string(id[:])] = proposal
	gGovernor.latestProposalByProposer[proposer] = string(id[:])

	std.Emit(
		"Proposed",
		"id", string(id[:]),
		"proposer", proposer.String(),
		"calls", ufmt.Sprintf("%v", calls),
	)

	return string(id), nil
}

// Describe adds a description to an existing proposal.
// Only the original proposer can add a description, and it must be done before the proposal is executed or canceled.
func Describe(id, description string) {
	if gGovernor == nil {
		panic("Governor not initialized")
	}

	proposal, exists := gGovernor.proposals[id]
	if !exists {
		panic("DOES_NOT_EXIST")
	}

	if proposal.ExecutionState.Executed != 0 {
		panic("ALREADY_EXECUTED")
	}

	if proposal.ExecutionState.Canceled != 0 {
		panic("PROPOSAL_CANCELED")
	}

	if proposal.Proposer != std.GetOrigCaller() {
		panic("NOT_PROPOSER")
	}

	// Emit the Described event
	std.Emit(
		"Described",
		"id", string(id[:]), // Convert byte array to string for event emission
		"description", description,
	)
}

// ProposeAndDescribe combines the functionality of Propose and Describe.
// It creates a new proposal and immediately adds a description to it.
// Returns the proposal ID and an error if either the proposal creation or description fails.
func ProposeAndDescribe(callsJSON, desc string) (string, error) {
	if gGovernor == nil {
		panic("Governor not initialized")
	}

	// 1. propose the calls
	id, err := Propose(callsJSON)
	if err != nil {
		return "", err
	}

	// 2. describe the proposal
	Describe(id, desc)

	return id, nil
}

// Vote allows a user to vote on a given proposal.
// The user's voting weight is determined by their average delegated stake over a specified period.
// Panics if the voting conditions are not met (e.g., voting period hasn't started, has ended, or user has already voted).
func Vote(id string, yes bool) {
	if gGovernor == nil {
		panic("Governor not initialized")
	}

	proposal, exists := gGovernor.proposals[id]
	if !exists {
		panic("DOES_NOT_EXIST")
	}

	if proposal.ExecutionState.Executed != 0 {
		panic("ALREADY_EXECUTED")
	}

	config := GetConfigVersion(proposal.ConfigVersion)
	timestampCurrent := uint64(timeNow().Unix())
	votingStartTime := proposal.ExecutionState.Created + config.VotingStartDelay
	voter := std.GetOrigCaller()

	if timestampCurrent < votingStartTime {
		panic("VOTING_NOT_STARTED")
	}

	if timestampCurrent >= (votingStartTime + config.VotingPeriod) {
		panic("VOTING_ENDED")
	}

	_, voted := gGovernor.vote[id][voter]
	if voted {
		panic("ALREADY_VOTED")
	}

	weight, err := gGovernor.staker.GetAverageDelegated(
		voter,
		votingStartTime-config.VotingWeightSmoothingDuration,
		votingStartTime,
	)
	if err != nil {
		panic("FAILED_TO_GET_WEIGHT")
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

	gGovernor.proposals[id] = proposal
	if gGovernor.vote[id] == nil {
		gGovernor.vote[id] = make(map[std.Address]uint8)
	}
	gGovernor.vote[id][voter] = uint8(2 + b2i(yes))

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

	proposal, exists := gGovernor.proposals[id]
	if !exists {
		panic("DOES_NOT_EXIST")
	}

	if proposal.ExecutionState.Canceled != 0 {
		panic("ALREADY_CANCELED")
	}

	config := GetConfigVersion(proposal.ConfigVersion)
	timestampCurrent := uint64(timeNow().Unix())
	if timestampCurrent >= (proposal.ExecutionState.Created + config.VotingStartDelay) {
		panic("VOTING_STARTED")
	}

	caller := std.GetOrigCaller()
	if caller != proposal.Proposer {
		// If the caller is not the proposer, check if the proposer's stake has fallen below the threshold
		avgDelegated, err := gGovernor.staker.GetAverageDelegatedOverLast(proposal.Proposer, config.VotingWeightSmoothingDuration)
		if err != nil {
			panic("FAILED_TO_GET_AVERAGE_DELEGATED")
		}
		if avgDelegated.Cmp(config.ProposalCreationThreshold) >= 0 {
			panic("NOT_PROPOSER")
		}
	}

	proposal.ExecutionState.Canceled = timestampCurrent
	gGovernor.proposals[id] = proposal

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
		panic("Governor not initialized")
	}

	proposal, exists := gGovernor.proposals[id]
	if !exists {
		panic("DOES_NOT_EXIST")
	}

	calls, err := parseCallsFromJSON(json.Must(json.Unmarshal([]byte(callsJSON))))
	if err != nil {
		panic("INVALID_CALLS_JSON")
	}

	callsHash := hashCalls(calls)
	if proposal.CallsHash != callsHash {
		panic("CALLS_HASH_MISMATCH")
	}

	if proposal.ExecutionState.Executed != 0 {
		panic("ALREADY_EXECUTED")
	}

	if proposal.ExecutionState.Canceled != 0 {
		panic("PROPOSAL_CANCELED")
	}

	timestampCurrent := uint64(timeNow().Unix())
	if timestampCurrent == 0 {
		panic("TIMESTAMP_ZERO")
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
	quorumUint := config.Quorum.Uint64()

	if yeaUint < quorumUint {
		panic("QUORUM_NOT_MET")
	}

	if yeaUint < nayUint {
		panic("NO_MAJORITY")
	}

	proposal.ExecutionState.Executed = timestampCurrent
	gGovernor.proposals[id] = proposal

	results := make([]string, 0, len(calls))
	for _, call := range calls {
		result := executeCall(call)
		results = append(results, result)
	}

	std.Emit(
		"Executed",
		"id", string(id[:]),
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

	result, err := fn(call.Calldata)
	if err != nil {
		panic("CALL_EXECUTION_FAILED: " + err.Error())
	}

	return string(result)
}

// GetConfigVersion returns the configuration for a specific version.
// If version is 0, it returns the current configuration.
func GetConfigVersion(version uint64) Config {
	if gGovernor == nil {
		panic("Governor not initialized")
	}

	if version == 0 {
		return gGovernor.config
	}

	config, exists := gGovernor.configVersions[version]
	if !exists {
		panic("DOES_NOT_EXIST")
	}

	return config
}

// // Reconfigure updates the Governor's configuration.
// // This function can only be called by the Governor itself (via a proposal).
// // Returns the new configuration version number.
// func Reconfigure(newConfig Config) uint64 {
// 	if gGovernor == nil {
// 		panic("Governor not initialized")
// 	}

// 	checkSelfCall()

// 	gGovernor.latestConfigVersion++
// 	gGovernor.configVersions[gGovernor.latestConfigVersion] = newConfig
// 	gGovernor.config = newConfig

// 	// TODO: emit

// 	return gGovernor.latestConfigVersion
// }

// checkSelfCall ensures that the function is called by the Governor itself.
// Panics if the caller is not the Governor contract.
func checkSelfCall() {
	if std.GetOrigCaller() != std.GetOrigPkgAddr() {
		panic("NOT_SELF_CALL")
	}
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

// Call represents a contract call
type Call struct {
	To       std.Address
	Selector uint64
	Calldata []byte
}

// hashCalls computes the hash of a list of calls

func hashCalls(calls []Call) string {
    var buf strings.Builder
    buf.WriteString("governance::governor::Governor::hash_calls")

    for _, call := range calls {
        buf.WriteString(string(call.To))
        buf.WriteString(strconv.FormatUint(call.Selector, 10))
        buf.Write(call.Calldata)
    }

    return buf.String()
}

func b2i(b bool) uint8 {
	if b {
		return 1
	}
	return 0
}

func b2s(b bool) string {
	if b {
		return "true"
	}
	return "false"
}
