package staker

import (
	"errors"
	"std"
	"strconv"
	"time"

	"gno.land/p/demo/grc/grc20"
	u256 "gno.land/p/demo/uint256"
)

var (
	ErrInsufficientBalance = errors.New("insufficient balance")
	ErrUnauthorized        = errors.New("unauthorized")
	ErrInvalidTimeRange    = errors.New("invalid time range")
	ErrNoData              = errors.New("no delegation data for the given period")
)

// DelegationHistory represents a single delegation event
type DelegationHistory struct {
	amount    *u256.Uint
	timestamp uint64
}

// staking contract
type Staker struct {
	token             grc20.IGRC20
	delegations       map[std.Address]*u256.Uint
	delegationHistory map[std.Address][]DelegationHistory
	totalStaked       *u256.Uint
}

func New(token grc20.IGRC20) *Staker {
	return &Staker{
		token:             token,
		delegations:       make(map[std.Address][]*u256.Uint),
		delegationHistory: make(map[std.Address][]DelegationHistory),
		totalStaked:       u256.NewUint(0),
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

// WithdrawAmount withdraws the specified amount from the given delegate to the recipient
func (s *Staker) WithdrawAmount(
	delegate std.Address,
	recipient std.Address,
	amount *u256.Uint,
) error {
	caller := std.GetOrigCaller()

	// Check if the caller is the delegate
	if caller != delegate {
		return ErrUnauthorized
	}

	// delegate must have enough balance
	currentStake, exists := s.delegations[delegate]
	if !exists || currentStake.Cmp(amount) < 0 {
		return ErrInsufficientBalance
	}

	// update delegations
	s.delegations[delegate] = u256.NewUint(0).Sub(currentStake, amount)

	// update total staked
	s.totalStaked = u256.NewUint(0).Sub(s.totalStaked, amount)

	// transfer tokens from this contract to recipient
	err := s.token.Transfer(recipient, amount.Uint64())
	if err != nil {
		return err
	}

	// update delegation history
	s.delegationHistory[delegate] = append(s.delegationHistory[delegate], DelegationHistory{
		amount:    s.delegations[delegate].Clone(),
		timestamp: uint64(time.Now().Unix()),
	})

	return nil
}

// GetDelegatedCumulative gets the cumulative delegated amount * seconds for an address at a certain timestamp.
func (s *Staker) GetDelegatedCumulative(delegate std.Address, timestamp uint64) (*u256.Uint, error) {
	if timestamp > uint64(time.Now().Unix()) {
		return nil, errors.New("FUTURE")
	}

	history, exists := s.delegationHistory[delegate]
	if !exists || len(history) == 0 {
		return u256.NewUint(0), nil
	}

	var lastSnapshot DelegationHistory
	var cumulativeAmount u256.Uint

	for _, snapshot := range history {
		if snapshot.timestamp > timestamp {
			break
		}
		if lastSnapshot.timestamp != 0 {
			duration := snapshot.timestamp - lastSnapshot.timestamp
			cumulativeAmount.Add(&cumulativeAmount, u256.NewUint(0).Mul(lastSnapshot.amount, u256.NewUint(duration)))
		}
		lastSnapshot = snapshot
	}

	if lastSnapshot.timestamp < timestamp {
		duration := timestamp - lastSnapshot.timestamp
		cumulativeAmount.Add(&cumulativeAmount, u256.NewUint(0).Mul(lastSnapshot.amount, u256.NewUint(duration)))
	}

	return &cumulativeAmount, nil
}

// GetAverageDelegated calculates the average delegated amount for a delegate over a given period
func (s *Staker) GetAverageDelegated(delegate std.Address, start, end uint64) (*u256.Uint, error) {
	if start > end {
		return nil, errors.New("invalid time range")
	}

	history, exists := s.delegationHistory[delegate]
	if !exists || len(history) == 0 {
		return u256.NewUint(0), nil
	}

	if start >= history[len(history)-1].timestamp {
		return history[len(history)-1].amount.Clone(), nil
	}

	if end <= history[0].timestamp {
		return u256.NewUint(0), nil
	}

	var (
		totalAmount   u256.Uint
		lastAmount    *u256.Uint
		lastTimestamp uint64
	)

	for i, record := range history {
		if record.timestamp > end {
			break
		}

		if i == 0 {
			if record.timestamp > start {
				totalAmount.Add(&totalAmount, u256.NewUint(0).Mul(record.amount, u256.NewUint(record.timestamp-start)))
			}
		} else {
			if record.timestamp > start {
				duration := record.timestamp - maxUint64(start, lastTimestamp)
				totalAmount.Add(&totalAmount, u256.NewUint(0).Mul(lastAmount, u256.NewUint(duration)))
			}
		}

		lastAmount = record.amount
		lastTimestamp = record.timestamp
	}

	if lastTimestamp < end {
		duration := end - maxUint64(start, lastTimestamp)
		totalAmount.Add(&totalAmount, u256.NewUint(0).Mul(lastAmount, u256.NewUint(duration)))
	}

	totalDuration := end - start
	if totalDuration == 0 {
		return lastAmount.Clone(), nil
	}

	return u256.NewUint(0).Div(&totalAmount, u256.NewUint(totalDuration)), nil
}

// GetAverageDelegatedOverLast gets the average amount delegated over the last period seconds.
func (s *Staker) GetAverageDelegatedOverLast(delegate std.Address, period uint64) (*u256.Uint, error) {
	now := uint64(time.Now().Unix())
	return s.GetAverageDelegated(delegate, now-period, now)
}

// GetCurrentDelegated returns the current delegated amount for a delegate
func (s *Staker) GetCurrentDelegated(delegate std.Address) (*u256.Uint, error) {
	history, exists := s.delegationHistory[delegate]
	if !exists || len(history) == 0 {
		return u256.NewUint(0), nil
	}

	lastEntry := history[len(history)-1]
	return lastEntry.amount.Clone(), nil
}

func (s *Staker) GetDelegatedAt(delegate std.Address, timestamp uint64) (*u256.Uint, error) {
	history, exists := s.delegationHistory[delegate]
	if !exists || len(history) == 0 {
		return u256.NewUint(0), nil
	}

	for i := len(history) - 1; i >= 0; i-- {
		if history[i].timestamp <= timestamp {
			return history[i].amount.Clone(), nil
		}
	}

	return u256.NewUint(0), nil
}

func maxUint64(a, b uint64) uint64 {
	if a > b {
		return a
	}
	return b
}
