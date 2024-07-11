package delegation

import (
	"errors"
	"std"
	"testing"

	"gno.land/p/demo/testutils"
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
		return errors.New("insufficient balance")
	}
	m.balances[from] -= amount
	m.balances[to] += amount
	return nil
}

///////////////////////////////////////////////////////////////////////////////////////

func TestGetStaker(t *testing.T) {
	mockStaker := testutils.TestAddress("mockStaker")
	Init(mockStaker, nil, "test token", "TST")

	result := GetStaker()
	if result != mockStaker {
		t.Errorf("GetStaer() = %v, want %v", result, mockStaker)
	}
}

func TestDelegatedTo(t *testing.T) {
    // Initialize the DelegatedToken
    mockStaker := testutils.TestAddress("mockStaker")
    Init(mockStaker, nil, "Test Token", "TST")

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

func TestDeposit(t *testing.T) {
	mockTokenAddress := testutils.TestAddress("mockToken")
	mockToken := newMockGRC20("Test Token", "TST", 18)
	Init(mockTokenAddress, mockToken, "Test Token", "TST")

	// Set the mock token as the staker (which is also the token in this case)
	gDelegatedToken.staker = mockTokenAddress

	owner := std.GetOrigCaller()

	// Set initial balance and allowance
	initialBalance := uint64(1000)
	allowance := uint64(500)
	mockToken.balances[owner] = initialBalance
	mockToken.Approve(std.GetOrigPkgAddr(), allowance)

	// Mock the token transfer
	oldTransferFrom := mockToken.TransferFrom
	mockToken.TransferFrom = func(from, to std.Address, amount uint64) error {
		if from == owner && to == std.GetOrigPkgAddr() && amount <= allowance {
			mockToken.balances[from] -= amount
			mockToken.balances[to] += amount
			return nil
		}
		return oldTransferFrom(from, to, amount)
	}

	// Call Deposit
	Deposit()

	// Check balance of delegated tokens
	balance := BalanceOf(owner)
	if balance.Cmp(u256.NewUint(allowance)) != 0 {
		t.Errorf("Deposit() failed, BalanceOf() = %v, want %v", balance, allowance)
	}

	// Check balance of original tokens
	originalBalance := mockToken.balances[owner]
	expectedOriginalBalance := initialBalance - allowance
	if originalBalance != expectedOriginalBalance {
		t.Errorf("Deposit() failed, original token balance = %v, want %v", originalBalance, expectedOriginalBalance)
	}

	// Check total supply
	if gDelegatedToken.totalSupply.Cmp(u256.NewUint(allowance)) != 0 {
		t.Errorf("Deposit() failed, totalSupply = %v, want %v", gDelegatedToken.totalSupply, allowance)
	}
}
