// ref: https://docs.gnoswap.io/core-concepts/liquidity-mining#warm-up-periods
package staking

import (
	"errors"
	"std"
	"time"

	u256 "gno.land/p/demo/uint256"
)

const (
	WarmUpPeriod1 = 5 * 24 * time.Hour	// 5 days
	WarmUpPeriod2 = 10 * 24 * time.Hour	// 10 days
	WarmUpPeriod3 = 30 * 24 * time.Hour	// 30 days
)

var (
	Multiplier1 = u256.NewUint(30)  // 0.3
	Multiplier2 = u256.NewUint(50)  // 0.5
	Multiplier3 = u256.NewUint(70)  // 0.7
	Multiplier4 = u256.NewUint(100) // 1.0
)

var (
	gTotalStaked     *u256.Uint
	gStakedPositions []*StakedPosition
	gStakers 	   map[std.Address]bool
	gTotalRewards	*u256.Uint
	gClaimedRewards	map[std.Address]*u256.Uint
)

// StakedPosition represents a single staked position.
type StakedPosition struct {
	Amount    *u256.Uint
	StartTime time.Time
	User std.Address
}

// Init initializes the staking system.
func Init() {
	gTotalStaked = u256.Zero()
	gStakedPositions = make([]*StakedPosition, 0)
	gStakers = make(map[std.Address]bool)
	gTotalRewards = u256.Zero()
	gClaimedRewards = make(map[std.Address]*u256.Uint)
}

// calculateRewardMultiplier calculates the reward multiplier based on the staking duration.
func calculateRewardMultiplier(stakeDuration time.Duration) *u256.Uint {
	switch {
	case stakeDuration < WarmUpPeriod1:
		return Multiplier1
	case stakeDuration < WarmUpPeriod2:
		return Multiplier2
	case stakeDuration < WarmUpPeriod3:
		return Multiplier3
	default:
		return Multiplier4
	}
}

// calculateReward calculates the reward for staked position.
func calculateReward(position *StakedPosition, baseReward *u256.Uint) *u256.Uint {
	stakeDuration := time.Since(position.StartTime)
	multiplier := calculateRewardMultiplier(stakeDuration)

	// multiply the base reward by multiplier
	// (divided by 100 as multipliers are in percentage)
	adjuestedReward := u256.Zero().Mul(baseReward, multiplier)
	return u256.Zero().Div(adjuestedReward, u256.NewUint(100))
}

// Stake adds a new staking position.
func Stake(amount *u256.Uint) error {
	if amount.IsZero() {
		return errors.New("cannot stake zero amount")
	}

	position := &StakedPosition{
		Amount:    amount,
		StartTime: time.Now(),
	}

	gStakedPositions = append(gStakedPositions, position)
	gTotalStaked = u256.Zero().Add(gTotalStaked, amount)

	return nil
}

// GetTotalStaked returns the total staked amount.
func GetTotalStaked() *u256.Uint {
	return gTotalStaked.Clone()
}

// GetLastStakedPosition returns the last staked position.
func GetLastStakedPosition() *StakedPosition {
	if len(gStakedPositions) == 0 {
		return nil
	}
	return gStakedPositions[len(gStakedPositions)-1]
}

func StakeForUser(user std.Address, amount *u256.Uint) {
	position := &StakedPosition{
		Amount:    amount,
		StartTime: time.Now(), // time.Now() retreives the current block time
		User: user,
	}
	gStakedPositions = append(gStakedPositions, position)
	gTotalStaked = u256.Zero().Add(gTotalStaked, amount)
	gStakers[user] = true
}

func GetUserStakes(user std.Address) []*StakedPosition {
	var userStakes []*StakedPosition
	for _, stake := range gStakedPositions {
		if stake.User == user {
			userStakes = append(userStakes, stake)
		}
	}
	return userStakes
}

func GetTotalStakedAmount() *u256.Uint {
	return gTotalStaked.Clone()
}

func GetTotalStakers() int {
	return len(gStakers)
}

func ClaimRewards(user std.Address) (*u256.Uint, error) {
	userStakes := GetUserStakes(user)
	if len(userStakes) == 0 {
		return nil, errors.New("no stakes found for user")
	}

	totalStaked := GetTotalStakedAmount()
	if totalStaked.IsZero() {
		return nil, errors.New("total staked amount is zero")
	}

	userTotalStake := u256.Zero()
	for _, stake := range userStakes {
		userTotalStake = u256.Zero().Add(userTotalStake, stake.Amount)
	}

	// calculate user's share of the total rewards.
	userShare := u256.Zero().Div(u256.Zero().Mul(userTotalStake, gTotalRewards), totalStaked)

	// subtract previously claimed rewards
	previouslyClaimed, exists := gClaimedRewards[user]
	if !exists {
		previouslyClaimed = u256.Zero()
	}
	reward := u256.Zero().Sub(userShare, previouslyClaimed)

	// update claimed rewards
	gClaimedRewards[user] = userShare

	// TODO: Transfer the reward to the user

	return reward, nil
}

// GetTotalRewards returns the total rewards distributed so far.
func GetTotalRewards() *u256.Uint {
	return gTotalRewards.Clone()
}

func GetClaimedRewards(user std.Address) *u256.Uint {
	claimed, exists := gClaimedRewards[user]
	if !exists {
		return u256.Zero()
	}
	return claimed.Clone()
}
