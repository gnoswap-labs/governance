package delegation

import (
	"std"

	"gno.land/p/demo/ufmt"
	u256 "gno.land/p/demo/uint256"
)

type IDelegatedToken interface {
	GetStaker() std.Address
	GetDelegatedTo(owner std.Address) std.Address
	Delegate(owner, to std.Address)
	// Deposit()
	// DepositAmount(amount *u256.Uint)
	// Withdraw()
	// WithdrawAmount(amount *u256.Uint)
}

type DelegatedToken struct {
	staker      std.Address
	delegatedTo map[std.Address]std.Address
	balances    map[std.Address]*u256.Uint
	allowances  map[std.Address]map[std.Address]*u256.Uint
	totalSupply *u256.Uint
	name        string
	symbol      string
}

var gDelegatedToken *DelegatedToken

// Init initializes the DelegatedToken contract
func Init(staker std.Address, name string, symbol string) {
	gDelegatedToken = &DelegatedToken{
		staker: 	staker,
		delegatedTo: make(map[std.Address]std.Address),
		balances:   make(map[std.Address]*u256.Uint),
		totalSupply: u256.Zero(),
		name: 	 name,
		symbol: symbol,
	}
}

// GetStaker returns the addrress of the staker that this delegated token wrapper uses.
func GetStaker() std.Address {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}
	return gDelegatedToken.staker
}

// GetDelegatedTo returns the address to whom the owner is delegated.
func GetDelegatedTo(owner std.Address) std.Address {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	delegatee, exists := gDelegatedToken.delegatedTo[owner]
	if !exists {
		// if not explicitly delegated, return owner
		return owner
	}

	return delegatee
}

func Delegate(owner, to std.Address) {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	currDelegatee := GetDelegatedTo(owner)

	// if the new delegation is different from the current one
	if currDelegatee != to {
		gDelegatedToken.delegatedTo[owner] = to

		// TODO: move delegates

		std.Emit(
			"Delegation",
			"from", owner.String(),
			"to", to.String(),
		)
	}
}