package delegation

import (
	"std"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/ufmt"
	u256 "gno.land/p/demo/uint256"
)

type IDelegatedToken interface {
	GetStaker() std.Address
	GetDelegatedTo(owner std.Address) std.Address
	Delegate(owner, to std.Address)
	Deposit()
	DepositAmount(amount *u256.Uint)
	// Withdraw()
	// WithdrawAmount(amount *u256.Uint)
}

type DelegatedToken struct {
	staker      std.Address
	token       grc20.Token
	delegatedTo map[std.Address]std.Address
	balances    map[std.Address]*u256.Uint
	allowances  map[std.Address]map[std.Address]*u256.Uint
	totalSupply *u256.Uint
	name        string
	symbol      string
}

var gDelegatedToken *DelegatedToken

// Init initializes the DelegatedToken contract
func Init(staker std.Address, token grc20.Token, name string, symbol string) {
	gDelegatedToken = &DelegatedToken{
		staker: 	staker,
		token:      token,
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

func mintDelegatedTokens(to std.Address, amount *u256.Uint) {
	if gDelegatedToken.balances[to] == nil {
		gDelegatedToken.balances[to] = u256.Zero()
	}
	gDelegatedToken.balances[to].Add(gDelegatedToken.balances[to], amount)
	gDelegatedToken.totalSupply.Add(gDelegatedToken.totalSupply, amount)
}

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