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

var gStaker *Staker

func Init(token grc20.IGRC20) {
	gStaker = &Staker{
		token:             token,
		delegations:       make(map[std.Address]*u256.Uint),
		delegationHistory: make(map[std.Address][]DelegationHistory),
		totalStaked:       u256.Zero(),
	}
}

// StakeAmount stakes the specified amount for the given delegate
func StakeAmount(delegate std.Address, amount *u256.Uint) error {
	caller := std.GetOrigCaller()

	// Check if the caller has enough balance
	balance, err := gStaker.token.BalanceOf(caller)
	if err != nil {
		panic(err)
	}
	if u256.NewUint(balance).Cmp(amount) < 0 {
		panic(ErrInsufficientBalance)
	}

	// Transfer tokens from caller to this contract
	err = gStaker.token.TransferFrom(caller, std.GetOrigPkgAddr(), amount.Uint64())
	if err != nil {
		panic(err)
	}

	// Update delegations
	if gStaker.delegations[delegate] == nil {
		gStaker.delegations[delegate] = u256.Zero()
	}
	gStaker.delegations[delegate] = u256.Zero().Add(gStaker.delegations[delegate], amount)

	// Update total staked
	gStaker.totalStaked = u256.Zero().Add(gStaker.totalStaked, amount)

	// Update delegation history
	gStaker.delegationHistory[delegate] = append(gStaker.delegationHistory[delegate], DelegationHistory{
		amount:    gStaker.delegations[delegate].Clone(),
		timestamp: uint64(time.Now().Unix()),
	})

	return nil
}

// WithdrawAmount withdraws the specified amount from the given delegate to the recipient
func WithdrawAmount(delegate std.Address, recipient std.Address, amount *u256.Uint) error {
	caller := std.GetOrigCaller()

	// Check if the caller is the delegate
	if caller != delegate {
		panic(ErrUnauthorized)
	}

	// delegate must have enough balance
	currentStake, exists := gStaker.delegations[delegate]
	if !exists || currentStake.Cmp(amount) < 0 {
		panic(ErrInsufficientBalance)
	}

	// update delegations
	gStaker.delegations[delegate] = u256.Zero().Sub(currentStake, amount)

	// update total staked
	gStaker.totalStaked = u256.Zero().Sub(gStaker.totalStaked, amount)

	// transfer tokens from this contract to recipient
	err := gStaker.token.Transfer(recipient, amount.Uint64())
	if err != nil {
		panic(err)
	}

	// update delegation history
	gStaker.delegationHistory[delegate] = append(gStaker.delegationHistory[delegate], DelegationHistory{
		amount:    gStaker.delegations[delegate].Clone(),
		timestamp: uint64(time.Now().Unix()),
	})

	return nil
}

// GetDelegatedCumulative gets the cumulative delegated amount * seconds for an address at a certain timestamp.
func GetDelegatedCumulative(delegate std.Address, timestamp uint64) (*u256.Uint, error) {
	if timestamp > uint64(time.Now().Unix()) {
		panic("FUTURE")
	}

	history, exists := gStaker.delegationHistory[delegate]
	if !exists || len(history) == 0 {
		return u256.Zero(), nil
	}

	var lastSnapshot DelegationHistory
	var cumulativeAmount u256.Uint

	for _, snapshot := range history {
		if snapshot.timestamp > timestamp {
			break
		}
		if lastSnapshot.timestamp != 0 {
			duration := snapshot.timestamp - lastSnapshot.timestamp
			cumulativeAmount.Add(&cumulativeAmount, u256.Zero().Mul(lastSnapshot.amount, u256.NewUint(duration)))
		}
		lastSnapshot = snapshot
	}

	if lastSnapshot.timestamp < timestamp {
		duration := timestamp - lastSnapshot.timestamp
		cumulativeAmount.Add(&cumulativeAmount, u256.Zero().Mul(lastSnapshot.amount, u256.NewUint(duration)))
	}

	return &cumulativeAmount, nil
}

// GetAverageDelegated calculates the average delegated amount for a delegate over a given period
func GetAverageDelegated(delegate std.Address, start, end uint64) (*u256.Uint, error) {
	if start > end {
		panic(ErrInvalidTimeRange)
	}

	history, exists := gStaker.delegationHistory[delegate]
	if !exists || len(history) == 0 {
		return u256.Zero(), nil
	}

	if start >= history[len(history)-1].timestamp {
		return history[len(history)-1].amount.Clone(), nil
	}

	if end <= history[0].timestamp {
		return u256.Zero(), nil
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
				totalAmount.Add(&totalAmount, u256.Zero().Mul(record.amount, u256.NewUint(record.timestamp-start)))
			}
		} else {
			if record.timestamp > start {
				duration := record.timestamp - maxUint64(start, lastTimestamp)
				totalAmount.Add(&totalAmount, u256.Zero().Mul(lastAmount, u256.NewUint(duration)))
			}
		}

		lastAmount = record.amount
		lastTimestamp = record.timestamp
	}

	if lastTimestamp < end {
		duration := end - maxUint64(start, lastTimestamp)
		totalAmount.Add(&totalAmount, u256.Zero().Mul(lastAmount, u256.NewUint(duration)))
	}

	totalDuration := end - start
	if totalDuration == 0 {
		return lastAmount.Clone(), nil
	}

	return u256.Zero().Div(&totalAmount, u256.NewUint(totalDuration)), nil
}

// GetAverageDelegatedOverLast gets the average amount delegated over the last period seconds.
func GetAverageDelegatedOverLast(delegate std.Address, period uint64) (*u256.Uint, error) {
	now := uint64(time.Now().Unix())
	return GetAverageDelegated(delegate, now-period, now)
}

// GetCurrentDelegated returns the current delegated amount for a delegate
func GetCurrentDelegated(delegate std.Address) (*u256.Uint, error) {
	history, exists := gStaker.delegationHistory[delegate]
	if !exists || len(history) == 0 {
		return u256.Zero(), nil
	}

	lastEntry := history[len(history)-1]
	return lastEntry.amount.Clone(), nil
}

func GetDelegatedAt(delegate std.Address, timestamp uint64) (*u256.Uint, error) {
	history, exists := gStaker.delegationHistory[delegate]
	if !exists || len(history) == 0 {
		return u256.Zero(), nil
	}

	for i := len(history) - 1; i >= 0; i-- {
		if history[i].timestamp <= timestamp {
			return history[i].amount.Clone(), nil
		}
	}

	return u256.Zero(), nil
}

func maxUint64(a, b uint64) uint64 {
	if a > b {
		return a
	}
	return b
}
