package governor

import (
	"std"
	"strconv"
	"strings"

	"gno.land/p/demo/json"
	"gno.land/p/demo/ufmt"
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

	// parse `selector` field: must be a number type
	selectorNode := node.MustKey("selector")
	if !selectorNode.IsNumber() {
		return Call{}, ufmt.Errorf("'selector' must be a number")
	}
	call.Selector, err = parseUint(selectorNode.String(), 10, 64)
	if err != nil {
		return Call{}, ufmt.Errorf("invalid 'selector': %v", err)
	}

	// parse `calldata` field: must be a string type, will be coneverted to a byte slice
	calldataNode := node.MustKey("calldata")
	if !calldataNode.IsString() {
		return Call{}, ufmt.Errorf("'calldata' must be a string")
	}
	calldataStr := calldataNode.MustString()
	call.Calldata = []byte(calldataStr)

	return call, nil
}
