package staker

import (
	"errors"
	"std"
	"time"

	"gno.land/p/demo/grc/grc20"
	u256 "gno.land/p/demo/uint256"
)

var (
	ErrInsufficientBalance = errors.New("insufficient balance")
)

// DelegationHistory represents a single delegation event
type DelegationHistory struct {
	amount *u256.Uint
	timestamp uint64
}

// staking contract
type Staker struct {
	token grc20.IGRC20
	delegations map[std.Address]*u256.Uint
	delegationHistory map[std.Address][]DelegationHistory
	totalStaked *u256.Uint
}

func New(token grc20.IGRC20) *Staker {
	return &Staker{
		token: token,
		delegations: make(map[std.Address][]*u256.Uint),
		delegationHistory: make(map[std.Address][]DelegationHistory),
		totalStaked: u256.NewUint(0),
	}
}

// StakeAmount stakes the specified amount for the given delegate
func (s *Staker) StakeAmount(delegate std.Address, amount *u256.Uint) error {
	caller := std.GetOrigCaller()
	
	// Check if the caller has enough balance
	balance, err := s.token.BalanceOf(caller)
	if err != nil {
		return err
	}
	if u256.NewUint(balance).Cmp(amount) < 0 {
		return ErrInsufficientBalance
	}

	// Transfer tokens from caller to this contract
	err = s.token.TransferFrom(caller, std.GetOrigPkgAddr(), amount.Uint64())
	if err != nil {
		return err
	}

	// Update delegations
	if s.delegations[delegate] == nil {
		s.delegations[delegate] = u256.NewUint(0)
	}
	s.delegations[delegate] = u256.NewUint(0).Add(s.delegations[delegate], amount)

	// Update total staked
	s.totalStaked = u256.NewUint(0).Add(s.totalStaked, amount)

	// Update delegation history
	s.delegationHistory[delegate] = append(s.delegationHistory[delegate], DelegationHistory{
		amount:    s.delegations[delegate].Clone(),
		timestamp: uint64(time.Now().Unix()),
	})

	return nil
}
