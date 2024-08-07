package governor

import (
    "std"
    "strconv"
    "strings"
    "gno.land/p/demo/json"
    "gno.land/p/demo/ufmt"
)

func parseCallsFromJSON(node *json.Node) ([]Call, error) {
	if !node.IsArray() {
		return nil, ufmt.Errorf("calls must be an array")
	}

	var calls []Call
	node.ArrayEach(func(i int, callNode *json.Node) {
		call, err := parseCall(callNode)
		if err != nil {
			panic(err)
		}
		calls = append(calls, call)
	})

	return calls, nil
}

func parseCall(node *json.Node) (Call, error) {
    if !node.IsObject() {
        return Call{}, ufmt.Errorf("call must be an object")
    }

    var call Call
    var err error

    toNode := node.MustKey("to")
    if !toNode.IsString() {
        return Call{}, ufmt.Errorf("'to' must be a string")
    }
    call.To = std.Address(toNode.MustString())

    selectorNode := node.MustKey("selector")
    if !selectorNode.IsNumber() {
        return Call{}, ufmt.Errorf("'selector' must be a number")
    }
    call.Selector, err = parseUint(selectorNode.String(), 10, 64)
    if err != nil {
        return Call{}, ufmt.Errorf("invalid 'selector': %v", err)
    }

    calldataNode := node.MustKey("calldata")
    if !calldataNode.IsString() {
        return Call{}, ufmt.Errorf("'calldata' must be a string")
    }
    calldataStr := calldataNode.MustString()
    call.Calldata = []byte(calldataStr)

    return call, nil
}
