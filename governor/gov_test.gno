package governor

import (
	"errors"
	"std"
	"strings"
	"testing"
	"time"

	"gno.land/p/demo/testutils"
	"gno.land/p/demo/ufmt"
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
		Quorum:                        500,
		ProposalCreationThreshold:     100,
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}

	t.Run("Successful proposal", func(t *testing.T) {
		Init(mockStaker, config)
		toAddr := testutils.TestAddress("test_address").String()
		callsJSON := ufmt.Sprintf(
			`[{"to":"%s","selector":1,"calldata":"test_data"}]`,
			toAddr,
		)

		id, err := Propose(callsJSON)
		if err != nil {
			t.Fatalf("Propose failed: %v", err)
		}

		proposalInfo, exists := gGovernor.proposals.Get(id)
		if !exists {
			t.Fatalf("Proposal not found after creation")
		}

		proposal := proposalInfo.(ProposalInfo)
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
		callsJSON := ufmt.Sprintf(
			`[{"to":"%s","selector":1,"calldata":"test_data"}]`,
			testutils.TestAddress("test_address").String(),
		)

		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "THRESHOLD" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Propose(callsJSON)
	})

	t.Run("Proposal with active proposal", func(t *testing.T) {
		Init(mockStaker, config)
		mockStaker.averageDelegated = uint256.NewUint(1000) // Above threshold
		callsJSON := ufmt.Sprintf(
			`[{"to":"%s","selector":1,"calldata":"test_data"}]`,
			testutils.TestAddress("test_address").String(),
		)

		// Create a proposal
		Propose(callsJSON)

		// Try to create another proposal immediately
		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "PROPOSER_HAS_ACTIVE_PROPOSAL" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Propose(callsJSON)
	})
}

func TestDescribe(t *testing.T) {
	mockStaker := &MockStaker{
		averageDelegated: uint256.NewUint(1000),
	}

	config := Config{
		VotingStartDelay:              100,
		VotingPeriod:                  1000,
		VotingWeightSmoothingDuration: 100,
		Quorum:                        500,
		ProposalCreationThreshold:     100,
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}

	Init(mockStaker, config)

	callsJSON := `[{"to":"g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5","selector":1,"calldata":"test_data"}]`
	id, _ := Propose(callsJSON)

	t.Run("Successful description", func(t *testing.T) {
		description := "This is a test proposal"
		Describe(id, description)

		proposalValue, exists := gGovernor.proposals.Get(id)
		if !exists {
			t.Fatalf("Proposal not found after description")
		}

		proposal := proposalValue.(ProposalInfo)
		if proposal.Description != description {
			t.Errorf("Description not set correctly. Expected %s, got %s", description, proposal.Description)
		}
	})

	t.Run("Non-existent proposal", func(t *testing.T) {
		nonExistentID := "0000000000000000000000000000000000000000000000000000000000000000"
		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "DOES_NOT_EXIST" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Describe(nonExistentID, "Test description")
	})

	t.Run("Already executed proposal", func(t *testing.T) {
		proposalValue, _ := gGovernor.proposals.Get(id)
		proposal := proposalValue.(ProposalInfo)
		proposal.ExecutionState.Executed = uint64(time.Now().Unix())
		gGovernor.proposals.Set(id, proposal)

		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "ALREADY_EXECUTED" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Describe(id, "Test description")
	})

	t.Run("Canceled proposal", func(t *testing.T) {
		proposalValue, _ := gGovernor.proposals.Get(id)
		proposal := proposalValue.(ProposalInfo)
		proposal.ExecutionState.Executed = 0
		proposal.ExecutionState.Canceled = uint64(time.Now().Unix())
		gGovernor.proposals.Set(id, proposal)

		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "PROPOSAL_CANCELED" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Describe(id, "Test description")
	})
}

