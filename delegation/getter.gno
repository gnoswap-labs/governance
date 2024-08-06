package delegation

import (
	"std"

	"gno.land/p/demo/grc/grc20"
	u256 "gno.land/p/demo/uint256"
)

// GetStaker returns the address of the entity staking the tokens.
func (dt *DelegatedToken) GetStaker() std.Address {
    return dt.staker
}

// GetToken returns the underlying GRC20 token being staked.
func (dt *DelegatedToken) GetToken() grc20.Token {
    return dt.token
}

// GetDelegatedTo returns the delegate address for the given owner address.
func (dt *DelegatedToken) GetDelegatedTo(owner std.Address) std.Address {
    return dt.delegatedTo[owner]
}

// GetBalance returns the delegated token balance for the given account.
func (dt *DelegatedToken) GetBalance(account std.Address) *u256.Uint {
    return dt.balances[account]
}

// GetAllowance returns the spending allowance for the given owner and spender.
func (dt *DelegatedToken) GetAllowance(owner, spender std.Address) *u256.Uint {
    if dt.allowances[owner] == nil {
        return u256.Zero()
    }
    return dt.allowances[owner][spender]
}

// GetTotalSupply returns the total amount of delegated tokens in circulation.
func (dt *DelegatedToken) GetTotalSupply() *u256.Uint {
    return dt.totalSupply
}

// GetName returns the name of the delegated token.
func (dt *DelegatedToken) GetName() string {
    return dt.name
}

// GetSymbol returns the symbol of the delegated token.
func (dt *DelegatedToken) GetSymbol() string {
    return dt.symbol
}

// GetDecimals returns the number of decimal places for the delegated token.
func (dt *DelegatedToken) GetDecimals() uint8 {
    return dt.decimals
}
