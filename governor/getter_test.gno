package governor

// import (
// 	"bytes"
// 	"std"
// 	"testing"
// 	"time"

// 	"gno.land/p/demo/uint256"
// )

// func TestGetters(t *testing.T) {
// 	// Setup
// 	mockStaker := &MockStaker{
// 		averageDelegated: uint256.NewUint(1000),
// 	}

// 	config := Config{
// 		VotingStartDelay:              100,
// 		VotingPeriod:                  1000,
// 		VotingWeightSmoothingDuration: 100,
// 		Quorum:                        uint256.NewUint(500),
// 		ProposalCreationThreshold:     uint256.NewUint(100),
// 		ExecutionDelay:                100,
// 		ExecutionWindow:               1000,
// 	}

// 	Init(mockStaker, config)

// 	// Create a test proposal
// 	calls := []Call{
// 		{
// 			To:       std.Address("test_address"),
// 			Selector: 1,
// 			Calldata: []byte("test_data"),
// 		},
// 	}
// 	id, _ := Propose(calls)

// 	// Test GetStaker
// 	t.Run("GetStaker", func(t *testing.T) {
// 		staker := GetStaker()
// 		if staker != mockStaker {
// 			t.Errorf("GetStaker() = %v, want %v", staker, mockStaker)
// 		}
// 	})

// 	// Test GetConfig
// 	t.Run("GetConfig", func(t *testing.T) {
// 		gotConfig := GetConfig()
// 		if gotConfig != config {
// 			t.Errorf("GetConfig() = %v, want %v", gotConfig, config)
// 		}
// 	})

// 	// Test GetConfigWithVersion
// 	t.Run("GetConfigWithVersion", func(t *testing.T) {
// 		gotConfig, gotVersion := GetConfigWithVersion()
// 		if gotConfig != config {
// 			t.Errorf("GetConfigWithVersion() config = %v, want %v", gotConfig, config)
// 		}
// 		if gotVersion != 0 {
// 			t.Errorf("GetConfigWithVersion() version = %v, want 0", gotVersion)
// 		}
// 	})

// 	// Test GetProposal
// 	t.Run("GetProposal", func(t *testing.T) {
// 		proposal := GetProposal(id)
// 		if !bytes.Equal(proposal.CallsHash[:], hashCalls(calls)[:]) {
// 			t.Errorf("GetProposal() CallsHash mismatch")
// 		}
// 		if proposal.Proposer != std.GetOrigCaller() {
// 			t.Errorf("GetProposal() Proposer = %v, want %v", proposal.Proposer, std.GetOrigCaller())
// 		}
// 	})

// 	// Test GetProposalWithConfig
// 	t.Run("GetProposalWithConfig", func(t *testing.T) {
// 		proposal, gotConfig := GetProposalWithConfig(id)
// 		if !bytes.Equal(proposal.CallsHash[:], hashCalls(calls)[:]) {
// 			t.Errorf("GetProposalWithConfig() CallsHash mismatch")
// 		}
// 		if gotConfig != config {
// 			t.Errorf("GetProposalWithConfig() config = %v, want %v", gotConfig, config)
// 		}
// 	})

// 	// Test GetVote
// 	t.Run("GetVote", func(t *testing.T) {
// 		voter := std.GetOrigCaller()

// 		// Before voting
// 		vote := GetVote(id, voter)
// 		if vote != 0 {
// 			t.Errorf("GetVote() before voting = %v, want 0", vote)
// 		}

// 		// Set the time to be after voting has started
// 		proposal := gGovernor.proposals[id]
// 		votingStartTime := proposal.ExecutionState.Created + config.VotingStartDelay + 1
// 		origTimeNow := timeNow
// 		timeNow = func() time.Time { return time.Unix(int64(votingStartTime), 0) }
// 		defer func() { timeNow = origTimeNow }()

// 		// After voting
// 		Vote(id, true)
// 		vote = GetVote(id, voter)
// 		if vote != 3 {
// 			t.Errorf("GetVote() after voting yes = %v, want 3", vote)
// 		}
// 	})

// 	// Test error cases
// 	t.Run("GetProposal non-existent", func(t *testing.T) {
// 		defer func() {
// 			if r := recover(); r == nil {
// 				t.Errorf("GetProposal() with non-existent ID did not panic")
// 			}
// 		}()
// 		GetProposal([32]byte{})
// 	})

// 	t.Run("GetProposalWithConfig non-existent", func(t *testing.T) {
// 		defer func() {
// 			if r := recover(); r == nil {
// 				t.Errorf("GetProposalWithConfig() with non-existent ID did not panic")
// 			}
// 		}()
// 		GetProposalWithConfig([32]byte{})
// 	})
// }
