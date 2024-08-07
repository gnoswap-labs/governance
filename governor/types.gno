package governor

import (
	"std"

	u256 "gno.land/p/demo/uint256"
)

// Governor represents the governor contract
type Governor struct {
    // staker is the interface to interact with the staking contract
    staker IStakerDispatcher

    // config is the current configuration of the governor
    config Config

    // configVersions stores all historical configurations indexed by their version number
    configVersions map[uint64]Config

    // latestConfigVersion is the version number of the most recent configuration
    latestConfigVersion uint64

    // nonce is used to generate unique proposal IDs
    nonce uint64

    // proposals stores all proposals indexed by their ID
    proposals map[string]ProposalInfo

    // latestProposalByProposer keeps track of the latest proposal ID for each proposer
    latestProposalByProposer map[std.Address]string

    // vote stores the voting information for each proposal
    // The uint8 value represents: 0 = not voted, 2 = voted no, 3 = voted yes
    vote map[string]map[std.Address]uint8
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
	CallsHash string

	// The address of the proposer
	Proposer std.Address

	// The execution state of the proposal
	ExecutionState ExecutionState

	// How many yes votes have been collected
	Yea *u256.Uint // TODO: u64

	// How many no votes have been collected
	Nay *u256.Uint // TODO: u64

	// The version of the config that this proposal was created with
	ConfigVersion uint64
}

// CallFunction prepresents a function that can be called by the governor
type CallFunction func([]byte) ([]byte, error)
