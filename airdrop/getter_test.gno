package airdrop

import (
	"std"
	"strconv"
	"testing"

	"gno.land/p/demo/json"
	"gno.land/p/demo/testutils"
	u256 "gno.land/p/demo/uint256"
)

func _setupAirdropConfig(t *testing.T) (*Airdrop, std.Address) {
	mockToken := NewMockGRC20("Test Token", "TST", 18)
	addr := testutils.TestAddress("addr")
	config := Config{
		RefundableTimestamp: 1234567890,
		RefundTo:            addr,
	}
	airdrop := NewAirdrop(mockToken, config, addr)

	return airdrop, addr
}

func TestGetAirdropConfig(t *testing.T) {
	airdrop, refundTo := _setupAirdropConfig(t)

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

	if refund != refundTo.String() {
		t.Errorf("Expected RefundTo to be %s, but got %v", refundTo.String(), refund)
	}
}

func TestGetTotalClaims(t *testing.T) {
	ardp, _ := _setupAirdropConfig(t)

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
	mockToken := NewMockGRC20("Test Token", "TST", 18)

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
	airdrop, _ := _setupAirdropConfig(t)

	tests := []struct {
		name           string
		claimID        uint64
		initiallySet   bool
		expectedStatus bool
	}{
		{
			name:           "Unclaimed ID",
			claimID:        1,
			initiallySet:   false,
			expectedStatus: false,
		},
		{
			name:           "Claimed ID",
			claimID:        2,
			initiallySet:   true,
			expectedStatus: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.initiallySet {
				word, bit := airdrop.claimIDToBitmapIndex(tt.claimID)
				airdrop.claimedBitmap[word] |= 1 << bit
			}

			jsonStr := airdrop.GetClaimStatus(tt.claimID)

			node, err := json.Unmarshal([]byte(jsonStr))
			if err != nil {
				t.Fatalf("Failed to unmarshal JSON: %v", err)
			}

			claimID, err := node.MustKey("claim_id").GetString()
			if err != nil {
				t.Fatalf("Failed to get claim_id: %v", err)
			}

			if claimID != strconv.FormatUint(tt.claimID, 10) {
				t.Errorf("Expected claimID to be %d, but got %v", tt.claimID, claimID)
			}

			claimed, err := node.MustKey("claimed").GetBool()
			if err != nil {
				t.Fatalf("Failed to get claimed: %v", err)
			}

			if claimed != tt.expectedStatus {
				t.Errorf("Expected claimed status to be %v, but got %v", tt.expectedStatus, claimed)
			}
		})
	}
}
