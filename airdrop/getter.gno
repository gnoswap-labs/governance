package airdrop

import (
	"std"
	"strconv"
	"strings"

	"gno.land/p/demo/json"
	"gno.land/p/demo/ufmt"
	"gno.land/p/demo/uint256"
)

// GetAirdropConfig returns the current configuration of the airdrop as a JSON string.
//
// Example:
//
//	{
//	  "refundable_timestamp": "1234567890",
//	  "refund_to": "g1234567890abcdefghijklmnop"
//	}
func (a *Airdrop) GetAirdropConfig() string {
	node := json.ObjectNode("", nil)

	timestamp := strconv.FormatUint(a.config.RefundableTimestamp, 10)
	err := node.AppendObject("refundable_timestamp", json.StringNode("refundable_timestamp", timestamp))
	if err != nil {
		panic(err)
	}

	err = node.AppendObject("refund_to", json.StringNode("refund_to", a.config.RefundTo.String()))
	if err != nil {
		panic(err)
	}

	return marshal(node)
}

// GetTotalClaims returns the total number of claims made so far as a JSON string.
//
// Example:
//
//	{
//	  "total_claims": "16"
//	}
func (a *Airdrop) GetTotalClaims() string {
	totalClaims := 0
	for _, bitmap := range a.claimedBitmap {
		totalClaims += popCount(bitmap)
	}

	node := json.ObjectNode("", nil)

	claims := strconv.Itoa(totalClaims)
	err := node.AppendObject("total_claims", json.StringNode("total_claims", claims))
	if err != nil {
		panic(err)
	}

	return marshal(node)
}

// GetRemainingBalance returns the remaining balance of tokens available for airdrop.
//
// Example:
//
//	{
//	  "remaining_balance": "1000000"
//	}
func (a *Airdrop) GetRemainingBalance() string {
	balance := a.token.BalanceOf(a.address)

	node := json.ObjectNode("", nil)

	balanceStr := uint256.NewUint(balance).ToString()
	err := node.AppendObject("remaining_balance", json.StringNode("remaining_balance", balanceStr))
	if err != nil {
		panic(err)
	}

	return marshal(node)
}

// GetClaimStatus returns the status for a given claim ID.
//
// Example:
//
//	{
//	  "claim_id": "123",
//	  "claimed": true
//	}
func (a *Airdrop) GetClaimStatus(claimID uint64) string {
	claimed := a.IsClaimed(claimID)

	node := json.ObjectNode("", nil)

	id := strconv.FormatUint(claimID, 10)
	err := node.AppendObject("claim_id", json.StringNode("claim_id", id))
	if err != nil {
		panic(err)
	}
	err = node.AppendObject("claimed", json.BoolNode("claimed", claimed))
	if err != nil {
		panic(err)
	}

	return marshal(node)
}

// popCount returns the number of set bits in a uint64
func popCount(x uint64) int {
	count := 0
	for x != 0 {
		count++
		x &= x - 1
	}
	return count
}

func marshal(node *json.Node) string {
	b, err := json.Marshal(node)
	if err != nil {
		panic(ufmt.Sprintf("failed to marshal JSON: %v", err))
	}
	return string(b)
}
