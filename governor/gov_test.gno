package governor

import (
	"bytes"
	"errors"
	"std"
	"testing"
	"time"

	"gno.land/p/demo/uint256"
	"gno.land/p/demo/ufmt"
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

func TestDescribe(t *testing.T) {
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

	Init(mockStaker, config)

	calls := []Call{
		{
			To:       std.Address("test_address"),
			Selector: 1,
			Calldata: []byte("test_data"),
		},
	}

	id, _ := Propose(calls)

	t.Run("Non-existent proposal", func(t *testing.T) {
		Init(mockStaker, config)
		nonExistentID := [32]byte{}
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
				expectedErrMsg := "DOES_NOT_EXIST"
				if !bytes.Contains([]byte(errMsg), []byte(expectedErrMsg)) {
					t.Fatalf("unexpected panic message: %v", errMsg)
				}
			} else {
				t.Fatalf("should panic")
			}
		}()

		Describe(nonExistentID, "Test description")
	})

	t.Run("Already executed proposal", func(t *testing.T) {
		proposal := gGovernor.proposals[id]
		proposal.ExecutionState.Executed = uint64(time.Now().Unix())
		gGovernor.proposals[id] = proposal

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
				expectedErrMsg := "ALREADY_EXECUTED"
				if !bytes.Contains([]byte(errMsg), []byte(expectedErrMsg)) {
					t.Fatalf("unexpected panic message: %v", errMsg)
				}
			} else {
				t.Fatalf("should panic")
			}
		}()

		Describe(id, "Test description")
		// expect panic message: panic: already executed
	})

	t.Run("Canceled proposal", func(t *testing.T) {
		proposal := gGovernor.proposals[id]
		proposal.ExecutionState.Executed = 0
		proposal.ExecutionState.Canceled = uint64(time.Now().Unix())
		gGovernor.proposals[id] = proposal

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
				expectedErrMsg := "PROPOSAL_CANCELED"
				if !bytes.Contains([]byte(errMsg), []byte(expectedErrMsg)) {
					t.Fatalf("unexpected panic message: %v", errMsg)
				}
			} else {
				t.Fatalf("should panic")
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
		Quorum:                        uint256.NewUint(500),
		ProposalCreationThreshold:     uint256.NewUint(100),
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}

	Init(mockStaker, config)

	calls := []Call{
		{
			To:       std.Address("test_address"),
			Selector: 1,
			Calldata: []byte("test_data"),
		},
	}

	description := "Test proposal description"

	t.Run("Successful propose and describe", func(t *testing.T) {
		id, err := ProposeAndDescribe(calls, description)
		if err != nil {
			t.Fatalf("ProposeAndDescribe failed: %v", err)
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
				// XXX
				expectedErrMsg := "PROPOSER_HAS_ACTIVE_PROPOSAL"
				if !bytes.Contains([]byte(errMsg), []byte(expectedErrMsg)) {
					t.Fatalf("unexpected panic message: %v", errMsg)
				}
			} else {
				t.Fatalf("should panic")
			}
		}()

		ProposeAndDescribe(calls, description)
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
		Quorum:                        uint256.NewUint(500),
		ProposalCreationThreshold:     uint256.NewUint(100),
		ExecutionDelay:                100,
		ExecutionWindow:               1000,
	}

	Init(mockStaker, config)

	calls := []Call{
		{
			To:       std.Address("test_address"),
			Selector: 1,
			Calldata: []byte("test_data"),
		},
	}

	id, _ := Propose(calls)

	// t.Run("Successful vote", func(t *testing.T) {
	// 	// Set the current time to be within the voting period
	// 	currentTime := gGovernor.proposals[id].ExecutionState.Created + config.VotingStartDelay + 50
	// 	origTimeNow := timeNow
	// 	timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
	// 	defer func() { timeNow = origTimeNow }()

	// 	Vote(id, true)

	// 	proposal := gGovernor.proposals[id]
	// 	if proposal.Yea.Cmp(uint256.NewUint(1000)) != 0 {
	// 		t.Errorf("Expected Yea votes to be 1000, got %s", proposal.Yea.ToString())
	// 	}

	// 	vote := gGovernor.vote[id][std.GetOrigCaller()]
	// 	if vote != 3 {
	// 		t.Errorf("Expected vote to be 3 (Yea), got %d", vote)
	// 	}
	// })

	t.Run("Vote before voting period", func(t *testing.T) {
		currentTime := gGovernor.proposals[id].ExecutionState.Created + config.VotingStartDelay - 1
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

	// t.Run("Vote after voting period", func(t *testing.T) {
	// 	currentTime := gGovernor.proposals[id].ExecutionState.Created + config.VotingStartDelay + config.VotingPeriod + 1
	// 	origTimeNow := timeNow
	// 	timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
	// 	defer func() { timeNow = origTimeNow }()

	// 	defer func() {
	// 		if r := recover(); r == nil {
	// 			t.Errorf("The code did not panic")
	// 		} else if r != "VOTING_ENDED" {
	// 			t.Errorf("Unexpected panic: %v", r)
	// 		}
	// 	}()

	// 	Vote(id, true)
	// })

	// t.Run("Vote twice", func(t *testing.T) {
	// 	currentTime := gGovernor.proposals[id].ExecutionState.Created + config.VotingStartDelay + 50
	// 	origTimeNow := timeNow
	// 	timeNow = func() time.Time { return time.Unix(int64(currentTime), 0) }
	// 	defer func() { timeNow = origTimeNow }()

	// 	Vote(id, true)

	// 	defer func() {
	// 		if r := recover(); r == nil {
	// 			t.Errorf("The code did not panic")
	// 		} else if r != "ALREADY_VOTED" {
	// 			t.Errorf("Unexpected panic: %v", r)
	// 		}
	// 	}()

	// 	Vote(id, false)
	// })
}

func TestCancel(t *testing.T) {
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

    Init(mockStaker, config)

    calls := []Call{
        {
            To:       std.Address("test_address"),
            Selector: 1,
            Calldata: []byte("test_data"),
        },
    }

    id, _ := Propose(calls)

    t.Run("Successful cancel by proposer", func(t *testing.T) {
        Cancel(id)

        proposal := gGovernor.proposals[id]
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
        id, _ := Propose(calls)

        // Set the current time to be after voting start
        currentTime := gGovernor.proposals[id].ExecutionState.Created + config.VotingStartDelay + 1
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

func TestCancelByNonProposer(t *testing.T) {
    setupGovernor := func() ([32]byte, *MockStaker) {
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

        Init(mockStaker, config)

        calls := []Call{
            {
                To:       std.Address("test_address"),
                Selector: 1,
                Calldata: []byte("test_data"),
            },
        }

        id, _ := Propose(calls)
        return id, mockStaker
    }

    // t.Run("Cancel by non-proposer with sufficient stake", func(t *testing.T) {
	// 	t.Skip()
    //     id, _ := setupGovernor()

    //     // Change the caller
    //     origCaller := std.GetOrigCaller
    //     std.GetOrigCaller = func() std.Address { return std.Address("non_proposer") }
    //     defer func() { std.GetOrigCaller = origCaller }()

    //     defer func() {
    //         if r := recover(); r == nil {
    //             t.Errorf("The code did not panic")
    //         } else if r != "NOT_PROPOSER" {
    //             t.Errorf("Unexpected panic: %v", r)
    //         }
    //     }()

    //     Cancel(id)
    // })

    // t.Run("Cancel by non-proposer with insufficient stake", func(t *testing.T) {
    //     id, mockStaker := setupGovernor()

    //     // Change the caller and lower the proposer's stake
    //     origCaller := std.GetOrigCaller
    //     std.GetOrigCaller = func() std.Address { return std.Address("non_proposer") }
    //     defer func() { std.GetOrigCaller = origCaller }()

    //     mockStaker.averageDelegated = uint256.NewUint(50) // Below threshold

    //     Cancel(id)

    //     proposal := gGovernor.proposals[id]
    //     if proposal.ExecutionState.Canceled == 0 {
    //         t.Errorf("Proposal was not canceled")
    //     }
    // })
}

func TestGetConfigVersion(t *testing.T) {
	mockStaker := &MockStaker{
		averageDelegated: uint256.NewUint(1000),
	}

	initialConfig := Config{
		VotingStartDelay:              100,
		VotingPeriod:                  1000,
		VotingWeightSmoothingDuration: 100,
		Quorum:                        uint256.NewUint(500),
		ProposalCreationThreshold:     uint256.NewUint(100),
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
			Quorum:                        uint256.NewUint(1000),
			ProposalCreationThreshold:     uint256.NewUint(200),
			ExecutionDelay:                200,
			ExecutionWindow:               2000,
		}

		gGovernor.configVersions[1] = newConfig
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
        calldata []byte
        register func(uint64)
        expected []byte
        wantErr  bool
    }{
        {
            name:     "Simple concatenation",
            selector: 1,
            calldata: []byte("World"),
            register: func(selector uint64) {
                RegisterFunction(selector, func(data []byte) ([]byte, error) {
                    return append([]byte("Hello, "), data...), nil
                })
            },
            expected: []byte("Hello, World"),
            wantErr:  false,
        },
        {
            name:     "Uppercase conversion",
            selector: 2,
            calldata: []byte("lowercase"),
            register: func(selector uint64) {
                RegisterFunction(selector, func(data []byte) ([]byte, error) {
                    return bytes.ToUpper(data), nil
                })
            },
            expected: []byte("LOWERCASE"),
            wantErr:  false,
        },
        {
            name:     "Error case",
            selector: 3,
            calldata: []byte("error"),
            register: func(selector uint64) {
                RegisterFunction(selector, func(data []byte) ([]byte, error) {
                    return nil, errors.New("mock error")
                })
            },
            expected: nil,
            wantErr:  true,
        },
        {
            name:     "Unregistered function",
            selector: 4,
            calldata: []byte("test"),
            register: func(selector uint64) {
                // Don't register any function
            },
            expected: nil,
            wantErr:  true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            registry = make(map[uint64]CallFunction)

            tt.register(tt.selector)

            call := Call{
                To:       std.Address("test_address"),
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
                if !bytes.Equal(result, tt.expected) {
                    t.Errorf("executeCall() = %v, want %v", result, tt.expected)
                }
            }
        })
    }
}
