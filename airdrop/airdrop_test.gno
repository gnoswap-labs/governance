package airdrop

import (
	"errors"
	"std"
	"testing"
	"time"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/merkle"
	"gno.land/p/demo/testutils"
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

func TestClaimIDToBitmapIndex(t *testing.T) {
	address := std.Address("test")
	a := NewAirdrop(nil, Config{}, address, nil)

	tests := []struct {
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

	for _, tc := range tests {
		word, index := a.claimIDToBitmapIndex(tc.claimID)
		if word != tc.expectedWord || index != tc.expectedIndex {
			t.Errorf("For claimID %d, expected (%d, %d), got (%d, %d)",
				tc.claimID, tc.expectedWord, tc.expectedIndex, word, index)
		}
	}
}

func TestIsClaimed(t *testing.T) {
	initialClaims := []Claim{
		{ID: 1, Claimee: std.Address("claimee1"), Amount: uint256.NewUint(100)},
		{ID: 2, Claimee: std.Address("claimee2"), Amount: uint256.NewUint(200)},
		{ID: 3, Claimee: std.Address("claimee3"), Amount: uint256.NewUint(300)},
	}

	address := std.Address("test")
	a := NewAirdrop(nil, Config{}, address, initialClaims)

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

	initialClaims := []Claim{
		{ID: 1, Claimee: std.Address("claimee"), Amount: uint256.NewUint(100000)},
		{ID: 2, Claimee: std.Address("claimee2"), Amount: uint256.NewUint(200000)},
		{ID: 3, Claimee: std.Address("claimee3"), Amount: uint256.NewUint(300000)},
	}

	airdrop := NewAirdrop(mockToken, Config{}, address, nil)

	// Set up some initial balances
	airdropAddress := address
	claimeeAddress := std.Address("claimee")
	mockToken.balances[airdropAddress] = 1000000 // Initial balance of airdrop contract

	claim := initialClaims[0]
	proof := airdrop.GetProof(claim)

	// Test successful claim
	// claimed := airdrop.Claim(claim, proof)
	// if !claimed {
	// 	t.Error("Expected claim to be successful")
	// }

	// Check balances after claim
	// airdropBalance := mockToken.BalanceOf(airdropAddress)
	// if airdropBalance != 900000 {
	// 	t.Errorf("Expected airdrop balance to be 900000, got %d", airdropBalance)
	// }
	// claimeeBalance := mockToken.BalanceOf(claimeeAddress)
	// if claimeeBalance != 100000 {
	// 	t.Errorf("Expected claimee balance to be 100000, got %d", claimeeBalance)
	// }

	// // Test claiming again (should fail)
	// claimed = airdrop.Claim(claim, proof)
	// if claimed {
	// 	t.Error("Expected claim to fail (already claimed)")
	// }

	// // Test claim with insufficient balance
	// bigClaim := Claim{
	// 	ID:      2,
	// 	Claimee: claimeeAddress,
	// 	Amount:  uint256.NewUint(1000000), // More than the remaining balance
	// }

	// defer func() {
	// 	if r := recover(); r == nil {
	// 		t.Errorf("should panic")
	// 	} else if r != ErrInsufficientBalance {
	// 		t.Errorf("Expected ErrInsufficientBalance, got %v", r)
	// 	}
	// }()
	// airdrop.Claim(bigClaim, proof)
}

func TestClaim64(t *testing.T) {
	address := std.Address("test")
	mockToken := NewMockGRC20("Test Token", "TST", 18)

	// Create a new Airdrop instance
	airdrop := NewAirdrop(mockToken, Config{}, address, nil)

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
	airdropBalance := mockToken.BalanceOf(airdropAddress)
	if airdropBalance != 936000 { // 1000000 - (64 * 1000)
		t.Errorf("Expected airdrop balance to be 936000, got %d", airdropBalance)
	}
	for i := 0; i < 64; i++ {
		claimeeBalance := mockToken.BalanceOf(std.Address(ufmt.Sprintf("claimee%d", i)))
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

func TestRefund(t *testing.T) {
	token := NewMockGRC20("Test Token", "TST", 18)
	refundTo := testutils.TestAddress("refund_to")
	config := Config{
		RefundableTimestamp: uint64(time.Now().Add(time.Hour).Unix()),
		RefundTo:            refundTo,
	}
	airdrop := NewAirdrop(token, config, testutils.TestAddress("airdrop"), nil)

	// Set some balance for the airdrop contract
	token.balances[airdrop.address] = 1000

	t.Run("Refund before refundable timestamp", func(t *testing.T) {
		defer func() {
			if r := recover(); r == nil {
				t.Errorf("Expected panic but got none")
			} else if r != ErrTooEarly {
				t.Errorf("Expected ErrTooEarly panic but got: %v", r)
			}
		}()
		airdrop.Refund()
	})

	t.Run("Successful refund", func(t *testing.T) {
		// Set current time to after refundable timestamp
		oldTimeNow := timeNow
		timeNow = func() time.Time {
			return time.Unix(int64(config.RefundableTimestamp+1), 0)
		}
		defer func() { timeNow = oldTimeNow }()

		err := airdrop.Refund()
		if err != nil {
			t.Errorf("Unexpected error: %v", err)
		}

		if balance := token.balances[refundTo]; balance != 1000 {
			t.Errorf("Expected refund balance to be 1000, got %d", balance)
		}

		if balance := token.balances[airdrop.address]; balance != 0 {
			t.Errorf("Expected airdrop balance to be 0, got %d", balance)
		}
	})

	// t.Run("Refund with no balance", func(t *testing.T) {
	//     token.balances[airdrop.address] = 0
	//     defer func() {
	//         if r := recover(); r == nil {
	//             t.Errorf("Expected panic but got none")
	//         } else if r != ErrNoBalance {
	//             t.Errorf("Expected ErrNoBalance panic but got: %v", r)
	//         }
	//     }()
	//     airdrop.Refund()
	// })
}

func setupAirdrop() (*Airdrop, *mockGRC20) {
    token := NewMockGRC20("Test Token", "TST", 18)
    config := Config{
        RefundableTimestamp: 0,
        RefundTo:            std.Address("refund_to"),
    }

    initialClaims := []Claim{
        {ID: 1, Claimee: std.Address("claimee1"), Amount: uint256.NewUint(100)},
        {ID: 2, Claimee: std.Address("claimee2"), Amount: uint256.NewUint(200)},
        {ID: 3, Claimee: std.Address("claimee3"), Amount: uint256.NewUint(300)},
    }

    airdrop := NewAirdrop(token, config, std.Address("airdrop"), initialClaims)
    return airdrop, token
}

func TestRootConsistency(t *testing.T) {
	airdrop, _ := setupAirdrop()
	initialRoot := airdrop.snapshots[0].Root

	newClaim := Claim{ID: 4, Claimee: std.Address("claimee4"), Amount: uint256.NewUint(400)}
	airdrop.AddClaim(newClaim)

	newRoot := airdrop.snapshots[1].Root
	if initialRoot == newRoot {
		t.Errorf("Expected new root to be different from initial root")
	}
}

func TestAirdropWithMerkle(t *testing.T) {
	airdrop, token := setupAirdrop()

	// Test initial snapshot
	if root := airdrop.GetLatestRoot(); root == "" {
		t.Errorf("Expected non-empty root, got empty string")
	}

	// Test adding a new claim
	newClaim := Claim{ID: 4, Claimee: std.Address("claimee4"), Amount: uint256.NewUint(400)}
	airdrop.AddClaim(newClaim)

	if len(airdrop.snapshots) != 2 {
		t.Errorf("Expected 2 snapshots, got %d", len(airdrop.snapshots))
	}

	// Test claim verification
	proof := airdrop.GetProof(newClaim)
	if !airdrop.VerifySnapshot(newClaim, proof, 1) {
		t.Errorf("Failed to verify valid claim")
	}
}
