package airdrop

import (
	"std"
	"strconv"
	"strings"

	"gno.land/p/demo/grc/grc20"
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
func GetAirdropConfig(jsonStr string) string {
	airdrop := createAirdropFromJSON(jsonStr)

	node := json.ObjectNode("", nil)

	timestamp := strconv.FormatUint(airdrop.config.RefundableTimestamp, 10)
	err := node.AppendObject("refundable_timestamp", json.StringNode("refundable_timestamp", timestamp))
	if err != nil {
		panic(err)
	}

	err = node.AppendObject("refund_to", json.StringNode("refund_to", airdrop.config.RefundTo.String()))
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
func GetTotalClaims(jsonStr string) string {
	airdrop := createAirdropFromJSON(jsonStr)

	totalClaims := 0
	for _, bitmap := range airdrop.claimedBitmap {
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
//
// GetRemainingBalance returns the remaining balance of tokens available for airdrop.
func GetRemainingBalance(jsonStr string) string {
	airdrop := createAirdropFromJSON(jsonStr)

	balance := airdropToken.BalanceOf(airdrop.address)

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
func GetClaimStatus(jsonStr string, claimID uint64) string {
	airdrop := createAirdropFromJSON(jsonStr)

	claimed := airdrop.IsClaimed(claimID)

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

// AirdropToJSON converts an Airdrop struct to a JSON string.
func AirdropToJSON(a *Airdrop) string {
	node := json.ObjectNode("", nil)

	configNode := json.ObjectNode("config", nil)
	err := configNode.AppendObject("refundable_timestamp", json.StringNode("refundable_timestamp", strconv.FormatUint(a.config.RefundableTimestamp, 10)))
	if err != nil {
		panic(err)
	}
	err = configNode.AppendObject("refund_to", json.StringNode("refund_to", a.config.RefundTo.String()))
	if err != nil {
		panic(err)
	}

	err = node.AppendObject("config", configNode)
	if err != nil {
		panic(err)
	}

	err = node.AppendObject("address", json.StringNode("address", a.address.String()))
	if err != nil {
		panic(err)
	}

	claimedBitmapNode := json.ObjectNode("claimed_bitmap", nil)
	for i, bitmap := range a.claimedBitmap {
		err = claimedBitmapNode.AppendObject(strconv.FormatUint(i, 10), json.StringNode(strconv.FormatUint(i, 10), strconv.FormatUint(bitmap, 2)))
		if err != nil {
			panic(err)
		}
	}

	err = node.AppendObject("claimed_bitmap", claimedBitmapNode)
	if err != nil {
		panic(err)
	}

	return marshal(node)
}

// createAirdropFromJSON creates an Airdrop struct from a JSON string.
func createAirdropFromJSON(jsonStr string) *Airdrop {
	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		panic(ufmt.Sprintf("failed to unmarshal JSON: %v", err))
	}

	configNode := node.MustKey("config")

	timestamp := configNode.MustKey("refundable_timestamp").MustString()
	refundableTimestamp, err := parseUint(timestamp, 10, 64)
	if err != nil {
		panic(err)
	}

	refundToAddr := configNode.MustKey("refund_to").MustString()
	refundTo := std.Address(refundToAddr)

	address := std.Address(node.MustKey("address").MustString())

	claimedBitmapNode := node.MustKey("claimed_bitmap")
	claimedBitmap := make(map[uint64]uint64)

	claimedBitmapNode.ObjectEach(func(key string, value *json.Node) {
		index, err := parseUint(key, 10, 64)
		if err != nil {
			panic(err)
		}
		bitmap, err := parseUint(value.MustString(), 2, 64)
		if err != nil {
			panic(err)
		}
		claimedBitmap[index] = bitmap
	})

	return &Airdrop{
		config: Config{
			RefundableTimestamp: refundableTimestamp,
			RefundTo:            refundTo,
		},
		address:       address,
		claimedBitmap: claimedBitmap,
	}
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
