package airdrop

import (
	"std"
	"testing"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/uint256"
)

func TestAirdropClaimCheck(t *testing.T) {
	// Create a mock token
	mockToken := NewMockGRC20("Test Token", "TST", 18)

	// Create an airdrop instance
	airdropAddress := std.Address("airdrop_address")
	airdrop := NewAirdrop(mockToken, Config{}, airdropAddress, nil)

	// Set up some initial balances
	mockToken.balances[airdropAddress] = 1000000 // Initial balance of airdrop contract

	// Create an AirdropClaimCheck instance
	claimCheck := NewAirdropClaimCheck()

	// Create some test claims
	claims := []CheckParams{
		{
			Airdrop: airdrop,
			ClaimID: 0,
			Amount:  uint256.NewUint(500000),
		},
		{
			Airdrop: airdrop,
			ClaimID: 1,
			Amount:  uint256.NewUint(500000),
		},
		{
			Airdrop: airdrop,
			ClaimID: 2,
			Amount:  uint256.NewUint(1500000), // More than the balance
		},
	}

	// Simulate a claimed airdrop
	airdrop.claimedBitmap[0] = 2 // Binary 10, meaning claim ID 1 is claimed

	// Check the claims
	results := claimCheck.Check(claims)

	// Verify the results
	if len(results) != 3 {
		t.Fatalf("Expected 3 results, got %d", len(results))
	}

	// Check first claim (ID: 0)
	if results[0].Claimed {
		t.Error("Expected first claim to not be claimed")
	}
	if !results[0].Funded {
		t.Error("Expected first claim to be funded")
	}

	// Check second claim (ID: 1)
	if !results[1].Claimed {
		t.Error("Expected second claim to be claimed")
	}
	if !results[1].Funded {
		t.Error("Expected second claim to be funded")
	}

	// Check third claim (ID: 2)
	if results[2].Claimed {
		t.Error("Expected third claim to not be claimed")
	}
	if results[2].Funded {
		t.Error("Expected third claim to not be funded")
	}

	// Test with insufficient balance for all claims
	bigClaims := []CheckParams{
		{
			Airdrop: airdrop,
			ClaimID: 3,
			Amount:  uint256.NewUint(2000000), // More than the total balance
		},
	}

	bigResults := claimCheck.Check(bigClaims)

	if len(bigResults) != 1 {
		t.Fatalf("Expected 1 result, got %d", len(bigResults))
	}

	if bigResults[0].Claimed {
		t.Error("Expected big claim to not be claimed")
	}
	if bigResults[0].Funded {
		t.Error("Expected big claim to not be funded")
	}

	// Test with zero balance
	mockToken.balances[airdropAddress] = 0
	zeroBalanceResults := claimCheck.Check(claims)

	for i, result := range zeroBalanceResults {
		if result.Funded {
			t.Errorf("Expected claim %d to not be funded with zero balance", i)
		}
	}
}
