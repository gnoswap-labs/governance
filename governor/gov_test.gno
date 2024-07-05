package governor

import (
	"bytes"
	"std"
	"testing"
	"time"

	"gno.land/p/demo/uint256"
)

// MockStaker is a mock implementation of IStakerDispatcher for testing
type MockStaker struct {
	averageDelegated *uint256.Uint
}

func (m *MockStaker) StakeAmount(delegate std.Address, amount *uint256.Uint) error {
	return nil
}

func (m *MockStaker) WithdrawAmount(delegate std.Address, recipient std.Address, amount *uint256.Uint) error {
	return nil
}

func (m *MockStaker) GetDelegatedCumulative(delegate std.Address, timestamp uint64) (*uint256.Uint, error) {
	return uint256.NewUint(0), nil
}

func (m *MockStaker) GetAverageDelegated(delegate std.Address, start, end uint64) (*uint256.Uint, error) {
	return m.averageDelegated, nil
}

func (m *MockStaker) GetAverageDelegatedOverLast(delegate std.Address, period uint64) (*uint256.Uint, error) {
	return m.averageDelegated, nil
}

func (m *MockStaker) GetCurrentDelegated(delegate std.Address) (*uint256.Uint, error) {
	return uint256.NewUint(0), nil
}

func (m *MockStaker) GetDelegatedAt(delegate std.Address, timestamp uint64) (*uint256.Uint, error) {
	return uint256.NewUint(0), nil
}

////////////////////////////////////////////////////////

func TestPropose(t *testing.T) {
	mockStaker := &MockStaker{
		averageDelegated: uint256.NewUint(1000),
	}

	config := Config{
		VotingStartDelay:              100,
		VotingPeriod:                  1000,
		VotingWeightSmoothingDuration: 100,
		Quorum:                        uint256.NewUint(500),
		ProposalCreationThreshold:     uint256.NewUint(100),
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}

	t.Run("Successful proposal", func(t *testing.T) {
		Init(mockStaker, config)
		calls := []Call{
			{
				To:       std.Address("test_address"),
				Selector: 1,
				Calldata: []byte("test_data"),
			},
		}

		id, err := Propose(calls)
		if err != nil {
			t.Fatalf("Propose failed: %v", err)
		}

		proposal, exists := gGovernor.proposals[id]
		if !exists {
			t.Fatalf("Proposal not found after creation")
		}

		if proposal.Proposer != std.GetOrigCaller() {
			t.Errorf("Incorrect proposer. Expected %v, got %v", std.GetOrigCaller(), proposal.Proposer)
		}

		if proposal.ExecutionState.Created == 0 {
			t.Errorf("Proposal creation time not set")
		}

		if proposal.Yea.Cmp(uint256.NewUint(0)) != 0 || proposal.Nay.Cmp(uint256.NewUint(0)) != 0 {
			t.Errorf("Initial vote counts should be zero")
		}
	})

	t.Run("Proposal with insufficient stake", func(t *testing.T) {
		Init(mockStaker, config)
		mockStaker.averageDelegated = uint256.NewUint(50) // Below threshold

		calls := []Call{
			{
				To:       std.Address("test_address"),
				Selector: 1,
				Calldata: []byte("test_data"),
			},
		}

		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "THRESHOLD" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Propose(calls)
	})

	t.Run("Proposal with active proposal", func(t *testing.T) {
		Init(mockStaker, config)
		mockStaker.averageDelegated = uint256.NewUint(1000) // Above threshold

		calls := []Call{
			{
				To:       std.Address("test_address"),
				Selector: 1,
				Calldata: []byte("test_data"),
			},
		}

		// Create a proposal
		Propose(calls)

		// Try to create another proposal immediately
		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "PROPOSER_HAS_ACTIVE_PROPOSAL" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Propose(calls)
	})
}
