package staker

import (
	"std"
	"strings"
	"testing"

	"gno.land/p/demo/testutils"
	"gno.land/p/demo/json"
	"gno.land/p/demo/grc/grc20"
	u256 "gno.land/p/demo/uint256"
	"gno.land/p/demo/ufmt"
)

func TestGetAllDelegations(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 42)
	Init(token)

	addr1 := testutils.TestAddress("addr1")
	addr2 := testutils.TestAddress("addr2")

	gStaker.delegations[addr1] = u256.NewUint(100)
	gStaker.delegations[addr2] = u256.NewUint(200)

	jsonStr := GetAllDelegations()

	// Check if the JSON string contains the expected key-value pairs
	expectedPairs := []string{
		ufmt.Sprintf(`"address":"%s","amount":"100"`, addr1),
		ufmt.Sprintf(`"address":"%s","amount":"200"`, addr2),
	}

	for _, pair := range expectedPairs {
		if !strings.Contains(jsonStr, pair) {
			t.Errorf("Expected JSON to contain %s, but it doesn't. JSON: %s", pair, jsonStr)
		}
	}

	if !strings.HasPrefix(jsonStr, "[") || !strings.HasSuffix(jsonStr, "]") {
		t.Errorf("JSON string is not properly formatted. JSON: %s", jsonStr)
	}
}

func TestGetDelegationHistory(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 42)
	Init(token)

	// Add some test delegation history
	testAddr := testutils.TestAddress("testAddr")
	gStaker.delegationHistory[testAddr] = []DelegationHistory{
		{timestamp: 1000, amount: u256.NewUint(100)},
		{timestamp: 2000, amount: u256.NewUint(200)},
		{timestamp: 3000, amount: u256.NewUint(300)},
		{timestamp: 4000, amount: u256.NewUint(400)},
	}

	// Test cases
	tests := []struct {
		name      string
		startTime uint64
		endTime   uint64
		expected  string
	}{
		{
			name:      "All entries",
			startTime: 0,
			endTime:   5000,
			expected:  `[{"timestamp":1000,"amount":"100"},{"timestamp":2000,"amount":"200"},{"timestamp":3000,"amount":"300"},{"timestamp":4000,"amount":"400"}]`,
		},
		{
			name:      "Middle entries",
			startTime: 1500,
			endTime:   3500,
			expected:  `[{"timestamp":2000,"amount":"200"},{"timestamp":3000,"amount":"300"}]`,
		},
		{
			name:      "No entries",
			startTime: 5000,
			endTime:   6000,
			expected:  `[]`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GetDelegationHistory(testAddr.String(), tt.startTime, tt.endTime)
			if result != tt.expected {
				t.Errorf("Expected %s, but got %s", tt.expected, result)
			}
		})
	}
}

func TestGetRecentDelegationHistory(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 42)
	Init(token)

	testAddr := testutils.TestAddress("testAddr")
	gStaker.delegationHistory[testAddr] = []DelegationHistory{
		{timestamp: 1000, amount: u256.NewUint(100)},
		{timestamp: 2000, amount: u256.NewUint(200)},
		{timestamp: 3000, amount: u256.NewUint(300)},
		{timestamp: 4000, amount: u256.NewUint(400)},
		{timestamp: 5000, amount: u256.NewUint(500)},
	}

	// Test cases
	tests := []struct {
		name     string
		n        int
		expected string
	}{
		{
			name:     "Last 3 entries",
			n:        3,
			expected: `[{"timestamp":3000,"amount":"300"},{"timestamp":4000,"amount":"400"},{"timestamp":5000,"amount":"500"}]`,
		},
		{
			name:     "All entries",
			n:        10,
			expected: `[{"timestamp":1000,"amount":"100"},{"timestamp":2000,"amount":"200"},{"timestamp":3000,"amount":"300"},{"timestamp":4000,"amount":"400"},{"timestamp":5000,"amount":"500"}]`,
		},
		{
			name:     "Last entry",
			n:        1,
			expected: `[{"timestamp":5000,"amount":"500"}]`,
		},
		{
			name:     "No entries",
			n:        0,
			expected: `[]`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GetRecentDelegationHistory(testAddr.String(), tt.n)
			if result != tt.expected {
				t.Errorf("Expected %s, but got %s", tt.expected, result)
			}
		})
	}

	// Test with non-existent address
	nonExistentAddr := testutils.TestAddress("nonExistentAddr")
	result := GetRecentDelegationHistory(nonExistentAddr.String(), 5)
	if result != "[]" {
		t.Errorf("Expected [] for non-existent address, but got %s", result)
	}
}
