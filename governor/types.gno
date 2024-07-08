package governor

import (
	"std"

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

// CallFunction prepresents a function that can be called by the governor
type CallFunction func([]byte) ([]byte, error)
