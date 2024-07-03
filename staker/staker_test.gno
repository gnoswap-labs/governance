package staker

import (
	"errors"
	"std"
	"testing"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/ufmt"
	"gno.land/p/demo/uint256"
)

// mockGRC20 is a mock implementation of the IGRC20 interface for testing
type mockGRC20 struct {
	balances    map[std.Address]uint64
	allowances  map[std.Address]map[std.Address]uint64
	totalSupply uint64
	name        string
	symbol      string
	decimals    uint8
}

// newMockGRC20 creates a new instance of mockGRC20
func newMockGRC20(name, symbol string, decimals uint8) *mockGRC20 {
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
    if m.balances[from] < amount {
        return ErrInsufficientBalance
    }
    m.balances[from] -= amount
    m.balances[to] += amount
    return nil
}

///////////////////////////////////////////////////////////////////////////////////////

func TestNewStaker(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 42)
	s := New(token)

	if s.token != token {
		t.Error("token not set correctly")
	}

	if s.totalStaked.Cmp(uint256.NewUint(0)) != 0 {
		t.Error("totalStaked not set correctly. expected 0")
	}

	if len(s.delegations) != 0 {
		t.Error("delegations not set correctly. expected empty map.")
	}

	if len(s.delegationHistory) != 0 {
		t.Error("delegationHistory not set correctly. expected empty map.")
	}
}

func TestStakeAmount(t *testing.T) {
	token := newMockGRC20("Test Token", "TST", 42)
	s := New(token)

	delegate := std.Address("delegate")
	amount := uint256.NewUint(100)

	// Set up some balance for the caller
	caller := std.GetOrigCaller()
	token.balances[caller] = 1000

	err := s.StakeAmount(delegate, amount)
	if err != nil {
		t.Errorf("StakeAmount returned an unexpected error: %v", err)
	}

	if amount.Uint64() != 100 {
		t.Errorf("StakeAmount did not update delegations correctly")
	}

	if s.totalStaked.Uint64() != 100 {
		t.Errorf("StakeAmount did not update totalStaked correctly")
	}

	if len(s.delegationHistory[delegate]) != 1 {
		t.Errorf("StakeAmount did not add to delegationHistory")
	}
}
