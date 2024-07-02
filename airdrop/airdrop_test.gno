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
    balances  map[std.Address]uint64
    allowances map[std.Address]map[std.Address]uint64
    totalSupply uint64
    name string
    symbol string
    decimals uint8
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

func TestNewAirdrop(t *testing.T) {
    token := &mockGRC20{}
    config := Config{
        Root:                [32]byte{},
        RefundableTimestamp: 1000,
        RefundTo:            "refundAddress",
    }
    claims := []Claim{
        {ID: 0, Claimee: "user1", Amount: uint256.NewUint(100)},
        {ID: 1, Claimee: "user2", Amount: uint256.NewUint(200)},
    }

    airdrop, err := NewAirdrop(token, config, claims)
    if err != nil {
        t.Fatalf("NewAirdrop failed: %v", err)
    }

    if airdrop.token != token {
        t.Errorf("Expected token to be set correctly")
    }
    if airdrop.config != config {
        t.Errorf("Expected config to be set correctly")
    }
    if len(airdrop.claimedBitmap) != 0 {
        t.Errorf("Expected claimedBitmap to be empty initially")
    }
    if airdrop.merkleTree == nil {
        t.Errorf("Expected merkleTree to be initialized")
    }
}

func TestIsClaimed(t *testing.T) {
    airdrop := &Airdrop{
        claimedBitmap: make(map[uint64]*uint256.Uint),
    }

    // Test unclaimed
    if airdrop.IsClaimed(1) {
        t.Errorf("Expected claim 1 to be unclaimed")
    }

    // Set claim 1 as claimed
    word, index := airdrop.claimIDToBitmapIndex(1)
    airdrop.claimedBitmap[word] = new(uint256.Uint).Lsh(uint256.NewUint(1), uint(index))

    // Test claimed
    if !airdrop.IsClaimed(1) {
        t.Errorf("Expected claim 1 to be claimed")
    }
}

// func TestClaim(t *testing.T) {
//     token := &mockGRC20{}
//     config := Config{
//         Root:                [32]byte{},
//         RefundableTimestamp: 1000,
//         RefundTo:            "refundAddress",
//     }
//     claims := []Claim{
//         {ID: 0, Claimee: "user1", Amount: uint256.NewUint(100)},
//         {ID: 1, Claimee: "user2", Amount: uint256.NewUint(200)},
//     }

//     airdrop, _ := NewAirdrop(token, config, claims)

//     // Mock the verifyProof function
//     airdrop.verifyProof = func(claim Claim, proof [][]byte) (bool, error) {
//         return true, nil
//     }

//     claimed, err := airdrop.Claim(claims[0], nil)
//     if err != nil {
//         t.Fatalf("Claim failed: %v", err)
//     }
//     if !claimed {
//         t.Errorf("Expected claim to be successful")
//     }

//     // Check if the claim is marked as claimed
//     if !airdrop.IsClaimed(0) {
//         t.Errorf("Expected claim 0 to be marked as claimed")
//     }

//     // Check if the token transfer occurred
//     if token.balances["user1"] != 100 {
//         t.Errorf("Expected 100 tokens to be transferred to user1")
//     }

//     // Try to claim again
//     claimed, err = airdrop.Claim(claims[0], nil)
//     if err != nil {
//         t.Fatalf("Claim failed: %v", err)
//     }
//     if claimed {
//         t.Errorf("Expected second claim attempt to fail")
//     }
// }

// func TestClaim128(t *testing.T) {
//     token := &mockGRC20{}
//     config := Config{
//         Root:                [32]byte{},
//         RefundableTimestamp: 1000,
//         RefundTo:            "refundAddress",
//     }
//     claims := make([]Claim, 128)
//     for i := 0; i < 128; i++ {
//         claims[i] = Claim{ID: uint64(i), Claimee: ufmt.Sprintf("user%d", i), Amount: uint256.NewUint(uint64(100 + i))}
//     }

//     airdrop, _ := NewAirdrop(token, config, claims)

//     claimedCount, err := airdrop.Claim128(claims, nil)
//     if err != nil {
//         t.Fatalf("Claim128 failed: %v", err)
//     }
//     if claimedCount != 128 {
//         t.Errorf("Expected 128 claims to be processed, got %d", claimedCount)
//     }

//     // Check if all claims are marked as claimed
//     for i := 0; i < 128; i++ {
//         if !airdrop.IsClaimed(uint64(i)) {
//             t.Errorf("Expected claim %d to be marked as claimed", i)
//         }
//     }

//     // Check if token transfers occurred
//     for i := 0; i < 128; i++ {
//         if token.balances[std.Address(ufmt.Sprintf("user%d", i))] != uint64(100+i) {
//             t.Errorf("Expected %d tokens to be transferred to user%d", 100+i, i)
//         }
//     }

//     // Try to claim again
//     claimedCount, err = airdrop.Claim128(claims, nil)
//     if err != nil {
//         t.Fatalf("Claim128 failed: %v", err)
//     }
//     if claimedCount != 0 {
//         t.Errorf("Expected second Claim128 attempt to claim 0, got %d", claimedCount)
//     }
// }
