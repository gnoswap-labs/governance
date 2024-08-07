package staker

import (
	"errors"
	"std"
	"testing"
	"time"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/testutils"
	"gno.land/p/demo/ufmt"
	u256 "gno.land/p/demo/uint256"
)

// mockGRC20 is a mock implementation of the IGRC20 interface for testing
type mockGRC20 struct {
	balances    map[std.Address]uint64
	allowances  map[std.Address]map[std.Address]uint64
	totalSupply uint64
	name        string
	symbol      string
	decimals    uint8
}

// newMockGRC20 creates a new instance of mockGRC20
func newMockGRC20(name, symbol string, decimals uint8) *mockGRC20 {
	return &mockGRC20{
		balances:   make(map[std.Address]uint64),
		allowances: make(map[std.Address]map[std.Address]uint64),
		name:       name,
		symbol:     symbol,
		decimals:   decimals,
	}
}

func (m *mockGRC20) GetName() string {
	return m.name
}

func (m *mockGRC20) GetSymbol() string {
	return m.symbol
}

func (m *mockGRC20) GetDecimals() uint {
	return uint(m.decimals)
}

func (m *mockGRC20) TotalSupply() uint64 {
	return m.totalSupply
}

func (m *mockGRC20) BalanceOf(account std.Address) uint64 {
	return m.balances[account]
}

func (m *mockGRC20) Transfer(to std.Address, amount uint64) error {
	from := std.GetOrigCaller()
	if m.balances[from] < amount {
		return errors.New("insufficient balance")
	}
	m.balances[from] -= amount
	m.balances[to] += amount
	return nil
}

func (m *mockGRC20) Allowance(owner, spender std.Address) uint64 {
	return m.allowances[owner][spender]
}

func (m *mockGRC20) Approve(spender std.Address, amount uint64) error {
	owner := std.GetOrigCaller()
	if m.allowances[owner] == nil {
		m.allowances[owner] = make(map[std.Address]uint64)
	}
	m.allowances[owner][spender] = amount
	return nil
}

func (m *mockGRC20) TransferFrom(from, to std.Address, amount uint64) error {
	if m.balances[from] < amount {
		return ErrInsufficientBalance
	}
	m.balances[from] -= amount
	m.balances[to] += amount
	return nil
}

///////////////////////////////////////////////////////////////////////////////////////

func TestStakeAmount(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 42)
	Init(token)

	delegateAddr := testutils.TestAddress("delegate")
	delegate := delegateAddr.String()

	// Set up some balance for the caller
	caller := std.GetOrigCaller()
	token.balances[caller] = 1000

	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("StakeAmount panicked: %v", r)
		}
	}()
	StakeAmount(delegate, "100")

	if gStaker.delegations[delegateAddr].Uint64() != 100 {
		t.Errorf("StakeAmount did not update delegations correctly")
	}

	if gStaker.totalStaked.Uint64() != 100 {
		t.Errorf("StakeAmount did not update totalStaked correctly")
	}

	if len(gStaker.delegationHistory[delegateAddr]) != 1 {
		t.Errorf("StakeAmount did not add to delegationHistory")
	}
}

func TestWithdrawAmount(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 42)
	Init(token)

	caller := std.GetOrigCaller()
	delegate := caller.String()

	recipientAddr := testutils.TestAddress("recipient")
	recipient := recipientAddr.String()

	withdrawAmount := u256.NewUint(50)

	// First, stake some amount
	token.balances[caller] = 1000

	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("WithdrawAmount panicked: %v", r)
		}
	}()
	StakeAmount(delegate, "100")

	// now, try to withdraw
	WithdrawAmount(delegate, recipient, "50")

	if gStaker.delegations[caller].Uint64() != 50 {
		t.Errorf("WithdrawAmount did not update delegations correctly")
	}

	if gStaker.totalStaked.Uint64() != 50 {
		t.Errorf("WithdrawAmount did not update totalStaked correctly")
	}

	if len(gStaker.delegationHistory[caller]) != 2 {
		t.Errorf("WithdrawAmount did not add to delegationHistory")
	}

	recipientBalance := token.BalanceOf(recipientAddr)
	if recipientBalance != 50 {
		t.Errorf("WithdrawAmount did not transfer tokens correctly")
	}
}

