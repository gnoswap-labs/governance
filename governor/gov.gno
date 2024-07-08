package governor

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"std"
	"time"

	"gno.land/p/demo/grc/grc20"
	u256 "gno.land/p/demo/uint256"
	"gno.land/p/demo/ufmt"
)

var (
	timeNow = time.Now
	gGovernor *Governor
)

// Init initializes the governor contract
func Init(staker IStakerDispatcher, config Config) {
	gGovernor = &Governor{
		staker:                   staker,
		config:                   config,
		configVersions:           make(map[uint64]Config),
		latestConfigVersion:      0,
		nonce:                    0,
		proposals:                make(map[[32]byte]ProposalInfo),
		latestProposalByProposer: make(map[std.Address][32]byte),
		vote:                     make(map[[32]byte]map[std.Address]uint8),
	}
}

// Propose proposes a new proposal
func Propose(calls []Call) ([32]byte, error) {
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

	gGovernor.proposals[id] = proposal
	gGovernor.latestProposalByProposer[proposer] = id

	// TODO: use Emit

	return id, nil
}

func Describe(id [32]byte, description string) {
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
func ProposeAndDescribe(calls []Call, desc string) ([32]byte, error) {
	if gGovernor == nil {
		panic("Governor not initialized")
	}

	// 1. propose the calls
	id, err := Propose(calls)
	if err != nil {
		return [32]byte{}, err
	}

	// 2. describe the proposal
	Describe(id, desc)

	return id, nil
}

// Vote allows a user to vote on a given proposal
func Vote(id [32]byte, yes bool) {
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

	pastVote, voted := gGovernor.vote[id][voter]
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

	if yes {
		proposal.Yea = u256.Zero().Add(proposal.Yea, weight)
	} else {
		proposal.Nay = u256.Zero().Add(proposal.Nay, weight)
	}

	gGovernor.proposals[id] = proposal
	if gGovernor.vote[id] == nil {
		gGovernor.vote[id] = make(map[std.Address]uint8)
	}
	gGovernor.vote[id][voter] = uint8(2 + b2i(yes))

	std.Emit(
		"Voted",
		"id", string(id[:]),
		"voter", voter.String(),
		"weight", weight.ToString(),
		"yes", b2s(yes),
	)
}

// Cancel cancels the proposal with the given ID. 
// Only callable by the proposer or if the proposer's stake has fallen below the threshold.
func Cancel(id [32]byte) {
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
        "id", string(id[:]),
    )
}

// func Execute(id [32]byte, calls []Call) [][]byte {
// 	if gGovernor == nil {
// 		panic("Governor not initialized")
// 	}

// 	proposal, exists := gGovernor.proposals[id]
// 	if !exists {
// 		panic("DOES_NOT_EXIST")
// 	}

// 	callsHash := hashCalls(calls)
// 	if proposal.CallsHash != callsHash {
// 		panic("CALLS_HASH_MISMATCH")
// 	}

// 	if proposal.ExecutionState.Executed != 0 {
// 		panic("ALREADY_EXECUTED")
// 	}

// 	if proposal.ExecutionState.Canceled != 0 {
// 		panic("PROPOSAL_CANCELED")
// 	}

// 	timestampCurrent := uint64(timeNow().Unix())
// 	if timestampCurrent == 0 {
// 		panic("TIMESTAMP_ZERO")
// 	}

// 	config := GetConfigVersion(proposal.ConfigVersion)
// 	votingEnd := proposal.ExecutionState.Created + config.VotingStartDelay + config.VotingPeriod
// 	if timestampCurrent < votingEnd {
// 		panic("VOTING_NOT_ENDED")
// 	}

// 	windowStart := votingEnd + config.ExecutionDelay
// 	if timestampCurrent < windowStart {
// 		panic("EXECUTION_WINDOW_NOT_STARTED")
// 	}

// 	windowEnd := windowStart + config.ExecutionWindow
// 	if timestampCurrent >= windowEnd {
// 		panic("EXECUTION_WINDOW_OVER")
// 	}

// 	if proposal.Yea.Cmp(config.Quorum) < 0 {
// 		panic("QUORUM_NOT_MET")
// 	}

// 	if proposal.Yea.Cmp(proposal.Nay) < 0 {
// 		panic("NO_MAJORITY")
// 	}

// 	proposal.ExecutionState.Executed = timestampCurrent
// 	gGovernor.proposals[id] = proposal

// 	results := make([][]byte, 0, len(calls))
// 	for _, call := range calls {
// 		result := executeCall(call)
// 		results = append(results, result)
// 	}

// 	std.Emit(
// 		"Executed",
// 		"id", string(id[:]),
// 	)

// 	return results
// }

// registry stores registered functions
var registry = make(map[uint64]CallFunction)

// RegisterFunction registers a function with the given selector
func RegisterFunction(selector uint64, fn CallFunction) {
	registry[selector] = fn
}

// executeCall executes a single call
func executeCall(call Call) []byte {
	fn, exists := registry[call.Selector]
	if !exists {
		panic("FUNCTION_NOT_REGISTERED")
	}

	result, err := fn(call.Calldata)
	if err != nil {
		panic("CALL_EXECUTION_FAILED: " + err.Error())
	}

	return result
}

// GetConfigVersion returns the configuration for a specific version
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

// getProposalID generates a unique proposal ID based on the contract address and nonce
func getProposalID(address std.Address, nonce uint64) [32]byte {
	data := make([]byte, len("governance::governor::Governor::get_proposal_id")+len(address)+8)
	copy(data, []byte("governance::governor::Governor::get_proposal_id"))
	copy(data[len("governance::governor::Governor::get_proposal_id"):], address[:])
	binary.BigEndian.PutUint64(data[len("governance::governor::Governor::get_proposal_id")+len(address):], nonce)
	return sha256.Sum256(data)
}

// Call represents a contract call
type Call struct {
	To       std.Address
	Selector uint64
	Calldata []byte
}

// hashCalls computes the hash of a list of calls
func hashCalls(calls []Call) [32]byte {
	var buf bytes.Buffer
	buf.WriteString("governance::governor::Governor::hash_calls")
	for _, call := range calls {
		addrStr := call.To.String()
		buf.WriteString(addrStr)

		// convert the selector to big endian bytes directly
		selectorBytes := make([]byte, 4)
		selectorBytes[0] = byte(call.Selector >> 24)
		selectorBytes[1] = byte(call.Selector >> 16)
		selectorBytes[2] = byte(call.Selector >> 8)
		selectorBytes[3] = byte(call.Selector)
		buf.Write(selectorBytes)

		buf.Write(call.Calldata)
	}
	return sha256.Sum256(buf.Bytes())
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
