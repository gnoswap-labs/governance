package governor

import (
	"errors"
	"time"

	"gno.land/p/demo/ufmt"
	u256 "gno.land/p/demo/uint256"
	"gno.land/r/demo/merkle"
	"gno.land/r/demo/staker"
)

// ProposalInfo represents the information of a proposal
type ProposalInfo struct {
	CallHash       [32]byte
	Proposer       string
	ExecutionState ExecutionState
	Yes            *u256.Uint
	No             *u256.Uint
	ConfigVersion  uint64
}

// Config represents the configuration of the governor
type Config struct {
	VotingStartDelay           uint64
	VotingPeriod               uint64
	VotingWeightSmoothDuration uint64
	Quorum                     *u256.Uint
	ProposalCreationThreshold  *u256.Uint
	ExecutionDelay             uint64
	ExecutionWindow            uint64
}

// Governor represents the main governor structure
type Governor struct {
	staker                   staker.IStaker
	config                   Config
	configVersions           map[uint64]Config
	latestConfigVersion      uint64
	nonce                    uint64
	proposals                map[[32]byte]ProposalInfo
	latestProposalByProposer map[string][32]byte
	vote                     map[[32]byte]map[string]uint8
}

// IGovernor defines the interface for the governor
type IGovernor interface {
	Propose(calls []Call) ([32]byte, error)
	Vote(id [32]byte, yea bool) error
	Cancel(id [32]byte) error
	Execute(id [32]byte, calls []Call) ([][]byte, error)
	Describe(id [32]byte, description string) error
	ProposeAndDescribe(calls []Call, description string) ([32]byte, error)
	GetStaker() staker.IStaker
	GetConfig() Config
	GetConfigWithVersion() (Config, uint64)
	GetConfigVersion(version uint64) Config
	GetProposal(id [32]byte) (ProposalInfo, error)
	GetProposalWithConfig(id [32]byte) (ProposalInfo, Config, error)
	GetVote(id [32]byte, voter string) uint8
	Reconfigure(config Config) (uint64, error)
	Upgrade(classHash [32]byte) error
}
