package staker

import (
	"time"

	u256 "gno.land/p/demo/uint256"
)

type IStaker interface {
	// StakeAmount stakes the specified amount for the given delegate
	StakeAmount(delegate string, amount *u256.Uint) error

	// WithdrawAmount withdraws the specified amount from the given delegate to the recipient
	WithdrawAmount(delegate string, recipient string, amount *u256.Uint) error

	// GetAverageDelegated returns the average delegated amount for the given delegate over the specified period
	GetAverageDelegated(delegate string, start time.Time, end time.Time) (*u256.Uint, error)

	// GetAverageDelegatedOverLast returns the average delegated amount for the given delegate over the last specified duration
	GetAverageDelegatedOverLast(delegate string, duration time.Duration) (*u256.Uint, error)

	// GetCurrentDelegated returns the current delegated amount for the given delegate
	GetCurrentDelegated(delegate string) (*u256.Uint, error)

	// GetDelegatedAt returns the delegated amount for the given delegate at the specified timestamp
	GetDelegatedAt(delegate string, timestamp time.Time) (*u256.Uint, error)
}
