package tokendelegate

import (
	"std"

	"gno.land/p/demo/avl"
	"gno.land/p/demo/grc/grc20"
	u256 "gno.land/p/demo/uint256"
)

// IDelegatedToken defines the interface for a delegated token.
type IDelegatedToken interface {
	GetStaker() std.Address
	GetDelegatedTo(owner std.Address) std.Address
	Delegate(owner, to std.Address)
	Deposit()
	DepositAmount(amount *u256.Uint)
	Withdraw(amount, caller string)
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
	allowances  *avl.Tree
	// allowances  map[std.Address]map[std.Address]*u256.Uint

	// totoalSupply represents the total amount of delegated tokens in circulation.
	totalSupply *u256.Uint

	// name is the name of the delegated token.
	name        string

	// symbol is the symbol of the delegated token.
	symbol      string

	// decimals is the number of decimal places for the delegated token.
	decimals   uint8

	// contractAddr is the address of this delegated token contract.
    // It's used to ensure correct functionality when called from different realms.
	contractAddr std.Address
}

var gDelegatedToken *DelegatedToken

// New creates a new instance of the DelegatedToken.
func New(staker std.Address, token grc20.Token, name string, symbol string, contractAddr std.Address) {
	gDelegatedToken = &DelegatedToken{
		staker:      staker,
		token:       token,
		delegatedTo: make(map[std.Address]std.Address),
		balances:    make(map[std.Address]*u256.Uint),
		allowances:  avl.NewTree(),
		totalSupply: u256.Zero(),
		name:        name,
		symbol:      symbol,
		contractAddr: contractAddr,
	}
}

func Delegate(owner, to string) {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	ownerAddr := std.Address(owner)
	toAddr := std.Address(to)

	currDelegatee := GetDelegatedTo(owner)
	delegateeAddr := std.Address(currDelegatee)

	// if the new delegation is different from the current one
	if delegateeAddr != toAddr {
		gDelegatedToken.delegatedTo[ownerAddr] = toAddr

		std.Emit(
			"Delegation",
			"from", owner,
			"to", to,
		)
	}
}

// Deposit transfers the approved amount of the staked token to this contract
// and mints an GRC20 representing the staked amount.
func Deposit(amount, caller string) {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	callerAddr := std.Address(caller)
	token := gDelegatedToken.token
	contractAddr := gDelegatedToken.contractAddr

	amountUint, err := u256.FromDecimal(amount)
	if err != nil {
		panic("invalid amount: " + err.Error())
	}

	// check balance
	balance := token.BalanceOf(callerAddr)
	if u256.NewUint(balance).Cmp(amountUint) < 0 {
		panic("insufficient balance")
	}

	// check allowance
	allowance := token.Allowance(callerAddr, contractAddr)
	if u256.NewUint(allowance).Cmp(amountUint) < 0 {
		panic("insufficient allowance")
	}

	// transfer tokens from caller to this contract
	err = token.TransferFrom(callerAddr, contractAddr, amountUint.Uint64())
	if err != nil {
		panic("transfer failed: " + err.Error())
	}

	// mint equivalent amount of delegated tokens
	mintDelegatedTokens(caller, amount)

	std.Emit(
		"DepositAmount",
		"from", caller,
		"amount", amount,
	)
}

// Withdraw withdraws the entire staked balance from the contract for the caller
func Withdraw(amount, caller string) {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	callerAddr := std.Address(caller)
	balance := BalanceOf(caller)

	if balance.IsZero() {
		panic("no balance to withdraw")
	}

	amountUint, err := u256.FromDecimal(amount)
	if err != nil {
		panic("invalid amount: " + err.Error())
	}

	if amountUint.Gt(balance) {
		panic("insufficient balance to withdraw")
	}

	// burn the specified amount of delegated tokens
	newBalance := u256.Zero().Sub(balance, amountUint)
	gDelegatedToken.balances[callerAddr] = newBalance
	gDelegatedToken.totalSupply = u256.Zero().Sub(gDelegatedToken.totalSupply, amountUint)

	// transfer the original tokens back to the caller
	token := gDelegatedToken.token
	err = token.Transfer(callerAddr, amountUint.Uint64())
	if err != nil {
		panic("transfer failed: " + err.Error())
	}

	std.Emit(
		"Withdrawal",
		"from", caller,
		"amount", amount,
	)
}

// mintDelegatedTokens mints the specified amount of delegated tokens for the given account (address).
func mintDelegatedTokens(to, amount string) {
	toAddr := std.Address(to)
	if gDelegatedToken.balances[toAddr] == nil {
		gDelegatedToken.balances[toAddr] = u256.Zero()
	}

	amountUint, err := u256.FromDecimal(amount)
	if err != nil {
		panic("invalid amount: " + err.Error())
	}
	gDelegatedToken.balances[toAddr].Add(gDelegatedToken.balances[toAddr], amountUint)
	gDelegatedToken.totalSupply.Add(gDelegatedToken.totalSupply, amountUint)
}

// BalanceOf returns the balance of delegated tokens for the given account.
func BalanceOf(account string) *u256.Uint {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	accountAddr := std.Address(account)
	balance, exists := gDelegatedToken.balances[accountAddr]
	if !exists {
		return u256.Zero()
	}

	return balance
}

// SetAllowance sets the spending allowance for a spender.
func SetAllowance(owner, spender std.Address, amount *u256.Uint) {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	key := owner.String() + ":" + spender.String()
	gDelegatedToken.allowances.Set(key, amount)
}
