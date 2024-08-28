package governor

import (
	"std"
	"strconv"
	"strings"

	"gno.land/p/demo/avl"
	u256 "gno.land/p/demo/uint256"
)

// Governor represents the governor contract
type Governor struct {
	// staker is the interface to interact with the staking contract
	staker IStakerDispatcher

	// config is the current configuration of the governor
	config Config

	// configVersions stores all historical configurations indexed by their version number
	configVersions *avl.Tree

	// latestConfigVersion is the version number of the most recent configuration
	latestConfigVersion uint64

	// nonce is used to generate unique proposal IDs
	nonce uint64

	// proposals stores all proposals indexed by their ID
	proposals *avl.Tree

	// latestProposalByProposer keeps track of the latest proposal ID for each proposer
	latestProposalByProposer *avl.Tree

	// vote stores the voting information for each proposal
	// The uint8 value represents: 0 = not voted, 2 = voted no, 3 = voted yes
	vote *avl.Tree

	votingStartTime uint64
	votingEndTime   uint64
}

// Config represents the configuration of the governor contract
type Config struct {
	// How long after a proposal is created does voting starrt
	VotingStartDelay uint64 `json:"voting_start_delay"`

	// The period during which votes are collected
	VotingPeriod uint64 `json:"voting_period"`

	// Over how many seconds the voting weight is averaged for proposal voting as creation/cancellation threshold
	VotingWeightSmoothingDuration uint64 `json:"voting_weight_smoothing_duration"`

	// How many total votes must be collected for the proposal
	Quorum uint64 `json:"quorum"`

	// The munimum amount of average votes required to create a proposal
	ProposalCreationThreshold uint64 `json:"proposal_creation_threshold"`

	// How much time must pass after the end of a voting period before a proposal can be executed
	ExecutionDelay uint64 `json:"execution_delay"`

	// The amount of time after the execution delay that the proposal can be executed
	ExecutionWindow uint64 `json:"execution_window"`
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
	CallsHash string `json:"calls_hash"`

	// The address of the proposer
	Proposer std.Address `json:"proposer"`

	// The execution state of the proposal
	ExecutionState ExecutionState `json:"execution_state"`

	// How many yes votes have been collected
	Yea *u256.Uint `json:"yea"`

	// How many no votes have been collected
	Nay *u256.Uint `json:"nay"`

	// The version of the config that this proposal was created with
	ConfigVersion uint64

	// The title of the proposal
	Title string `json:"title"`

	// The description of the proposal
	Description string `json:"description"`
}

// Call represents a contract call
type Call struct {
	To       std.Address
	// Selector uint64
	FunctionName string
	Calldata string
}

// hashCalls computes the hash of a list of calls

func hashCalls(calls []Call) string {
	var buf strings.Builder
	buf.WriteString("governance::governor::Governor::hash_calls")

	for _, call := range calls {
		buf.WriteString(string(call.To))
		// buf.WriteString(strconv.FormatUint(call.Selector, 10))
		buf.WriteString(call.FunctionName)
		buf.WriteString(call.Calldata)
	}

	return buf.String()
}

// CallFunction prepresents a function that can be called by the governor
type CallFunction func(...string) (string, error)
