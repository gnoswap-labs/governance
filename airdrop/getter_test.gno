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

	jsonStr := AirdropToJSON(airdrop)
	result := GetAirdropConfig(jsonStr)

	node, err := json.Unmarshal([]byte(result))
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

	jsonStr := AirdropToJSON(ardp)

	result := GetTotalClaims(jsonStr)

	node, err := json.Unmarshal([]byte(result))
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

	airdropJSON := AirdropToJSON(airdrop)

	jsonStr := GetRemainingBalance(airdropJSON)
	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	remainingBalance := node.MustKey("remaining_balance").MustString()
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

	// Update airdrop JSON
	airdropJSON = AirdropToJSON(airdrop)

	jsonStr = GetRemainingBalance(airdropJSON)

	updatedNode, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal updated JSON: %v", err)
	}

	updatedRemainingBalance := updatedNode.MustKey("remaining_balance").MustString()
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

			jsonStr := AirdropToJSON(airdrop)
			res := GetClaimStatus(jsonStr, tt.claimID)

			node, err := json.Unmarshal([]byte(res))
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

func TestAirdropToJSONAndCreateAirdropFromJSON(t *testing.T) {
	mockToken := NewMockGRC20("Test Token", "TST", 18)
	airdropAddress := testutils.TestAddress("airdrop_address")
	refundTo := testutils.TestAddress("refund_to")
	config := Config{
		RefundableTimestamp: 1234567890,
		RefundTo:            refundTo,
	}
	airdrop := NewAirdrop(mockToken, config, airdropAddress)

	// Set some claimed bits
	airdrop.claimedBitmap[0] = 0b101
	airdrop.claimedBitmap[1] = 0b11010

	jsonStr := AirdropToJSON(airdrop)
	newAirdrop := createAirdropFromJSON(jsonStr)

	if newAirdrop.config.RefundableTimestamp != airdrop.config.RefundableTimestamp {
		t.Errorf("RefundableTimestamp mismatch. Expected %d, got %d",
			airdrop.config.RefundableTimestamp, newAirdrop.config.RefundableTimestamp)
	}

	if newAirdrop.config.RefundTo != airdrop.config.RefundTo {
		t.Errorf("RefundTo mismatch. Expected %s, got %s",
			airdrop.config.RefundTo, newAirdrop.config.RefundTo)
	}

	if newAirdrop.address != airdrop.address {
		t.Errorf("Address mismatch. Expected %s, got %s",
			airdrop.address, newAirdrop.address)
	}

	if len(newAirdrop.claimedBitmap) != len(airdrop.claimedBitmap) {
		t.Errorf("ClaimedBitmap length mismatch. Expected %d, got %d",
			len(airdrop.claimedBitmap), len(newAirdrop.claimedBitmap))
	}

	for k, v := range airdrop.claimedBitmap {
		if newAirdrop.claimedBitmap[k] != v {
			t.Errorf("ClaimedBitmap mismatch for key %d. Expected %d, got %d",
				k, v, newAirdrop.claimedBitmap[k])
		}
	}

	root, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	configNode := root.MustKey("config")

	if configNode.MustKey("refundable_timestamp").MustString() != "1234567890" {
		t.Errorf("RefundableTimestamp mismatch in JSON. Expected 1234567890, got %s",
			configNode.MustKey("refundable_timestamp").MustString())
	}

	if configNode.MustKey("refund_to").MustString() != refundTo.String() {
		t.Errorf("RefundTo mismatch in JSON. Expected %s, got %s",
			refundTo.String(), configNode.MustKey("refund_to").MustString())
	}

	claimedBitmapNode := root.MustKey("claimed_bitmap")

	if claimedBitmapNode.MustKey("0").MustString() != "101" {
		t.Errorf("ClaimedBitmap[0] mismatch in JSON. Expected 5 (101), got %s",
			claimedBitmapNode.MustKey("0").MustString())
	}

	if claimedBitmapNode.MustKey("1").MustString() != "11010" {
		t.Errorf("ClaimedBitmap[1] mismatch in JSON. Expected 26 (11010), got %s",
			claimedBitmapNode.MustKey("1").MustString())
	}
}
