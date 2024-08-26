package tokendelegate

import (
	"std"

	"gno.land/p/demo/grc/grc20"
	u256 "gno.land/p/demo/uint256"
    "gno.land/p/demo/ufmt"
)

// GetStaker returns the addrress of the staker that this delegated token wrapper uses.
func GetStaker() string {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}
	return gDelegatedToken.staker.String()
}

// GetDelegatedTo returns the address to whom the owner is delegated.
func GetDelegatedTo(owner string) string {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	ownerAddr := std.Address(owner)
	delegatee, exists := gDelegatedToken.delegatedTo[ownerAddr]
	if !exists {
		// if not explicitly delegated, return owner
		return ownerAddr.String()
	}

	return delegatee.String()
}

// GetToken returns the underlying GRC20 token being staked.
func GetToken() grc20.Token {
    if gDelegatedToken == nil {
        panic("DelegatedToken not initialized")
    }
    return gDelegatedToken.token
}

// GetBalance returns the delegated token balance for the given account.
func GetBalance(account string) string {
    if gDelegatedToken == nil {
        panic("DelegatedToken not initialized")
    }

    accountAddr := std.Address(account)
    if !accountAddr.IsValid() {
        panic(ufmt.Sprintf("invalid account address: %s", account))
    }
    balance, exists := gDelegatedToken.balances[accountAddr]
    if !exists {
        return "0"
    }

    return balance.ToString()
}

// GetAllowance returns the spending allowance for the given owner and spender.
func GetAllowance(owner, spender string) string {
	if gDelegatedToken == nil {
		panic("DelegatedToken not initialized")
	}

	key := owner + ":" + spender
	allowance, exists := gDelegatedToken.allowances.Get(key)
	if !exists {
		return "0"
	}

	res := allowance.(*u256.Uint)
    return res.ToString()
}

// GetTotalSupply returns the total amount of delegated tokens in circulation.
func GetTotalSupply() string {
    if gDelegatedToken == nil {
        panic("DelegatedToken not initialized")
    }
    return gDelegatedToken.totalSupply.ToString()
}

// GetName returns the name of the delegated token.
func GetName() string {
    if gDelegatedToken == nil {
        panic("DelegatedToken not initialized")
    }
    return gDelegatedToken.name
}

// GetSymbol returns the symbol of the delegated token.
func GetSymbol() string {
    if gDelegatedToken == nil {
        panic("DelegatedToken not initialized")
    }
    return gDelegatedToken.symbol
}

// GetDecimals returns the number of decimal places for the delegated token.
func GetDecimals() uint8 {
    if gDelegatedToken == nil {
        panic("DelegatedToken not initialized")
    }
    return gDelegatedToken.decimals
}
