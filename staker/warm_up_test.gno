package staker

import (
    "testing"
    "time"
    u256 "gno.land/p/demo/uint256"
)

func TestCalculateReward(t *testing.T) {
    baseReward := u256.NewUint(1000) // 1000 tokens as base reward

    tests := []struct {
        name           string
        stakeDuration  time.Duration
        expectedReward *u256.Uint
    }{
        {
            name:           "Less than 5 days",
            stakeDuration:  4 * 24 * time.Hour,
            expectedReward: u256.NewUint(300), // 1000 * 0.3
        },
        {
            name:           "Between 5 and 10 days",
            stakeDuration:  7 * 24 * time.Hour,
            expectedReward: u256.NewUint(500), // 1000 * 0.5
        },
        {
            name:           "Between 10 and 30 days",
            stakeDuration:  20 * 24 * time.Hour,
            expectedReward: u256.NewUint(700), // 1000 * 0.7
        },
        {
            name:           "More than 30 days",
            stakeDuration:  40 * 24 * time.Hour,
            expectedReward: u256.NewUint(1000), // 1000 * 1.0
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            position := &StakedPosition{
                Amount:    u256.NewUint(1000), // Amount doesn't affect the calculation in this case
                StartTime: time.Now().Add(-tt.stakeDuration),
            }

            reward := calculateReward(position, baseReward)

            if reward.Cmp(tt.expectedReward) != 0 {
                t.Errorf("calculateReward() = %v, want %v", reward, tt.expectedReward)
            }
        })
    }
}

// Additional test to check edge cases
func TestCalculateRewardEdgeCases(t *testing.T) {
    baseReward := u256.NewUint(1000)

    tests := []struct {
        name           string
        stakeDuration  time.Duration
        expectedReward *u256.Uint
    }{
        {
            name:           "Exactly 5 days",
            stakeDuration:  5 * 24 * time.Hour,
            expectedReward: u256.NewUint(500), // Should use the higher multiplier
        },
        {
            name:           "Exactly 10 days",
            stakeDuration:  10 * 24 * time.Hour,
            expectedReward: u256.NewUint(700), // Should use the higher multiplier
        },
        {
            name:           "Exactly 30 days",
            stakeDuration:  30 * 24 * time.Hour,
            expectedReward: u256.NewUint(1000), // Should use the highest multiplier
        },
        {
            name:           "Zero duration",
            stakeDuration:  0,
            expectedReward: u256.NewUint(300), // Should use the lowest multiplier
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            position := &StakedPosition{
                Amount:    u256.NewUint(1000),
                StartTime: time.Now().Add(-tt.stakeDuration),
            }

            reward := calculateReward(position, baseReward)

            if reward.Cmp(tt.expectedReward) != 0 {
                t.Errorf("calculateReward() = %v, want %v", reward, tt.expectedReward)
            }
        })
    }
}