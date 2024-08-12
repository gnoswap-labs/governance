package staker

import (
	"std"
	"strconv"
	"strings"

	"gno.land/p/demo/grc/grc20"
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
	result := make(map[string]string)
	for addr, amount := range gStaker.delegations {
		result[addr.String()] = amount.ToString()
	}
	return marshalDelegationsJSON(result)
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

	return marshalDelegationHistory(relavantHistory)
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

	recentHistroy := history[startIndex:]

	return marshalDelegationHistory(recentHistroy)
}


// region marshalers

func marshalDelegationsJSON(m map[string]string) string {
	var builder strings.Builder
	builder.WriteString("[")
	
	first := true
	for k, v := range m {
		if !first {
			builder.WriteString(",")
		}
		first = false
		builder.WriteString("{")
		builder.WriteString("\"")
		builder.WriteString("address")
		builder.WriteString("\":\"")
		builder.WriteString(escapeJSONString(k))
		builder.WriteString("\",\"")
		builder.WriteString("amount")
		builder.WriteString("\":\"")
		builder.WriteString(escapeJSONString(v))
		builder.WriteString("\"")
		builder.WriteString("}")
	}
	
	builder.WriteString("]")
	return builder.String()
}

func marshalDelegationHistory(history []DelegationHistory) string {
	var builder strings.Builder
	builder.WriteString("[")

	for i, entry := range history {
		if i > 0 {
			builder.WriteString(",")
		}
		builder.WriteString("{")
		builder.WriteString("\"timestamp\":")
		builder.WriteString(strconv.FormatUint(entry.timestamp, 10))
		builder.WriteString(",\"amount\":\"")
		builder.WriteString(entry.amount.ToString())
		builder.WriteString("\"}")
	}

	builder.WriteString("]")
	return builder.String()
}

// escapeJSONString escapes special characters in a string for JSON encoding
func escapeJSONString(s string) string {
	var builder strings.Builder
	for _, r := range s {
		switch r {
		case '"':
			builder.WriteString("\\\"")
		case '\\':
			builder.WriteString("\\\\")
		case '\b':
			builder.WriteString("\\b")
		case '\f':
			builder.WriteString("\\f")
		case '\n':
			builder.WriteString("\\n")
		case '\r':
			builder.WriteString("\\r")
		case '\t':
			builder.WriteString("\\t")
		default:
			builder.WriteRune(r)
		}
	}
	return builder.String()
}
