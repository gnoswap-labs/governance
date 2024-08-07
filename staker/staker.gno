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
	token             grc20.Token
	delegations       map[std.Address]*u256.Uint
	delegationHistory map[std.Address][]DelegationHistory
	totalStaked       *u256.Uint
}

var gStaker *Staker

func Init(token grc20.Token) {
	gStaker = &Staker{
		token:             token,
		delegations:       make(map[std.Address]*u256.Uint),
		delegationHistory: make(map[std.Address][]DelegationHistory),
		totalStaked:       u256.Zero(),
	}
}

// StakeAmount stakes the specified amount for the given delegate
func StakeAmount(delegate, amount string) error {
	delegateAddr := std.Address(delegate)
	amountUint, err := u256.FromDecimal(amount)
	if err != nil {
		panic(err)
	}

	caller := std.GetOrigCaller()

	// Check if the caller has enough balance
	balance := gStaker.token.BalanceOf(caller)
	if u256.NewUint(balance).Cmp(amountUint) < 0 {
		panic(ErrInsufficientBalance)
	}

	// Transfer tokens from caller to this contract
	err = gStaker.token.TransferFrom(caller, std.GetOrigPkgAddr(), amountUint.Uint64())
	if err != nil {
		panic(err)
	}

	// Update delegations
	if gStaker.delegations[delegateAddr] == nil {
		gStaker.delegations[delegateAddr] = u256.Zero()
	}
	gStaker.delegations[delegateAddr] = u256.Zero().Add(gStaker.delegations[delegateAddr], amountUint)

	// Update total staked
	gStaker.totalStaked = u256.Zero().Add(gStaker.totalStaked, amountUint)

	// Update delegation history
	gStaker.delegationHistory[delegateAddr] = append(gStaker.delegationHistory[delegateAddr], DelegationHistory{
		amount:    gStaker.delegations[delegateAddr].Clone(),
		timestamp: uint64(time.Now().Unix()),
	})

	return nil
}

// WithdrawAmount withdraws the specified amount from the given delegate to the recipient
func WithdrawAmount(delegate, recipient, amount string) error {
	delegateAddr := std.Address(delegate)
    recipientAddr := std.Address(recipient)

    amountUint, err := u256.FromDecimal(amount)
	if err != nil {
		panic(err)
	}

	caller := std.GetOrigCaller()

	// Check if the caller is the delegate
	if caller != delegateAddr {
		panic(ErrUnauthorized)
	}

	if caller != std.PrevRealm().Addr() {
		panic(ErrUnauthorized)
	}

	// delegate must have enough balance
	currentStake, exists := gStaker.delegations[delegateAddr]
	if !exists || currentStake.Cmp(amountUint) < 0 {
		panic(ErrInsufficientBalance)
	}

	// update delegations
	gStaker.delegations[delegateAddr] = u256.Zero().Sub(currentStake, amountUint)

	// update total staked
	gStaker.totalStaked = u256.Zero().Sub(gStaker.totalStaked, amountUint)

	// transfer tokens from this contract to recipient
	err = gStaker.token.Transfer(recipientAddr, amountUint.Uint64())
	if err != nil {
		panic(err)
	}

	// update delegation history
	gStaker.delegationHistory[delegateAddr] = append(gStaker.delegationHistory[delegateAddr], DelegationHistory{
		amount:    gStaker.delegations[delegateAddr].Clone(),
		timestamp: uint64(time.Now().Unix()),
	})

	return nil
}

// GetDelegatedCumulative gets the cumulative delegated amount * seconds for an address at a certain timestamp.
func GetDelegatedCumulative(delegate string, timestamp uint64) (string, error) {
	delegateAddr := std.Address(delegate)

	if timestamp > uint64(time.Now().Unix()) {
		panic("FUTURE")
	}

	history, exists := gStaker.delegationHistory[delegateAddr]
	if !exists || len(history) == 0 {
		return u256.Zero().ToString(), nil
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

	return cumulativeAmount.ToString(), nil
}

// GetAverageDelegated calculates the average delegated amount for a delegate over a given period
func GetAverageDelegated(delegate string, start, end uint64) (string, error) {
	delegateAddr := std.Address(delegate)
	res := u256.Zero()

	if start > end {
		panic(ErrInvalidTimeRange)
	}

	history, exists := gStaker.delegationHistory[delegateAddr]
	if !exists || len(history) == 0 {
		return res.ToString(), nil
	}

	if start >= history[len(history)-1].timestamp {
		res = history[len(history)-1].amount.Clone()
		return res.ToString(), nil
	}

	if end <= history[0].timestamp {
		return res.ToString(), nil
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
		res = lastAmount.Clone()
		return res.ToString(), nil
	}

	res = u256.Zero().Div(&totalAmount, u256.NewUint(totalDuration))
	return res.ToString(), nil
}

// GetAverageDelegatedOverLast gets the average amount delegated over the last period seconds.
func GetAverageDelegatedOverLast(delegate string, period uint64) (string, error) {
	now := uint64(time.Now().Unix())
	return GetAverageDelegated(delegate, now-period, now)
}

// GetCurrentDelegated returns the current delegated amount for a delegate
func GetCurrentDelegated(delegate string) (string, error) {
	res := u256.Zero()
	history, exists := gStaker.delegationHistory[std.Address(delegate)]
	if !exists || len(history) == 0 {
		return res.ToString(), nil
	}

	lastEntry := history[len(history)-1]
	res = lastEntry.amount.Clone()
	return res.ToString(), nil
}

func GetDelegatedAt(delegate string, timestamp uint64) (string, error) {
	res := u256.Zero()
	delegateAddr := std.Address(delegate)

	history, exists := gStaker.delegationHistory[delegateAddr]
	if !exists || len(history) == 0 {
		return res.ToString(), nil
	}

	for i := len(history) - 1; i >= 0; i-- {
		if history[i].timestamp <= timestamp {
			res = history[i].amount.Clone()
			return res.ToString(), nil
		}
	}

	return res.ToString(), nil
}

func maxUint64(a, b uint64) uint64 {
	if a > b {
		return a
	}
	return b
}
