package staker

import (
	"std"

	u256 "gno.land/p/demo/uint256"
)

type IStaker interface {
	// StakeAmount stakes the specified amount for the given delegate
	StakeAmount(delegate std.Address, amount *u256.Uint) error

	// WithdrawAmount withdraws the specified amount from the given delegate to the recipient
	WithdrawAmount(delegate std.Address, recipient std.Address, amount *u256.Uint) error

	// GetAverageDelegated returns the average delegated amount for the given delegate over the specified period
	GetAverageDelegated(delegate std.Address, start uint64, end uint64) (*u256.Uint, error)

	// GetAverageDelegatedOverLast returns the average delegated amount for the given delegate over the last specified duration
	GetAverageDelegatedOverLast(delegate std.Address, duration uint64) (*u256.Uint, error)

	// GetCurrentDelegated returns the current delegated amount for the given delegate
	GetCurrentDelegated(delegate std.Address) (*u256.Uint, error)

	// GetDelegatedAt returns the delegated amount for the given delegate at the specified timestamp
	GetDelegatedAt(delegate std.Address, timestamp uint64) (*u256.Uint, error)
}
