package staker

import (
    "time"
    u256 "gno.land/p/demo/uint256"
)

const (
	WarmUpPeriod1 = 5 * 24 * time.Hour
	WarmUpPeriod2 = 10 * 24 * time.Hour
	WarmUpPeriod3 = 30 * 24 * time.Hour
)

var (
	Multiplier1 = u256.NewUint(30) // 0.3
	Multiplier2 = u256.NewUint(50) // 0.5
	Multiplier3 = u256.NewUint(70) // 0.7
	Multiplier4 = u256.NewUint(100) // 1.0
)

// StakedPosition represents a single staked position.
type StakedPosition struct {
	Amount *u256.Uint
	StartTime time.Time
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

func calculateReward(position *StakedPosition, baseReward *u256.Uint) *u256.Uint {
	stakeDuration := time.Since(position.StartTime)
	multiplier := calculateRewardMultiplier(stakeDuration)

	// multiply the base reward by multiplier
	// (divided by 100 as multipliers are in percentage)
	adjuestedReward := u256.Zero().Mul(baseReward, multiplier)
	return u256.Zero().Div(adjuestedReward, u256.NewUint(100))
}