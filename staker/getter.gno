package staker

import (
	"std"
	"strconv"
	"strings"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/json"
	u256 "gno.land/p/demo/uint256"
	"gno.land/p/demo/ufmt"
)

// region getters

// GetTotalStaked returns the total aount of tokens staked in the contract.
func GetTotalStaked() string {
	return gStaker.totalStaked.ToString()
}

// GetDelegationAmount returns the amount of tokens delegated to a given address.
func GetDelegationAmount(delegate string) string {
	delegateAddr := std.Address(delegate)
	if !delegateAddr.IsValid() {
		panic(ufmt.Sprintf("invalid address: %s", delegate))
	}

	amount, exists := gStaker.delegations[delegateAddr]
	if !exists {
		return "0"
	}

	return amount.ToString()
}

// GetAllDelegations returns a JSON string of all delegations,
// with addresses as keys and amounts as values.
func GetAllDelegations() string {
	delegationsArray := json.ArrayNode("", nil)

	for addr, amount := range gStaker.delegations {
		delegationObj := json.ObjectNode("", nil)
		err := delegationObj.AppendObject("address", json.StringNode("address", addr.String()))
		if err != nil {
			panic(ufmt.Sprintf("Error appending address to JSON object: %v", err))
		}
		err = delegationObj.AppendObject("amount", json.StringNode("amount", amount.ToString()))
		if err != nil {
			panic(ufmt.Sprintf("Error appending amount to JSON object: %v", err))
		}
		delegationsArray.AppendArray(delegationObj)
	}

	b, err := json.Marshal(delegationsArray)
	if err != nil {
		panic(ufmt.Sprintf("JSON marshal error: %v", err))
	}

	return string(b)
}

// GetDelegationHistoryCount returns the number of historical delegation events for a given address.
func GetDelegationHistoryCount(delegate string) int {
	delegateAddr := std.Address(delegate)
	if !delegateAddr.IsValid() {
		panic(ufmt.Sprintf("invalid address: %s", delegate))
	}

	history, exists := gStaker.delegationHistory[delegateAddr]
	if !exists {
		return 0
	}

	return len(history)
}

// GetDelegationHistroy returns a JSN string of delegation history for a given address
// within the specified time range.
func GetDelegationHistory(delegate string, startTime, endTime uint64) string {
	delegateAddr := std.Address(delegate)
	if !delegateAddr.IsValid() {
		panic(ufmt.Sprintf("invalid address: %s", delegate))
	}

	history, exists := gStaker.delegationHistory[delegateAddr]
	if !exists {
		return "[]"
	}

	var relavantHistory []DelegationHistory
	for _, entry := range history {
		if entry.timestamp >= startTime && entry.timestamp <= endTime {
			relavantHistory = append(relavantHistory, entry)
		}
	}

	historyNodes := make([]*json.Node, len(relavantHistory))
	for i, entry := range relavantHistory {
		historyNodes[i] = json.ObjectNode("", map[string]*json.Node{
			"timestamp": json.NumberNode("timestamp", float64(entry.timestamp)),
			"amount":    json.StringNode("amount", entry.amount.ToString()),
		})
	}

	node := json.ArrayNode("", historyNodes...)

	b, err := json.Marshal(node)
	if err != nil {
		panic(err)
	}

	return string(b)
}

func GetRecentDelegationHistory(delegate string, n int) string {
	delegateAddr := std.Address(delegate)
	if !delegateAddr.IsValid() {
		panic(ufmt.Sprintf("invalid address: %s", delegate))
	}

	history, exists := gStaker.delegationHistory[delegateAddr]
	if !exists || len(history) == 0 {
		return "[]"
	}

	// determine the starting index for recent history
	startIndex := len(history) - n
	if startIndex < 0 {
		startIndex = 0
	} else if startIndex > len(history) {
		startIndex = len(history)
	}

	recentHistory := history[startIndex:]

	historyNodes := make([]*json.Node, len(recentHistory))
	for i, entry := range recentHistory {
		historyNodes[i] = json.ObjectNode("", map[string]*json.Node{
			"timestamp": json.NumberNode("timestamp", float64(entry.timestamp)),
			"amount":    json.StringNode("amount", entry.amount.ToString()),
		})
	}

	node := json.ArrayNode("", historyNodes...)

	b, err := json.Marshal(node)
	if err != nil {
		panic(err)
	}

	return string(b)
}
