package delegation

import (
	"testing"

	"gno.land/p/demo/testutils"
	"gno.land/p/demo/uint256"
)

func TestGetStaker(t *testing.T) {
	mockStaker := testutils.TestAddress("mockStaker")
	Init(mockStaker, "test token", "TST")

	result := GetStaker()
	if result != mockStaker {
		t.Errorf("GetStaer() = %v, want %v", result, mockStaker)
	}
}

func TestDelegatedTo(t *testing.T) {
    // Initialize the DelegatedToken
    mockStaker := testutils.TestAddress("mockStaker")
    Init(mockStaker, "Test Token", "TST")

    // Create test addresses
    owner1 := testutils.TestAddress("owner1")
    owner2 := testutils.TestAddress("owner2")
    delegate1 := testutils.TestAddress("delegate1")
    delegate2 := testutils.TestAddress("delegate2")

    // Test 1: Initial state - should be delegated to self
    result := GetDelegatedTo(owner1)
    if result != owner1 {
        t.Errorf("Initial GetDelegatedTo(owner1) = %v, want %v", result, owner1)
    }

    // Test 2: Delegate owner1 to delegate1
    Delegate(owner1, delegate1)
    result = GetDelegatedTo(owner1)
    if result != delegate1 {
        t.Errorf("After delegation, GetDelegatedTo(owner1) = %v, want %v", result, delegate1)
    }

    // Test 3: Delegate owner2 to delegate2
    Delegate(owner2, delegate2)
    result = GetDelegatedTo(owner2)
    if result != delegate2 {
        t.Errorf("After delegation, GetDelegatedTo(owner2) = %v, want %v", result, delegate2)
    }

    // Test 4: Check owner1's delegation hasn't changed
    result = GetDelegatedTo(owner1)
    if result != delegate1 {
        t.Errorf("After owner2 delegation, GetDelegatedTo(owner1) = %v, want %v", result, delegate1)
    }

    // Test 5: Change owner1's delegation
    Delegate(owner1, delegate2)
    result = GetDelegatedTo(owner1)
    if result != delegate2 {
        t.Errorf("After changing delegation, GetDelegatedTo(owner1) = %v, want %v", result, delegate2)
    }

    // Test 6: Delegate back to self
    Delegate(owner1, owner1)
    result = GetDelegatedTo(owner1)
    if result != owner1 {
        t.Errorf("After delegating to self, GetDelegatedTo(owner1) = %v, want %v", result, owner1)
    }

    // Test 7: Check non-existent delegation
    nonExistentOwner := testutils.TestAddress("nonExistent")
    result = GetDelegatedTo(nonExistentOwner)
    if result != nonExistentOwner {
        t.Errorf("GetDelegatedTo(nonExistentOwner) = %v, want %v", result, nonExistentOwner)
    }
}