func TestProposeAndDescribe(t *testing.T) {
	mockStaker := &MockStaker{
		averageDelegated: uint256.NewUint(1000),
	}

	config := Config{
		VotingStartDelay:              100,
		VotingPeriod:                  1000,
		VotingWeightSmoothingDuration: 100,
		Quorum:                        500,
		ProposalCreationThreshold:     100,
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}

	Init(mockStaker, config)

	callsJSON := ufmt.Sprintf(
		`[{"to":"%s","selector":1,"calldata":"test_data"}]`,
		testutils.TestAddress("test_address").String(),
	)

	description := "Test proposal description"

	t.Run("Successful propose and describe", func(t *testing.T) {
		id, err := ProposeAndDescribe(callsJSON, description)
		if err != nil {
			t.Fatalf("ProposeAndDescribe failed: %v", err)
		}

		proposalValue, _ := gGovernor.proposals.Get(id)
		proposal := proposalValue.(ProposalInfo)

		if proposal.Proposer != std.GetOrigCaller() {
			t.Errorf("Incorrect proposer. Expected %v, got %v", std.GetOrigCaller(), proposal.Proposer)
		}

		if proposal.ExecutionState.Created == 0 {
			t.Errorf("Proposal creation time not set")
		}
	})

	t.Run("Proposal with insufficient stake", func(t *testing.T) {
		mockStaker.averageDelegated = uint256.NewUint(50) // Below threshold

		defer func() {
			if r := recover(); r != nil {
				var errMsg string
				switch v := r.(type) {
				case string:
					errMsg = v
				case error:
					errMsg = v.Error()
				default:
					errMsg = ufmt.Sprintf("unexpected panic: %v", r)
				}
				expectedErrMsg := "PROPOSER_HAS_ACTIVE_PROPOSAL"
				if errMsg != expectedErrMsg {
					t.Fatalf("unexpected panic message: %v", errMsg)
				}
			} else {
				t.Fatalf("should panic")
			}
		}()

		ProposeAndDescribe(callsJSON, description)
	})
}

func TestVote(t *testing.T) {
	mockStaker := &MockStaker{
		averageDelegated: uint256.NewUint(1000),
	}

	config := Config{
		VotingStartDelay:              100,
		VotingPeriod:                  1000,
		VotingWeightSmoothingDuration: 100,
		Quorum:                        500,
		ProposalCreationThreshold:     100,
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}

	Init(mockStaker, config)

	callsJSON := ufmt.Sprintf(
		`[{"to":"%s","selector":1,"calldata":"test_data"}]`,
		testutils.TestAddress("test_address").String(),
	)

	id, _ := Propose(callsJSON)

	t.Run("Successful vote", func(t *testing.T) {
		// Set the current time to be within the voting period
		currentTime := uint64(timeNow().Unix()) + config.VotingStartDelay + 50
		origTimeNow := timeNow
		timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
		defer func() { timeNow = origTimeNow }()

		Vote(id, true)

		proposalValue, _ := gGovernor.proposals.Get(id)
		proposal := proposalValue.(ProposalInfo)
		if proposal.Yea.Cmp(uint256.NewUint(1000)) != 0 {
			t.Errorf("Expected Yea votes to be 1000, got %s", proposal.Yea.ToString())
		}

		voteKey := id + ":" + std.GetOrigCaller().String()
		voteValue, exists := gGovernor.vote.Get(voteKey)
		if !exists {
			t.Errorf("Vote not recorded")
		}
		if voteValue.(uint8) != 3 {
			t.Errorf("Expected vote to be 3 (Yea), got %d", voteValue)
		}
	})

	t.Run("Vote before voting period", func(t *testing.T) {
		currentTime := uint64(timeNow().Unix()) + config.VotingStartDelay - 1
		origTimeNow := timeNow
		timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
		defer func() { timeNow = origTimeNow }()

		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "VOTING_NOT_STARTED" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Vote(id, true)
	})

	t.Run("Vote after voting period", func(t *testing.T) {
		currentTime := uint64(timeNow().Unix()) + config.VotingStartDelay + config.VotingPeriod + 1
		origTimeNow := timeNow
		timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
		defer func() { timeNow = origTimeNow }()

		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "VOTING_ENDED" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Vote(id, true)
	})

	t.Run("Vote twice", func(t *testing.T) {
		t.Skip()
		currentTime := uint64(timeNow().Unix()) + config.VotingStartDelay + 50
		origTimeNow := timeNow
		timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
		defer func() { timeNow = origTimeNow }()

		Vote(id, true)

		panicked := false
		panicValue := ""
		func() {
			defer func() {
				if r := recover(); r != nil {
					panicked = true
					panicValue = ufmt.Sprintf("%v", r)
				}
			}()
			Vote(id, false)
		}()

		if !panicked {
			t.Errorf("The code did not panic")
		} else if panicValue != "ALREADY_VOTED" {
			t.Errorf("Unexpected panic: %v", panicValue)
		}
	})
}

