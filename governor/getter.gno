package governor

// import (
// 	"std"

// 	"gno.land/p/demo/uint256"
// )

// // GetStaker returns the address of the staker contract used by this governor.
// func GetStaker() IStakerDispatcher {
// 	if gGovernor == nil {
// 		panic("governor not initialized")
// 	}

// 	return gGovernor.staker
// }

// // GetConfig returns the current configuration of the governor.
// func GetConfig() Config {
// 	if gGovernor == nil {
// 		panic("governor not initialized")
// 	}

// 	return gGovernor.config
// }

// // GetConfigWithVersion returns the current configuration of the governor
// // along with its version.
// func GetConfigWithVersion() (Config, uint64) {
// 	if gGovernor == nil {
// 		panic("governor not initialized")
// 	}

// 	return gGovernor.config, gGovernor.latestConfigVersion
// }

// // GetProposal returns the imformation for a specific proposal.
// func GetProposal(id [32]byte) ProposalInfo {
// 	if gGovernor == nil {
// 		panic("governor not initialized")
// 	}

// 	prop, exists := gGovernor.proposals[id]
// 	if !exists {
// 		panic("proposal not found")
// 	}

// 	return prop
// }

// // GetProposalWithConfig returns the information for a specific proposal along with the configuration
// // that was in effect when the proposal was created.
// func GetProposalWithConfig(id [32]byte) (ProposalInfo, Config) {
// 	if gGovernor == nil {
// 		panic("governor not initialized")
// 	}

// 	prop, exists := gGovernor.proposals[id]
// 	if !exists {
// 		panic("proposal not found")
// 	}

// 	config := GetConfigVersion(prop.ConfigVersion)
// 	return prop, config
// }

// // GetVote returns the vote cast by a specific voter for a specific proposal.
// // Retuerns:
// // 0 - Not voted
// // 1 - Voted against
// // 3 - Voted in favor
// func GetVote(id [32]byte, voter std.Address) uint8 {
// 	if gGovernor == nil {
// 		panic("governor not initialized")
// 	}

// 	votes, exists := gGovernor.vote[id]
// 	if !exists {
// 		return 0 // Not voted
// 	}

// 	return votes[voter]
// }