func TestGetAverageDelegated(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 42)
	Init(token)

	delegateAddr := testutils.TestAddress("delegate")
	delegate := delegateAddr.String()

	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("GetAverageDelegated panicked: %v", r)
		}
	}()
	StakeAmount(delegate, "0")

	// simulate time passing and additional stakes
	currentTime := uint64(1000)
	gStaker.delegationHistory[delegateAddr] = []DelegationHistory{
		{amount: u256.NewUint(1000), timestamp: currentTime},
		{amount: u256.NewUint(1500), timestamp: currentTime + 100},
		{amount: u256.NewUint(2000), timestamp: currentTime + 200},
	}

	tests := []struct {
		name           string
		start          uint64
		end            uint64
		expectedResult string
	}{
		{
			name:           "Full period average",
			start:          currentTime,
			end:            currentTime + 200,
			expectedResult: "1250", // (1000*100 + 1500*100 + 2000*0) / 200
		},
		{
			name:           "Partial period average",
			start:          currentTime + 50,
			end:            currentTime + 150,
			expectedResult: "1250", // (1000*50 + 1500*50) / 100
		},
		{
			name:           "Single point in time",
			start:          currentTime + 100,
			end:            currentTime + 100,
			expectedResult: "1500",
		},
		{
			name:           "Period before any stakes",
			start:          currentTime - 100,
			end:            currentTime - 50,
			expectedResult: "0",
		},
		{
			name:           "Period after all recorded stakes",
			start:          currentTime + 300,
			end:            currentTime + 400,
			expectedResult: "2000",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := GetAverageDelegated(delegate, tt.start, tt.end)
			if err != nil {
				t.Fatalf("Unexpected error: %v", err)
			}
			if result != tt.expectedResult {
				t.Errorf("Expected %s, got %s", tt.expectedResult, result)
			}
		})
	}
}

func TestGetAverageDelegatedOverLast(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 42)
	Init(token)

	delegateAddr := testutils.TestAddress("delegate")
	delegate := delegateAddr.String()

	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("GetAverageDelegatedOverLast panicked: %v", r)
		}
	}()
	StakeAmount(delegate, "0")

	// Set up delegation history
	now := uint64(time.Now().Unix())
	gStaker.delegationHistory[delegateAddr] = []DelegationHistory{
		{amount: u256.NewUint(1000), timestamp: now - 100},
		{amount: u256.NewUint(2000), timestamp: now - 50},
		{amount: u256.NewUint(3000), timestamp: now},
	}

	avg, err := GetAverageDelegatedOverLast(delegate, uint64(100))
	if err != nil {
		t.Fatalf("GetAverageDelegatedOverLast failed: %v", err)
	}

	if avg != "1500" { // (1000*50 + 2000*50) / 100
		t.Errorf("Expected 1500, got %s", avg)
	}
}

func TestGetCurrentDelegated(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 18)
	Init(token)

	delegate1 := testutils.TestAddress("delegate1")
	delegate2 := testutils.TestAddress("delegate2")

	// Set up delegation history for delegate1
	gStaker.delegationHistory[delegate1] = []DelegationHistory{
		{amount: u256.NewUint(1000), timestamp: 100},
		{amount: u256.NewUint(1500), timestamp: 200},
		{amount: u256.NewUint(2000), timestamp: 300},
	}

	tests := []struct {
		name           string
		delegate       string
		expectedResult string
	}{
		{
			name:           "Delegate with history",
			delegate:       delegate1.String(),
			expectedResult: "2000",
		},
		{
			name:           "Delegate without history",
			delegate:       delegate2.String(),
			expectedResult: "0",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := GetCurrentDelegated(tt.delegate)
			if err != nil {
				t.Fatalf("Unexpected error: %v", err)
			}
			if result != tt.expectedResult {
				t.Errorf("Expected %s, got %s", tt.expectedResult, result)
			}
		})
	}
}

func TestGetDelegatedAt(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 18)
	Init(token)

	delegateAddr := testutils.TestAddress("delegate")
	delegate := delegateAddr.String()

	gStaker.delegationHistory[delegateAddr] = []DelegationHistory{
		{amount: u256.NewUint(1000), timestamp: 100},
		{amount: u256.NewUint(1500), timestamp: 200},
		{amount: u256.NewUint(2000), timestamp: 300},
	}

	tests := []struct {
		name           string
		timestamp      uint64
		expectedResult string
	}{
		{
			name:           "Before first delegation",
			timestamp:      50,
			expectedResult: "0",
		},
		{
			name:           "At first delegation",
			timestamp:      100,
			expectedResult: "1000",
		},
		{
			name:           "Between first and second delegation",
			timestamp:      150,
			expectedResult: "1000",
		},
		{
			name:           "At second delegation",
			timestamp:      200,
			expectedResult: "1500",
		},
		{
			name:           "At last delegation",
			timestamp:      300,
			expectedResult: "2000",
		},
		{
			name:           "After last delegation",
			timestamp:      400,
			expectedResult: "2000",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := GetDelegatedAt(delegate, tt.timestamp)
			if err != nil {
				t.Fatalf("Unexpected error: %v", err)
			}
			if result != tt.expectedResult {
				t.Errorf("Expected %s, got %s", tt.expectedResult, result)
			}
		})
	}

	t.Run("Non-existent delegate", func(t *testing.T) {
		result, err := GetDelegatedAt("dummy", uint64(200))
		if err != nil {
			t.Fatalf("Unexpected error: %v", err)
		}
		if result != "0" {
			t.Errorf("Expected 0, got %s", result)
		}
	})
}
