package governor

import (
	"std"
	"strconv"
	"strings"

	"gno.land/p/demo/json"
	"gno.land/p/demo/ufmt"
	u256 "gno.land/p/demo/uint256"
)

// parseCallsFromJSON converts a JSON array of calls into a slice of Call structs.
// The input JSON should be an array of objects, each representing a single call.
//
// Example JSON input:
// [
//
//	{
//	  "to": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5",
//	  "selector": 1,
//	  "calldata": "test_data"
//	},
//	{
//	  "to": "g1sss7jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj",
//	  "selector": 2,
//	  "calldata": "more_test_data"
//	}
//
// ]
//
// Returns a slice of Call structs and an error if parsing fails.
func parseCallsFromJSON(node *json.Node) ([]Call, error) {
	if !node.IsArray() {
		return nil, ufmt.Errorf("calls must be an array")
	}

	var calls []Call
	// iterate over each element in the array
	node.ArrayEach(func(i int, callNode *json.Node) {
		// parse each call object
		call, err := parseCall(callNode)
		if err != nil {
			panic(err)
		}
		calls = append(calls, call)
	})

	return calls, nil
}

// parseCall converts a single JSON object representing a call into a Call struct.
// The input JSON object should have the following structure:
//
//	{
//	  "to": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5",
//	  "selector": 1,
//	  "calldata": "test_data"
//	}
//
// Returns a Call struct and an error if parsing fails.
func parseCall(node *json.Node) (Call, error) {
	if !node.IsObject() {
		return Call{}, ufmt.Errorf("call must be an object")
	}

	var call Call
	var err error

	// parse `to` field: must be string type representing an address
	toNode := node.MustKey("to")
	if !toNode.IsString() {
		return Call{}, ufmt.Errorf("'to' must be a string")
	}
	call.To = std.Address(toNode.MustString())

	functionNameNode := node.MustKey("function_name")
	if !functionNameNode.IsString() {
		return Call{}, ufmt.Errorf("'function_name' must be a string")
	}
	call.FunctionName = functionNameNode.MustString()

	// parse `calldata` field: must be a string type, will be coneverted to a byte slice
	calldataNode := node.MustKey("calldata")
	if !calldataNode.IsString() {
		return Call{}, ufmt.Errorf("'calldata' must be a string")
	}
	calldataStr := calldataNode.MustString()
	call.Calldata = calldataStr

	return call, nil
}

// parseConfig converts a JSON Node representing a config into a Config struct.
// The input JSON object should have the following structure:
//
//	{
//	  "votingStartDelay": 100,
//	  "votingPeriod": 1000,
//	  "votingWeightSmoothingDuration": 100,
//	  "quorum": "500",
//	  "proposalCreationThreshold": "100",
//	  "executionDelay": 100,
//	  "executionWindow": 1000
//	}
//
// Returns a Config struct and an error if parsing fails.
func parseConfig(node *json.Node) (Config, error) {
	if !node.IsObject() {
		return Config{}, ufmt.Errorf("config must be an object")
	}

	var config Config
	var err error

	config.VotingStartDelay, err = parseUint64Field(node, "votingStartDelay")
	if err != nil {
		return Config{}, err
	}

	config.VotingPeriod, err = parseUint64Field(node, "votingPeriod")
	if err != nil {
		return Config{}, err
	}

	config.VotingWeightSmoothingDuration, err = parseUint64Field(node, "votingWeightSmoothingDuration")
	if err != nil {
		return Config{}, err
	}

	config.Quorum, err = parseUint64Field(node, "quorum")
	if err != nil {
		return Config{}, err
	}

	config.ProposalCreationThreshold, err = parseUint64Field(node, "proposalCreationThreshold")
	if err != nil {
		return Config{}, err
	}

	config.ExecutionDelay, err = parseUint64Field(node, "executionDelay")
	if err != nil {
		return Config{}, err
	}

	config.ExecutionWindow, err = parseUint64Field(node, "executionWindow")
	if err != nil {
		return Config{}, err
	}

	return config, nil
}

func parseUint64Field(node *json.Node, key string) (uint64, error) {
	fieldName := node.MustKey(key)
	if !fieldName.IsNumber() {
		return 0, ufmt.Errorf("'%s' must be a number", key)
	}
	return parseUint(fieldName.String(), 10, 64)
}

func parseStringField(node *json.Node, key string) (string, error) {
	fieldName := node.MustKey(key)
	if !fieldName.IsString() {
		return "", ufmt.Errorf("'%s' must be a string", key)
	}
	return fieldName.String(), nil
}
