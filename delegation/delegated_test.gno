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

	// apply a custom rule for specific conditions
	customTransferFrom func(from, to std.Address, amount uint64) error
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
	if m.customTransferFrom != nil {
		return m.customTransferFrom(from, to, amount)
	}

	if m.balances[from] < amount {
		return errors.New("insufficient balance")
	}

	m.balances[from] -= amount
	m.balances[to] += amount
	return nil
}

///////////////////////////////////////////////////////////////////////////////////////

var testAddr = testutils.TestAddress("testAddr")

func TestGetStaker(t *testing.T) {
	New(testAddr, nil, "test token", "TST")

	result := GetStaker()
	if result != testAddr {
		t.Errorf("GetStaer() = %v, want %v", result, testAddr)
	}
}

func TestDelegatedTo(t *testing.T) {
	// Initialize the DelegatedToken
	New(testAddr, nil, "Test Token", "TST")

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

func TestDepositAmount(t *testing.T) {
	mockToken := newMockGRC20("Test Token", "TST", 18)
	New(testAddr, mockToken, "Test Token", "TST")

	owner := testutils.TestAddress("owner")
	std.TestSetOrigCaller(owner)

	// Set initial balance and allowance
	initialBalance := uint64(1000)
	allowance := uint64(500)
	depositAmount := u256.NewUint(300)
	mockToken.balances[owner] = initialBalance
	mockToken.Approve(std.GetOrigPkgAddr(), allowance)

	Deposit("300", owner.String())

	// Check balance of delegated tokens
	balance := BalanceOf(owner)
	if balance.Cmp(depositAmount) != 0 {
		t.Errorf("Deposit() failed, BalanceOf() = %v, want %v", balance, depositAmount)
	}

	// Check balance of original tokens
	originalBalance := mockToken.BalanceOf(owner)
	expectedBalance := initialBalance - depositAmount.Uint64()
	if originalBalance != expectedBalance {
		t.Errorf("DepositAmount() failed, original token balance = %v, want %v", originalBalance, expectedBalance)
	}

	// Check total supply
	if gDelegatedToken.totalSupply.Cmp(depositAmount) != 0 {
		t.Errorf("DepositAmount() failed, totalSupply = %v, want %v", gDelegatedToken.totalSupply, depositAmount)
	}
}

func TestDepositZeroAmount(t *testing.T) {
	mockToken := newMockGRC20("Test Token", "TST", 18)
	New(testAddr, mockToken, "Test Token", "TST")

	owner := testutils.TestAddress("owner")
	std.TestSetOrigCaller(owner)

	// Set initial balance and allowance
	mockToken.balances[owner] = 1000
	mockToken.Approve(std.GetOrigPkgAddr(), 500)

	// Attempt to deposit zero amount
	zeroAmount := u256.NewUint(0)
	Deposit("0", owner.String())

	// Check balance of delegated tokens (should be zero)
	balance := BalanceOf(owner)
	if !balance.IsZero() {
		t.Errorf("DepositAmount(0) failed, BalanceOf() = %v, want 0", balance)
	}

	// Check total supply (should be zero)
	if !gDelegatedToken.totalSupply.IsZero() {
		t.Errorf("DepositAmount(0) failed, totalSupply = %v, want 0", gDelegatedToken.totalSupply)
	}
}

func TestWithdraw(t *testing.T) {
	mockToken := newMockGRC20("Test Token", "TST", 18)
	New(testAddr, mockToken, "Test Token", "TST")

	owner := testutils.TestAddress("owner")
	std.TestSetOrigCaller(owner)

	// Set initial balance and deposit
	initialBalance := uint64(1000)
	depositAmount := u256.NewUint(500)
	mockToken.balances[owner] = initialBalance
	mockToken.Approve(std.GetOrigPkgAddr(), depositAmount.Uint64())
	Deposit(depositAmount.ToString(), owner.String())

	// Check initial delegated token balance
	delegatedBalance := BalanceOf(owner)
	if delegatedBalance.Cmp(depositAmount) != 0 {
		t.Errorf("Initial BalanceOf() = %v, want %v", delegatedBalance, depositAmount)
	}

	partialWithdrawAmount := "200"
	Withdraw(partialWithdrawAmount, owner.String())

	// Check delegated token balance after withdrawal (should be zero)
	delegatedBalance = BalanceOf(owner)

	expectedDelegatedBalance := u256.NewUint(300) // 500 - 200
	if delegatedBalance.Cmp(expectedDelegatedBalance) != 0 {
		t.Errorf("After Withdraw(), BalanceOf() = %v, want %v", delegatedBalance, expectedDelegatedBalance)
	}

	// Check original token balance after withdrawal
	originalBalance := mockToken.BalanceOf(owner)
	expectedBalance := initialBalance - depositAmount.Uint64() // 1000 - 500 = 500
	if originalBalance != expectedBalance {
		t.Errorf("After Withdraw(), original token balance = %v, want %v", originalBalance, expectedBalance)
	}
}
