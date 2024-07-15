package staking

import (
	"std"
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

func TestStakingQueries(t *testing.T) {
    Init()

    user1 := std.Address("user1")
    user2 := std.Address("user2")

    StakeForUser(user1, u256.NewUint(100))
    StakeForUser(user1, u256.NewUint(200))
    StakeForUser(user2, u256.NewUint(300))

    t.Run("GetUserStakes", func(t *testing.T) {
        stakes := GetUserStakes(user1)
        if len(stakes) != 2 {
            t.Errorf("Expected 2 stakes for user1, got %d", len(stakes))
        }
        totalStaked := u256.Zero()
        for _, stake := range stakes {
            totalStaked = totalStaked.Add(totalStaked, stake.Amount)
        }
        if totalStaked.Cmp(u256.NewUint(300)) != 0 {
            t.Errorf("Expected total stake of 300 for user1, got %s", totalStaked.ToString())
        }

        stakes = GetUserStakes(user2)
        if len(stakes) != 1 {
            t.Errorf("Expected 1 stake for user2, got %d", len(stakes))
        }
        if stakes[0].Amount.Cmp(u256.NewUint(300)) != 0 {
            t.Errorf("Expected stake of 300 for user2, got %s", stakes[0].Amount.ToString())
        }
    })

    t.Run("GetTotalStakedAmount", func(t *testing.T) {
        totalStaked := GetTotalStakedAmount()
        if totalStaked.Cmp(u256.NewUint(600)) != 0 {
            t.Errorf("Expected total staked amount of 600, got %s", totalStaked.ToString())
        }
    })

    t.Run("GetTotalStakers", func(t *testing.T) {
        totalStakers := GetTotalStakers()
        if totalStakers != 2 {
            t.Errorf("Expected 2 total stakers, got %d", totalStakers)
        }
    })
}

func TestClaimRewards(t *testing.T) {
	Init()

	user1 := std.Address("user1")
	user2 := std.Address("user2")

	StakeForUser(user1, u256.NewUint(1000))
	StakeForUser(user2, u256.NewUint(500))

	SimulateRewardAccrual(u256.NewUint(100)) // 100 tokens distributed as rewards

	t.Run("claim rewards", func(t *testing.T) {
		// user 1 claims rewards
		reward1, err := ClaimRewards(user1)
		if err != nil {
			t.Fatalf("failed to claim rewards for user1: %v", err)
		}
		expectedReward1 := u256.NewUint(66) // (1000 / 1500) * 100
		if reward1.Cmp(expectedReward1) != 0 {
			t.Errorf("Expected reward of %v for user1, got %v", expectedReward1, reward1)
		}

		reward2, err := ClaimRewards(user2)
		if err != nil {
			t.Fatalf("failed to claim rewards for user2: %v", err)
		}
		expectedReward2 := u256.NewUint(33) // (500 / 1500) * 100
		if reward2.Cmp(expectedReward2) != 0 {
			t.Errorf("Expected reward of %v for user2, got %v", expectedReward2, reward2)
		}

		reward1Again, err := ClaimRewards(user1)
		if err != nil {
			t.Fatalf("failed to claim rewards for user1 again: %v", err)
		}
		if !reward1Again.IsZero() {
			t.Errorf("Expected zero reward for user1, got %v", reward1Again)
		}
	})

	t.Run("claim with no stake", func(t *testing.T) {
		noStakedUser := std.Address("noStake")
		_, err := ClaimRewards(noStakedUser)
		if err == nil {
			t.Fatalf("Expected an error, but got none")
		}
	})
}

func SimulateRewardAccrual(amount *u256.Uint) {
    // This function simulates the distribution of rewards
    gTotalRewards = gTotalRewards.Add(gTotalRewards, amount)
}

func TestStakingPeriod(t *testing.T) {
	Init()

	user1 := std.Address("user1")
	amount := u256.NewUint(1000)

	var (
		_30Days  = 30 * 24 * time.Hour
		_90Days  = 90 * 24 * time.Hour
	)

	t.Run("stake with different periods", func(t *testing.T) {
		// stake for 30 days
		err := StakeWithPeriod(user1, amount, _30Days)
		if err != nil {
			t.Fatalf("failed to stake for 30 days: %v", err)
		}

		// stake for 90 days
		err = StakeWithPeriod(user1, amount, _90Days)
		if err != nil {
			t.Fatalf("failed to stake for 90 days: %v", err)
		}

		stakes := GetUserStakes(user1)
		if len(stakes) != 2 {
			t.Fatalf("Expected 2 stakes, got %d", len(stakes))
		}

		if stakes[0].LockPeriod != _30Days {
			t.Errorf("expected lock period of 30 days, got %v", stakes[0].LockPeriod)
		}

		if stakes[1].LockPeriod != _90Days {
			t.Errorf("expected lock period of 90 days, got %v", stakes[1].LockPeriod)
		}
	})
}
