package governor

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"std"
	"time"

	"gno.land/p/demo/grc/grc20"
	u256 "gno.land/p/demo/uint256"
)

// Governor represents the governor contract
type Governor struct {
	staker                   IStakerDispatcher
	config                   Config
	configVersions           map[uint64]Config
	latestConfigVersion      uint64
	nonce                    uint64
	proposals                map[[32]byte]ProposalInfo
	latestProposalByProposer map[std.Address][32]byte
	vote                     map[[32]byte]map[std.Address]uint8
}

// Config represents the configuration of the governor contract
type Config struct {
	// How long after a proposal is created does voting starrt
	VotingStartDelay uint64
	// The period during which votes are collected
	VotingPeriod uint64
	// Over how many seconds the voting weight is averaged for proposal voting as creation/cancellation threshold
	VotingWeightSmoothingDuration uint64
	// How many total votes must be collected for the proposal
	Quorum *u256.Uint
	// The munimum amount of average votes required to create a proposal
	ProposalCreationThreshold *u256.Uint
	// How much time must pass after the end of a voting period before a proposal can be executed
	ExecutionDelay uint64
	// The amount of time after the execution delay that the proposal can be executed
	ExecutionWindow uint64
}

// ExecutionState represents the state of a proposal's execution
type ExecutionState struct {
	Created  uint64
	Executed uint64
	Canceled uint64
}

// ProposalInfo represents all the information about a proposal
type ProposalInfo struct {
	// The hash of the set of calls that are executed in this proposal
	CallsHash [32]byte
	// The address of the proposer
	Proposer std.Address
	// The execution state of the proposal
	ExecutionState ExecutionState
	// How many yes votes have been collected
	Yea *u256.Uint
	// How many no votes have been collected
	Nay *u256.Uint
	// The version of the config that this proposal was created with
	ConfigVersion uint64
}

var gGovernor *Governor

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
	timestampCurrent := uint64(time.Now().Unix())

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
	timestampCurrent := uint64(time.Now().Unix())
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
