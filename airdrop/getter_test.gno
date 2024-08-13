package airdrop

import (
	"testing"

	"gno.land/p/demo/testutils"
	"gno.land/p/demo/json"
	u256 "gno.land/p/demo/uint256"
)

func TestGetAirdropConfig(t *testing.T) {
	mockToken := NewMockGRC20("Test Token", "TST", 18)
	refundTo := testutils.TestAddress("refund_to")
	config := Config{
		RefundableTimestamp: 1234567890,
		RefundTo:            refundTo,
	}
	airdrop := NewAirdrop(mockToken, config, refundTo)

	jsonStr := airdrop.GetAirdropConfig()

	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	timestamp, _ := node.MustKey("refundable_timestamp").Value()
	if timestamp != "1234567890" {
		t.Errorf("Expected RefundableTimestamp to be 1234567890, but got %v", timestamp)
	}

	refund, _ := node.MustKey("refund_to").Value()
	if refund != refundTo.String() {
		t.Errorf("Expected RefundTo to be %s, but got %v", refundTo.String(), refund)
	}
}

func TestGetTotalClaims(t *testing.T) {
	mockToken := NewMockGRC20("Test Token", "TST", 18)
	refundTo := testutils.TestAddress("refund_to")
	config := Config{
		RefundableTimestamp: 1234567890,
		RefundTo:            refundTo,
	}
	ardp := NewAirdrop(mockToken, config, refundTo)

	ardp.claimedBitmap[0] = 0b10101010
	ardp.claimedBitmap[1] = 0b01010101
	ardp.claimedBitmap[2] = 0b11111111

	jsonStr := ardp.GetTotalClaims()

	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	totalClaims, _ := node.MustKey("total_claims").Value()
	if totalClaims != "16" {
		t.Errorf("Expected TotalClaims to be 16, but got %v", totalClaims)
	}
}

func TestGetRemainingBalance(t *testing.T) {
	// Create a mock token
	mockToken := NewMockGRC20("Test Token", "TST", 18)

	// Create an airdrop instance
	airdropAddress := testutils.TestAddress("airdrop_address")
	airdrop := NewAirdrop(mockToken, Config{}, airdropAddress)

	// Set up some initial balance
	initialBalance := uint64(1000000)
	mockToken.balances[airdropAddress] = initialBalance

	jsonStr := airdrop.GetRemainingBalance()
	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	remainingBalance, _ := node.MustKey("remaining_balance").GetString()
	if remainingBalance != "1000000" {
		t.Errorf("Expected remaining balance to be 1000000, but got %v", remainingBalance)
	}

	actualBalance, err := u256.FromDecimal(remainingBalance)
	if err != nil {
		t.Fatalf("Failed to convert remaining balance string to uint256: %v", err)
	}

	expectedBalance := u256.NewUint(initialBalance)
	if actualBalance.Cmp(expectedBalance) != 0 {
		t.Errorf(
			"Expected remaining balance to be %s, but got %s",
			expectedBalance.ToString(),
			actualBalance.ToString(),
		)
	}

	/////////////////////////////////////////////////////////////////////////////////

	// Simulate some claims
	claimedAmount := uint64(300000)
	mockToken.balances[airdropAddress] -= claimedAmount

	jsonStr = airdrop.GetRemainingBalance()

	updatedNode, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal updated JSON: %v", err)
	}

	updatedRemainingBalance, _ := updatedNode.MustKey("remaining_balance").GetString()
	if updatedRemainingBalance != "700000" {
		t.Errorf("Expected updated remaining balance to be 700000, but got %v", updatedRemainingBalance)
	}

	updatedActualBalance, err := u256.FromDecimal(updatedRemainingBalance)
	if err != nil {
		t.Fatalf("Failed to convert updated remaining balance string to uint256: %v", err)
	}

	updatedExpectedBalance := u256.NewUint(initialBalance - claimedAmount)
	if updatedActualBalance.Cmp(updatedExpectedBalance) != 0 {
		t.Errorf(
			"Expected updated remaining balance to be %s, but got %s",
			updatedExpectedBalance.ToString(),
			updatedActualBalance.ToString(),
		)
	}
}

func TestGetClaimStatus(t *testing.T) {
	mockToken := NewMockGRC20("Test Token", "TST", 18)

	airdropAddress := testutils.TestAddress("airdrop_address")
	airdrop := NewAirdrop(mockToken, Config{}, airdropAddress)

	// Test unclaimed status
	unclaimedID := uint64(1)
	jsonStr := airdrop.GetClaimStatus(unclaimedID)

	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	claimID, _ := node.MustKey("claim_id").GetString()
	if claimID != "1" {
		t.Errorf("Expected claimID to be 1, but got %v", claimID)
	}

	claimed, _ := node.MustKey("claimed").GetBool()
	if claimed != false {
		t.Errorf("Expected claimed status to be false, but got %v", claimed)
	}

	// Simulate a claim
	claimedID := uint64(2)
	word, bit := airdrop.claimIDToBitmapIndex(claimedID)
	airdrop.claimedBitmap[word] |= 1 << bit

	jsonStr = airdrop.GetClaimStatus(claimedID)

	updatedNode, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	claimID2, _ := updatedNode.MustKey("claim_id").GetString()
	if claimID2 != "2" {
		t.Errorf("Expected claimID to be 2, but got %v", claimID2)
	}

	claimed2, _ := updatedNode.MustKey("claimed").GetBool()
	if claimed2 != false {
		t.Errorf("Expected claimed status to be true, but got %v", claimed2)
	}
}
