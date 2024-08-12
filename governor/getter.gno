package governor

import (
	"std"

	"gno.land/p/demo/json"
	"gno.land/p/demo/uint256"
	"gno.land/p/demo/ufmt"
)

// TODO: Change returns to primitive types

// GetStaker returns the address of the staker contract used by this governor.
func GetStaker() IStakerDispatcher {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	return gGovernor.staker
}

// GetConfig returns the current configuration of the governor as a JSON string.
func GetConfig() string {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	configNode := json.ObjectNode("", nil)
	config := gGovernor.config

	err := configNode.AppendObject("VotingStartDelay", json.NumberNode("VotingStartDelay", float64(config.VotingStartDelay)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}
	err = configNode.AppendObject("VotingPeriod", json.NumberNode("VotingPeriod", float64(config.VotingPeriod)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}
	err = configNode.AppendObject("VotingWeightSmoothingDuration", json.NumberNode("VotingWeightSmoothingDuration", float64(config.VotingWeightSmoothingDuration)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}
	err = configNode.AppendObject("Quorum", json.NumberNode("Quorum", float64(config.Quorum)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}
	err = configNode.AppendObject("ProposalCreationThreshold", json.NumberNode("ProposalCreationThreshold", float64(config.ProposalCreationThreshold)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}
	err = configNode.AppendObject("ExecutionDelay", json.NumberNode("ExecutionDelay", float64(config.ExecutionDelay)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}
	err = configNode.AppendObject("ExecutionWindow", json.NumberNode("ExecutionWindow", float64(config.ExecutionWindow)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}

	b, err := json.Marshal(configNode)
	if err != nil {
		panic(ufmt.Sprintf("JSON marshal error: %v", err))
	}

	return string(b)
}

// GetConfigWithVersion returns the current configuration of the governor
// along with its version.
func GetConfigWithVersion() string {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	configWithVersionNode := json.ObjectNode("", nil)

	err := configWithVersionNode.AppendObject("config", json.StringNode("config", GetConfig()))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}

	err = configWithVersionNode.AppendObject("version", json.NumberNode("version", float64(gGovernor.latestConfigVersion)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}

	b, err := json.Marshal(configWithVersionNode)
	if err != nil {
		panic(ufmt.Sprintf("JSON marshal error: %v", err))
	}

	return string(b)
}

// GetProposal returns the imformation for a specific proposal.
func GetProposal(id string) string {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	prop, exists := gGovernor.proposals[id]
	if !exists {
		panic("proposal not found")
	}

	propNode := json.ObjectNode("", nil)

	err := propNode.AppendObject("call_hash", json.StringNode("call_hash", prop.CallsHash))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}
	err = propNode.AppendObject("proposer", json.StringNode("proposer", prop.Proposer.String()))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}

	execStatNode := json.ObjectNode("", nil)
	err = execStatNode.AppendObject("created", json.NumberNode("created", float64(prop.ExecutionState.Created)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}
	err = execStatNode.AppendObject("executed", json.NumberNode("executed", float64(prop.ExecutionState.Executed)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}
	err = execStatNode.AppendObject("canceled", json.NumberNode("canceled", float64(prop.ExecutionState.Canceled)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}

	err = propNode.AppendObject("execution_state", execStatNode)
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}

	err = propNode.AppendObject("yea", json.NumberNode("yea", float64(prop.Yea.Uint64())))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}

	err = propNode.AppendObject("nay", json.NumberNode("nay", float64(prop.Nay.Uint64())))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}

	err = propNode.AppendObject("config_version", json.NumberNode("config_version", float64(prop.ConfigVersion)))
	if err != nil {
		panic(ufmt.Sprintf("Error appending to JSON object: %v", err))
	}

	b, err := json.Marshal(propNode)
	if err != nil {
		panic(ufmt.Sprintf("JSON marshal error: %v", err))
	}

	return string(b)
}

// func GetProposal(id string) ProposalInfo {
// 	if gGovernor == nil {
// 		panic("governor not initialized")
// 	}

// 	prop, exists := gGovernor.proposals[id]
// 	if !exists {
// 		panic("proposal not found")
// 	}

// 	return prop
// }

// GetProposalWithConfig returns the information for a specific proposal along with the configuration
// that was in effect when the proposal was created.
func GetProposalWithConfig(id string) (ProposalInfo, Config) {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	prop, exists := gGovernor.proposals[id]
	if !exists {
		panic("proposal not found")
	}

	config := GetConfigVersion(prop.ConfigVersion)
	return prop, config
}

// GetVote returns the vote cast by a specific voter for a specific proposal.
// Retuerns:
// 0 - Not voted
// 1 - Voted against
// 3 - Voted in favor
func GetVote(id string, voter std.Address) uint8 {
	if gGovernor == nil {
		panic("governor not initialized")
	}

	votes, exists := gGovernor.vote[id]
	if !exists {
		return 0 // Not voted
	}

	return votes[voter]
}