func TestCancel(t *testing.T) {
	mockStaker := &MockStaker{
		averageDelegated: uint256.NewUint(1000),
	}

	config := Config{
		VotingStartDelay:              100,
		VotingPeriod:                  1000,
		VotingWeightSmoothingDuration: 100,
		Quorum:                        500,
		ProposalCreationThreshold:     100,
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}

	Init(mockStaker, config)

	callsJSON := ufmt.Sprintf(
		`[{"to":"%s","selector":1,"calldata":"test_data"}]`,
		testutils.TestAddress("test_address").String(),
	)

	id, err := Propose(callsJSON)
	if err != nil {
		t.Fatalf("Propose failed: %v", err)
	}

	t.Run("Successful cancel by proposer", func(t *testing.T) {
		Cancel(id)

		// proposal := gGovernor.proposals[id]
		proposalValue, _ := gGovernor.proposals.Get(id)
		proposal := proposalValue.(ProposalInfo)
		if proposal.ExecutionState.Canceled == 0 {
			t.Errorf("Proposal was not canceled")
		}
	})

	t.Run("Cancel already canceled proposal", func(t *testing.T) {
		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "ALREADY_CANCELED" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Cancel(id)
	})

	t.Run("Cancel after voting started", func(t *testing.T) {
		id, err := Propose(callsJSON)
		if err != nil {
			t.Fatalf("Propose failed: %v", err)
		}

		// Set the current time to be after voting start
		currentTime := uint64(timeNow().Unix()) + config.VotingStartDelay + 1
		origTimeNow := timeNow
		timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
		defer func() { timeNow = origTimeNow }()

		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "VOTING_STARTED" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Cancel(id)
	})
}

func TestGetConfigVersion(t *testing.T) {
	mockStaker := &MockStaker{
		averageDelegated: uint256.NewUint(1000),
	}

	initialConfig := Config{
		VotingStartDelay:              100,
		VotingPeriod:                  1000,
		VotingWeightSmoothingDuration: 100,
		Quorum:                        500,
		ProposalCreationThreshold:     100,
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}

	Init(mockStaker, initialConfig)

	t.Run("Get initial config (version 0)", func(t *testing.T) {
		config := GetConfigVersion(0)
		if config != initialConfig {
			t.Errorf("Expected initial config, got different config")
		}
	})

	t.Run("Get non-existent config version", func(t *testing.T) {
		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "DOES_NOT_EXIST" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		GetConfigVersion(1) // This should panic
	})

	t.Run("Get existing config version", func(t *testing.T) {
		newConfig := Config{
			VotingStartDelay:              200,
			VotingPeriod:                  2000,
			VotingWeightSmoothingDuration: 200,
			Quorum:                        1000,
			ProposalCreationThreshold:     200,
			ExecutionDelay:                200,
			ExecutionWindow:               2000,
		}

		// gGovernor.configVersions[1] = newConfig
		// gGovernor.latestConfigVersion = 1
		gGovernor.configVersions.Set("1", newConfig)
		gGovernor.latestConfigVersion = 1

		config := GetConfigVersion(1)
		if config != newConfig {
			t.Errorf("Expected new config, got different config")
		}
	})
}

