package airdrop

import (
	"errors"
	"std"
	"testing"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/merkle"
	"gno.land/p/demo/ufmt"
	"gno.land/p/demo/uint256"
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

// NewMockGRC20 creates a new instance of mockGRC20
func NewMockGRC20(name, symbol string, decimals uint8) *mockGRC20 {
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

func (m *mockGRC20) BalanceOf(account std.Address) (uint64, error) {
	return m.balances[account], nil
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

func (m *mockGRC20) Allowance(owner, spender std.Address) (uint64, error) {
	return m.allowances[owner][spender], nil
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
	spender := std.GetOrigCaller()
	allowance, _ := m.Allowance(from, spender)
	if allowance < amount {
		return errors.New("insufficient allowance")
	}
	if m.balances[from] < amount {
		return errors.New("insufficient balance")
	}
	m.balances[from] -= amount
	m.balances[to] += amount
	m.allowances[from][spender] -= amount
	return nil
}

///////////////////////////////////////////////////////////////////////////////////////

func TestClaimIDToBitmapIndex(t *testing.T) {
	address := std.Address("test")
	a := NewAirdrop(nil, Config{}, address)

	testCases := []struct {
		claimID       uint64
		expectedWord  uint64
		expectedIndex uint64
	}{
		{0, 0, 0},
		{63, 0, 63},
		{64, 1, 0},
		{128, 2, 0},
		{129, 2, 1},
	}

	for _, tc := range testCases {
		word, index := a.claimIDToBitmapIndex(tc.claimID)
		if word != tc.expectedWord || index != tc.expectedIndex {
			t.Errorf("For claimID %d, expected (%d, %d), got (%d, %d)",
				tc.claimID, tc.expectedWord, tc.expectedIndex, word, index)
		}
	}
}

func TestIsClaimed(t *testing.T) {
	address := std.Address("test")
	a := NewAirdrop(nil, Config{}, address)

	// Test unclaimed
	if a.IsClaimed(0) {
		t.Error("Expected claim 0 to be unclaimed")
	}

	// Set claim 0 as claimed
	a.claimedBitmap[0] = 1

	// Test claimed
	if !a.IsClaimed(0) {
		t.Error("Expected claim 0 to be claimed")
	}

	// Test unclaimed (different word)
	if a.IsClaimed(64) {
		t.Error("Expected claim 64 to be unclaimed")
	}
}

func TestClaim(t *testing.T) {
	address := std.Address("test")
	mockToken := NewMockGRC20("Test Token", "TST", 18)

	airdrop := NewAirdrop(mockToken, Config{}, address)

	// Set up some initial balances
	airdropAddress := std.GetOrigCaller()
	claimeeAddress := std.Address("claimee")
	mockToken.balances[airdropAddress] = 1000000 // Initial balance of airdrop contract

	claim := Claim{
		ID:      1,
		Claimee: claimeeAddress,
		Amount:  uint256.NewUint(100000),
	}

	// Test successful claim
	claimed, err := airdrop.Claim(claim)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if !claimed {
		t.Error("Expected claim to be successful")
	}

	// Check balances after claim
	airdropBalance, _ := mockToken.BalanceOf(airdropAddress)
	if airdropBalance != 900000 {
		t.Errorf("Expected airdrop balance to be 900000, got %d", airdropBalance)
	}
	claimeeBalance, _ := mockToken.BalanceOf(claimeeAddress)
	if claimeeBalance != 100000 {
		t.Errorf("Expected claimee balance to be 100000, got %d", claimeeBalance)
	}

	// Test claiming again (should fail)
	claimed, err = airdrop.Claim(claim)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if claimed {
		t.Error("Expected claim to fail (already claimed)")
	}

	// Test claim with insufficient balance
	bigClaim := Claim{
		ID:      2,
		Claimee: claimeeAddress,
		Amount:  uint256.NewUint(1000000), // More than the remaining balance
	}

	defer func() {
		if r := recover(); r == nil {
			t.Errorf("should panic")
		} else if r != ErrInsufficientBalance {
			t.Errorf("Expected ErrInsufficientBalance, got %v", r)
		}
	}()
	airdrop.Claim(bigClaim)
}

func TestClaim64(t *testing.T) {
	address := std.Address("test")
	mockToken := NewMockGRC20("Test Token", "TST", 18)

	// Create a new Airdrop instance
	airdrop := NewAirdrop(mockToken, Config{}, address)

	// Set up some initial balances
	airdropAddress := std.GetOrigCaller()
	mockToken.balances[airdropAddress] = 1000000 // Initial balance of airdrop contract

	// Create 64 claims
	claims := make([]Claim, 64)
	for i := 0; i < 64; i++ {
		claims[i] = Claim{
			ID:      uint64(i * 64), // Ensure first claim ID is multiple of 64
			Claimee: std.Address(ufmt.Sprintf("claimee%d", i)),
			Amount:  uint256.NewUint(1000), // Each claim is for 1000 tokens
		}
	}

	// Test successful batch claim
	claimed, _ := airdrop.Claim64(claims)
	if claimed != 64 {
		t.Errorf("Expected 64 claims, got %d", claimed)
	}

	// Check balances after claims
	airdropBalance, _ := mockToken.BalanceOf(airdropAddress)
	if airdropBalance != 936000 { // 1000000 - (64 * 1000)
		t.Errorf("Expected airdrop balance to be 936000, got %d", airdropBalance)
	}
	for i := 0; i < 64; i++ {
		claimeeBalance, _ := mockToken.BalanceOf(std.Address(ufmt.Sprintf("claimee%d", i)))
		if claimeeBalance != 1000 {
			t.Errorf("Expected claimee%d balance to be 1000, got %d", i, claimeeBalance)
		}
	}

	// Test claiming again (should claim 0)
	claimed, _ = airdrop.Claim64(claims)
	if claimed != 0 {
		t.Errorf("Expected 0 claims, got %d", claimed)
	}

	// Test with insufficient balance
	bigClaims := make([]Claim, 64)
	for i := 0; i < 64; i++ {
		bigClaims[i] = Claim{
			ID:      uint64((i + 1) * 64),
			Claimee: std.Address(ufmt.Sprintf("claimee%d", i)),
			Amount:  uint256.NewUint(20000), // Each claim is for 20000 tokens, which is more than the remaining balance
		}
	}

	defer func() {
		if r := recover(); r == nil {
			t.Errorf("The code did not panic")
		} else if r != ErrInsufficientBalance {
			t.Errorf("Expected ErrInsufficientBalance panic, got %v", r)
		}
	}()

	airdrop.Claim64(bigClaims)

	// Test with invalid claim count
	invalidClaims := make([]Claim, 65) // 65 claims, which is more than allowed

	defer func() {
		if r := recover(); r == nil {
			t.Errorf("The code did not panic")
		} else if r != ErrInvalidClaimsCount {
			t.Errorf("Expected ErrInvalidClaimsCount panic, got %v", r)
		}
	}()

	airdrop.Claim64(invalidClaims)

	// Test with invalid first claim ID
	invalidFirstClaim := make([]Claim, 64)
	invalidFirstClaim[0] = Claim{ID: 1} // First claim ID is not a multiple of 64

	defer func() {
		if r := recover(); r == nil {
			t.Errorf("The code did not panic")
		} else if r != ErrFirstClaimIsNot64 {
			t.Errorf("Expected ErrFirstClaimIsNot64 panic, got %v", r)
		}
	}()

	airdrop.Claim64(invalidFirstClaim)
}
