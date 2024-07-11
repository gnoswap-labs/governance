package delegation

import (
	"std"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/ufmt"
	u256 "gno.land/p/demo/uint256"
)

// IDelegatedToken defines the interface for a delegated token.
type IDelegatedToken interface {
	GetStaker() std.Address
	GetDelegatedTo(owner std.Address) std.Address
	Delegate(owner, to std.Address)
	Deposit()
	DepositAmount(amount *u256.Uint)
	Withdraw()
	WithdrawAmount(amount *u256.Uint)
}

// DelegatedToken represents a token that can be delegated to another address.
type DelegatedToken struct {
	// staker is the address of the entity staking the tokens.
	staker      std.Address

	// token is the unerlying GRC20 token being staked.
	token       grc20.Token

	// delegatedTo maps owner address to their delegate address.
	delegatedTo map[std.Address]std.Address

	// balances keeps track of the delegated token balances for each account.
	balances    map[std.Address]*u256.Uint

	// allowances tracks the spending allowances for delegated tokens.
	allowances  map[std.Address]map[std.Address]*u256.Uint

	// totoalSupply represents the total amount of delegated tokens in circulation.
	totalSupply *u256.Uint

	// name is the name of the delegated token.
	name        string

	// symbol is the symbol of the delegated token.
	symbol      string
}

var gDelegatedToken *DelegatedToken

// Init initializes the DelegatedToken contract
func Init(staker std.Address, token grc20.Token, name string, symbol string) {
	gDelegatedToken = &DelegatedToken{
		staker:      staker,
		token:       token,
		delegatedTo: make(map[std.Address]std.Address),
		balances:    make(map[std.Address]*u256.Uint),
		totalSupply: u256.Zero(),
		name:        name,
		symbol:      symbol,
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

		// TODO: move delegates ?

		std.Emit(
			"Delegation",
			"from", owner.String(),
			"to", to.String(),
		)
	}
}

// Deposit transfers the approved amount of the staked token to this contract
// and mints an GRC20 representing the staked amount.
func Deposit() {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	caller := std.GetOrigCaller()
	token := gDelegatedToken.token

	// get the approved amount
	allowance := token.Allowance(caller, std.GetOrigPkgAddr())
	if allowance == 0 {
		panic("no allowance")
	}

	err := token.TransferFrom(caller, std.GetOrigPkgAddr(), allowance)
	if err != nil {
		panic("transfer failed: " + err.Error())
	}

	// mint equivalent amount of delegated tokens
	amount := u256.NewUint(allowance)
	mintDelegatedTokens(caller, amount)

	std.Emit(
		"Deposit",
		"from", caller.String(),
		"amount", amount.ToString(),
	)
}

// DepositAmount deposites a specific amount of tokens
func DepositAmount(amount *u256.Uint) {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	caller := std.GetOrigCaller()
	token := gDelegatedToken.token

	// check allowance
	allowance := token.Allowance(caller, std.GetOrigPkgAddr())
	if u256.NewUint(allowance).Cmp(amount) < 0 {
		panic("insufficient allowance")
	}

	// transfer tokens from caller to this contract
	err := token.TransferFrom(caller, std.GetOrigPkgAddr(), amount.Uint64())
	if err != nil {
		panic("transfer failed: " + err.Error())
	}

	// mint equivalent amount of delegated tokens
	mintDelegatedTokens(caller, amount)

	std.Emit(
		"DepositAmount",
		"from", caller.String(),
		"amount", amount.ToString(),
	)
}

// Withdraw withdraws the entire staked balance from the contract for the caller
func Withdraw() {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	caller := std.GetOrigCaller()
	balance := BalanceOf(caller)

	if balance.IsZero() {
		panic("no balance to withdraw")
	}

	// burn the delegated tokens
	gDelegatedToken.balances[caller] = u256.Zero()
	gDelegatedToken.totalSupply = u256.Zero().Sub(gDelegatedToken.totalSupply, balance)

	// transfer the original tokens back to the caller
	token := gDelegatedToken.token
	err := token.Transfer(caller, balance.Uint64())
	if err != nil {
		panic("transfer failed: " + err.Error())
	}

	std.Emit(
		"Withdrawal",
		"from", caller.String(),
		"amount", balance.ToString(),
	)
}

// WithdrawAmount withdraws specified amount of token
// from the contract for the caller
func WithdrawAmount(amount *u256.Uint) {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	caller := std.GetOrigCaller()
	balance := BalanceOf(caller)

	if balance.Cmp(amount) < 0 {
		panic("insufficient balance to withdraw")
	}

	// Burn the delegated tokens
	gDelegatedToken.balances[caller] = u256.Zero().Sub(balance, amount)
	gDelegatedToken.totalSupply = u256.Zero().Sub(gDelegatedToken.totalSupply, amount)

	// transfer the original token back to the caller
	token := gDelegatedToken.token
	err := token.Transfer(caller, amount.Uint64())
	if err != nil {
		panic("transfer failed: " + err.Error())
	}

	std.Emit(
		"WithdrawAmount",
		"from", caller.String(),
		"amount", amount.ToString(),
	)
}

// mintDelegatedTokens mints the specified amount of delegated tokens for the given account (address).
func mintDelegatedTokens(to std.Address, amount *u256.Uint) {
	if gDelegatedToken.balances[to] == nil {
		gDelegatedToken.balances[to] = u256.Zero()
	}
	gDelegatedToken.balances[to].Add(gDelegatedToken.balances[to], amount)
	gDelegatedToken.totalSupply.Add(gDelegatedToken.totalSupply, amount)
}

// BalanceOf returns the balance of delegated tokens for the given account.
func BalanceOf(account std.Address) *u256.Uint {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	balance, exists := gDelegatedToken.balances[account]
	if !exists {
		return u256.Zero()
	}

	return balance
}