func TestExecuteCall(t *testing.T) {
	tests := []struct {
		name     string
		selector uint64
		calldata string
		register func(uint64)
		expected string
		wantErr  bool
	}{
		{
			name:     "Simple concatenation",
			selector: 1,
			calldata: "World",
			register: func(selector uint64) {
				RegisterFunction(selector, func(args ...string) (string, error) {
					if len(args) < 1 {
						return "", errors.New("no data provided")
					}
					return "Hello, " + strings.Join(args, " "), nil
				})
			},
			expected: "Hello, World",
			wantErr:  false,
		},
		{
			name:     "Uppercase conversion",
			selector: 2,
			calldata: "lowercase",
			register: func(selector uint64) {
				RegisterFunction(selector, func(data ...string) (string, error) {
					if len(data) < 1 {
						return "", errors.New("no data provided")
					}
					return strings.ToUpper(data[0]), nil
				})
			},
			expected: "LOWERCASE",
			wantErr:  false,
		},
		{
			name:     "Error case",
			selector: 3,
			calldata: "error",
			register: func(selector uint64) {
				RegisterFunction(selector, func(data ...string) (string, error) {
					return "", errors.New("test error")
				})
			},
			expected: "",
			wantErr:  true,
		},
		{
			name:     "multiple arguments",
			selector: 4,
			calldata: "arg1,arg2,arg3",
			register: func(selector uint64) {
				RegisterFunction(selector, func(data ...string) (string, error) {
					if len(data) < 3 {
						return "", errors.New("not enough arguments")
					}
					return strings.Join(data, " "), nil
				})
			},
			expected: "arg1 arg2 arg3",
			wantErr:  false,
		},
		{
			name:     "Unregistered function",
			selector: 4,
			calldata: "test",
			register: func(selector uint64) {
				// Don't register any function
			},
			expected: "",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.register(tt.selector)

			call := Call{
				To:       testutils.TestAddress("test_address"),
				Selector: tt.selector,
				Calldata: tt.calldata,
			}

			if tt.wantErr {
				defer func() {
					if r := recover(); r == nil {
						t.Errorf("executeCall() did not panic as expected")
					}
				}()
			}

			result := executeCall(call)

			if !tt.wantErr {
				if result != tt.expected {
					t.Errorf("executeCall() = %s, want %s", result, tt.expected)
				}
			}
		})
	}
}

func TestExecute(t *testing.T) {
	RegisterFunction(1, func(args ...string) (string, error) {
		if len(args) < 1 {
			return "", errors.New("no data provided")
		}
		return "Executed: " + strings.Join(args, " "), nil
	})

	setupGovernor := func() (string, string, Config) {
		mockStaker := &MockStaker{
			averageDelegated: uint256.NewUint(1000),
		}

		config := Config{
			VotingStartDelay:              100,
			VotingPeriod:                  1000,
			VotingWeightSmoothingDuration: 100,
			Quorum:                        500,
			ProposalCreationThreshold:     100,
			ExecutionDelay:                100,
			ExecutionWindow:               1000,
		}

		Init(mockStaker, config)

		callsJSON := ufmt.Sprintf(
			`[{"to":"%s","selector":1,"calldata":"test_data"}]`,
			testutils.TestAddress("test_address").String(),
		)

		id, _ := Propose(callsJSON)

		// Set the time to be after voting has started
		proposalValue, _ := gGovernor.proposals.Get(id)
		proposal := proposalValue.(ProposalInfo)

		votingStartTime := proposal.ExecutionState.Created + config.VotingStartDelay + 1
		origTimeNow := timeNow
		timeNow = func() time.Time { return time.Unix(int64(votingStartTime), 0) }

		// Set up a successful vote
		Vote(id, true)

		// Reset the time function
		timeNow = origTimeNow

		return id, callsJSON, config
	}

	t.Run("Successful execution", func(t *testing.T) {
		id, callsJSON, config := setupGovernor()

		// Set the current time to be within the execution window
		proposalValue, _ := gGovernor.proposals.Get(id)
		proposal := proposalValue.(ProposalInfo)

		currentTime := proposal.ExecutionState.Created + config.VotingStartDelay + config.VotingPeriod + config.ExecutionDelay + 1
		origTimeNow := timeNow
		timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
		defer func() { timeNow = origTimeNow }()

		results := Execute(id, callsJSON)

		if len(results) == 0 {
			t.Errorf("No results returned")
		}

		rr := strings.Split(results, ",")
		if len(rr) != 1 {
			t.Errorf("Expected 1 result, got %d", len(rr))
		}

		executedProposalValue, _ := gGovernor.proposals.Get(id)
		executedProposal := executedProposalValue.(ProposalInfo)
		if executedProposal.ExecutionState.Executed == 0 {
			t.Errorf("Proposal was not marked as executed")
		}

		// Check the result of the executed function
		expectedResult := "Executed: test_data"
		if results != expectedResult {
			t.Errorf("Expected result %s, got %s", expectedResult, results[0])
		}
	})

	t.Run("Execution before voting ends", func(t *testing.T) {
		id, calls, config := setupGovernor()

		// Set the current time to be before voting ends
		proposalValue, _ := gGovernor.proposals.Get(id)
		proposal := proposalValue.(ProposalInfo)

		currentTime := proposal.ExecutionState.Created + config.VotingStartDelay + config.VotingPeriod - 1
		origTimeNow := timeNow
		timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
		defer func() { timeNow = origTimeNow }()

		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "VOTING_NOT_ENDED" {
				t.Errorf("Unexpected panic: %v", r)
			}
		}()

		Execute(id, calls)
	})
}

