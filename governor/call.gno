package governor

import (
	"std"

	u256 "gno.land/p/demo/uint256"
)

type Call struct {
	To std.Address		// The address of the contract to call
	Selector uint64		// the selector of the function to call
	Calldata []u256.Uint // the calldata for the function call
}

// Execute executes the call
func (c *Call) Execute() ([]u256.Uint, error) {
	// TODO
	return nil, nil
}