package staking

import (
	"testing"
	"time"

	u256 "gno.land/p/demo/uint256"
)

// Set all bit to 1
var MaxUint256 = u256.Zero().Sub(u256.Zero().Sub(u256.Zero(), u256.One()), u256.One())

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

func TestStake(t *testing.T) {
	Init()

	tests := []struct {
		name          string
		amount        *u256.Uint
		expectedError bool
	}{
		{
			name:          "Stake valid amount",
			amount:        u256.NewUint(100),
			expectedError: false,
		},
		{
			name:          "Stake zero amount",
			amount:        u256.NewUint(0),
			expectedError: true,
		},
		{
			name:          "Stake maximum amount",
			amount:        MaxUint256,
			expectedError: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			initialTotalStaked := GetTotalStaked()

			err := Stake(tt.amount)

			if tt.expectedError && err == nil {
				t.Errorf("Expected an error, but got none")
			}
			if !tt.expectedError && err != nil {
				t.Errorf("Unexpected error: %v", err)
			}

			if !tt.expectedError {
				newTotalStaked := GetTotalStaked()
				expectedTotalStaked := u256.Zero().Add(initialTotalStaked, tt.amount)
				if newTotalStaked.Cmp(expectedTotalStaked) != 0 {
					t.Errorf("Total staked amount incorrect. Got: %v, Want: %v", newTotalStaked, expectedTotalStaked)
				}

				position := GetLastStakedPosition()
				if position == nil {
					t.Fatal("Expected a staked position, but got nil")
				}
				if position.Amount.Cmp(tt.amount) != 0 {
					t.Errorf("Staked amount incorrect. Got: %v, Want: %v", position.Amount, tt.amount)
				}
				if time.Since(position.StartTime) > time.Second {
					t.Errorf("StartTime not set correctly")
				}
			}
		})
	}
}

func TestStakeMultiple(t *testing.T) {
    Init()

    amounts := []*u256.Uint{
        u256.NewUint(100),
        u256.NewUint(200),
        u256.NewUint(300),
    }

    for i, amount := range amounts {
        err := Stake(amount)
        if err != nil {
            t.Fatalf("Failed to stake amount %v: %v", amount, err)
        }

        position := GetLastStakedPosition()
        if position == nil {
            t.Fatal("Expected a staked position, but got nil")
        }
        if position.Amount.Cmp(amount) != 0 {
            t.Errorf("Staked amount incorrect for position %d. Got: %v, Want: %v", i, position.Amount, amount)
        }
    }

    totalStaked := GetTotalStaked()
    expectedTotal := u256.NewUint(600)
    if totalStaked.Cmp(expectedTotal) != 0 {
        t.Errorf("Total staked amount incorrect. Got: %v, Want: %v", totalStaked, expectedTotal)
    }
}
