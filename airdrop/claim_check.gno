package airdrop

import (
	"gno.land/p/demo/grc/grc20"
	u256 "gno.land/p/demo/uint256"
)

// CheckParams representes the parameters for the checking a claim
type CheckParams struct {
	Airdrop *Airdrop
	ClaimID uint64
	Amount  *u256.Uint
}

// CheckResult represents the result of checking a claim
type CheckResult struct {
	Claimed bool
	Funded  bool
}

type IAirdropClaimCheck interface {
	Check(claims []CheckParams) []CheckResult
}

type AirdropClaimCheck struct{}

// NewAirdropClaimCheck creates a new instance of AirdropClaimCheck
func NewAirdropClaimCheck() *AirdropClaimCheck {
	return &AirdropClaimCheck{}
}

func (acc *AirdropClaimCheck) Check(claims []CheckParams) []CheckResult {
	results := make([]CheckResult, 0, len(claims))

	for _, claim := range claims {
		claimed := claim.Airdrop.IsClaimed(claim.ClaimID)

		// get the token balance of the airdrop contract
		airdeopAddr := claim.Airdrop.GetAddress()
		balance := claim.Airdrop.token.BalanceOf(airdeopAddr)

		funded := u256.NewUint(balance).Cmp(claim.Amount) >= 0

		results = append(results, CheckResult{
			Claimed: claimed,
			Funded:  funded,
		})
	}

	return results
}
