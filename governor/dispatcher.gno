package governor

import (
	"std"

	"gno.land/p/demo/uint256"
)

// IStakerDispatcher defines the interface for interacting with the Staker contract
type IStakerDispatcher interface {
	// StakeAmount stakes the specified amount for the given delegate
	StakeAmount(delegate std.Address, amount *uint256.Uint) error

	// WithdrawAmount withdraws the specified amount from the given delegate to the recipient
	WithdrawAmount(delegate std.Address, recipient std.Address, amount *uint256.Uint) error

	// GetDelegatedCumulative gets the cumulative delegated amount * seconds for an address at a certain timestamp
	GetDelegatedCumulative(delegate std.Address, timestamp uint64) (*uint256.Uint, error)

	// GetAverageDelegated calculates the average delegated amount for a delegate over a given period
	GetAverageDelegated(delegate std.Address, start, end uint64) (*uint256.Uint, error)

	// GetAverageDelegatedOverLast gets the average amount delegated over the last period seconds
	GetAverageDelegatedOverLast(delegate std.Address, period uint64) (*uint256.Uint, error)

	// GetCurrentDelegated returns the current delegated amount for a delegate
	GetCurrentDelegated(delegate std.Address) (*uint256.Uint, error)

	// GetDelegatedAt returns the delegated amount for a delegate at a specific timestamp
	GetDelegatedAt(delegate std.Address, timestamp uint64) (*uint256.Uint, error)
}