func TestReconfigure(t *testing.T) {
	mockStaker := &MockStaker{}
	initialConfig := Config{
		VotingStartDelay:              100,
		VotingPeriod:                  1000,
		VotingWeightSmoothingDuration: 100,
		Quorum:                        500,
		ProposalCreationThreshold:     100,
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}
	Init(mockStaker, initialConfig)

	// Helper function to set the caller to the governor itself
	setGovernorAsCaller := func() {
		origCaller := std.GetOrigCaller
		std.TestSetOrigCaller(std.GetOrigPkgAddr())
	}

	t.Run("Successful reconfiguration", func(t *testing.T) {
		setGovernorAsCaller()

		newConfigJSON := `{
            "votingStartDelay": 200,
            "votingPeriod": 2000,
            "votingWeightSmoothingDuration": 200,
            "quorum": 1000,
            "proposalCreationThreshold": 200,
            "executionDelay": 200,
            "executionWindow": 2000
        }`

		newVersion := Reconfigure(newConfigJSON)

		if newVersion != 1 {
			t.Errorf("Expected new version to be 1, got %d", newVersion)
		}

		if gGovernor.latestConfigVersion != 1 {
			t.Errorf("Expected latest config version to be 1, got %d", gGovernor.latestConfigVersion)
		}

		newConfig := gGovernor.config
		if newConfig.VotingStartDelay != 200 ||
			newConfig.VotingPeriod != 2000 ||
			newConfig.VotingWeightSmoothingDuration != 200 ||
			newConfig.Quorum != 1000 ||
			newConfig.ProposalCreationThreshold != 200 ||
			newConfig.ExecutionDelay != 200 ||
			newConfig.ExecutionWindow != 2000 {
			t.Errorf("New configuration does not match expected values")
		}
	})

	t.Run("Not called by governor", func(t *testing.T) {
		// Set the caller to be a different address
		std.TestSetOrigCaller(testutils.TestAddress("not_governor"))

		newConfigJSON := `{
	        "votingStartDelay": 200,
	        "votingPeriod": 2000,
	        "votingWeightSmoothingDuration": 200,
	        "quorum": 1000,
	        "proposalCreationThreshold": 200,
	        "executionDelay": 200,
	        "executionWindow": 2000
	    }`

		defer func() {
			if r := recover(); r == nil {
				t.Errorf("The code did not panic")
			} else if r != "NOT_SELF_CALL" {
				t.Errorf("Unexpected panic message: %v", r)
			}
		}()

		Reconfigure(newConfigJSON)
	})
}
