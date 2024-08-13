package airdrop

import (
	"std"
	"strings"

	"gno.land/p/demo/json"
	"gno.land/p/demo/ufmt"
	"gno.land/p/demo/uint256"
)

// GetAirdropConfig returns the current configuration of the airdrop as a JSON string.
//
// Example:
// {
//   "refundable_timestamp": "1234567890",
//   "refund_to": "g1234567890abcdefghijklmnop"
// }
func (a *Airdrop) GetAirdropConfig() string {
	node := json.ObjectNode("", nil)

	err := node.AppendObject("refundable_timestamp", json.StringNode("refundable_timestamp", ufmt.Sprintf("%d", a.config.RefundableTimestamp)))
	if err != nil {
		panic(err)
	}

	err = node.AppendObject("refund_to", json.StringNode("refund_to", a.config.RefundTo.String()))
	if err != nil {
		panic(err)
	}

	b, err := json.Marshal(node)
	if err != nil {
		panic(err)
	}

	return string(b)
}

// GetTotalClaims returns the total number of claims made so far as a JSON string.
//
// Example:
// {
//   "total_claims": "16"
// }
func (a *Airdrop) GetTotalClaims() string {
	totalClaims := 0
	for _, bitmap := range a.claimedBitmap {
		totalClaims += popCount(bitmap)
	}

	node := json.ObjectNode("", nil)

	err := node.AppendObject("total_claims", json.StringNode("total_claims", ufmt.Sprintf("%d", totalClaims)))
	if err != nil {
		panic(err)
	}

	b, err := json.Marshal(node)
	if err != nil {
		panic(err)
	}

	return string(b)
}

func (a *Airdrop) GetRemainingBalance() string {
	balance := a.token.BalanceOf(a.address)
	
	node := json.ObjectNode("", nil)

	err := node.AppendObject("remaining_balance", json.StringNode("remaining_balance", uint256.NewUint(balance).ToString()))
	if err != nil {
		panic(err)
	}

	b, err := json.Marshal(node)
	if err != nil {
		panic(err)
	}

	return string(b)
}

func (a *Airdrop) GetClaimStatus(claimID uint64) string {
	claimed := a.IsClaimed(claimID)

	node := json.ObjectNode("", nil)

	err := node.AppendObject("claim_id", json.StringNode("claim_id", ufmt.Sprintf("%d", claimID)))
	if err != nil {
		panic(err)
	}
	err = node.AppendObject("claimed", json.StringNode("claimed", ufmt.Sprintf("%t", claimed)))
	if err != nil {
		panic(err)
	}

	b, err := json.Marshal(node)
	if err != nil {
		panic(err)
	}

	return string(b)
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