package airdrop

import (
	"errors"
	"std"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/uint256"
)

var (
	ErrInvalidClaimsCount = errors.New("INVALID_CLAIMS_COUNT")
	ErrFirstClaimIsNot64  = errors.New("FIRST_CLAIM_MUST_BE_MULT_64")
)

// Claim represents a single airdrop claim
type Claim struct {
	ID      uint64
	Claimee std.Address
	Amount  *uint256.Uint
}

// Config represents the airdrop configuration
type Config struct {
	RefundableTimestamp uint64
	RefundTo            std.Address
}

// Airdrop represents the airdrop contract
type Airdrop struct {
	token         grc20.IGRC20
	config        Config
	claimedBitmap map[uint64]uint64
}

// NewAirdrop creates a new Airdrop instance
func NewAirdrop(token grc20.IGRC20, config Config) *Airdrop {
	return &Airdrop{
		token:         token,
		config:        config,
		claimedBitmap: make(map[uint64]uint64),
	}
}

// claimIDToBitmapIndex converts a claim ID to bitmap index
func (a *Airdrop) claimIDToBitmapIndex(claimID uint64) (word uint64, index uint64) {
	word = claimID / 64
	index = claimID % 64
	return
}

// IsClaimed checks if a claim has been made
func (a *Airdrop) IsClaimed(claimID uint64) bool {
	word, index := a.claimIDToBitmapIndex(claimID)
	bitmap, exists := a.claimedBitmap[word]
	if !exists {
		return false
	}
	return (bitmap & (1 << index)) != 0
}

// Claim processes a single claim
func (a *Airdrop) Claim(claim Claim) (bool, error) {
	word, index := a.claimIDToBitmapIndex(claim.ID)
	bitmap := a.claimedBitmap[word]
	mask := uint64(1) << index
	alreadyClaimed := bitmap&mask != 0

	if alreadyClaimed {
		return false, nil
	}

	// check if the airdrop contract has enough balance to transfer
	airdropBalance, err := a.token.BalanceOf(std.GetOrigCaller())
	if err != nil {
		return false, err
	}
	if airdropBalance < claim.Amount.Uint64() {
		return false, nil
	}

	err = a.token.Transfer(claim.Claimee, claim.Amount.Uint64())
	if err != nil {
		return false, err
	}

	// Update the bitmap
	a.claimedBitmap[word] = bitmap | mask

	return true, nil
}

// Claim64 processes up to 64 claims in a single batch
func (a *Airdrop) Claim64(claims []Claim) (uint8, error) {
	if len(claims) == 0 || len(claims) > 64 {
		return 0, ErrInvalidClaimsCount
	}

	if claims[0].ID%64 != 0 {
		return 0, ErrFirstClaimIsNot64
	}

	word := claims[0].ID / 64
	bitmap := a.claimedBitmap[word]

	var claimedCount uint8

	for i, claim := range claims {
		index := uint64(i)
		mask := uint64(1) << index
		alreadyClaimed := bitmap&mask != 0

		if !alreadyClaimed {
			bitmap |= mask
			err := a.token.Transfer(claim.Claimee, claim.Amount.Uint64())
			if err != nil {
				return claimedCount, err
			}
			claimedCount++
		}
	}

	a.claimedBitmap[word] = bitmap
	return claimedCount, nil
}

// GetConfig returns the airdrop configuration
func (a *Airdrop) GetConfig() Config {
	return a.config
}
