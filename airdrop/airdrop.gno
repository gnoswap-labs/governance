package airdrop

import (
	"errors"
	"std"
	"time"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/uint256"

	"gno.land/r/governance/snapshot"
)

var (
	ErrInvalidClaimsCount  = errors.New("INVALID_CLAIMS_COUNT")
	ErrFirstClaimIsNot64   = errors.New("FIRST_CLAIM_MUST_BE_MULT_64")
	ErrInsufficientBalance = errors.New("INSUFFICIENT_BALANCE")
	ErrRefundNotAllowed    = errors.New("refund not allowed")
	ErrTooEarly            = errors.New("too early")
	ErrNoBalance           = errors.New("no balance to refund")
)

var timeNow = time.Now

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
	token           grc20.Token
	config          Config
	claimedBitmap   map[uint64]uint64 // claimID -> bitmap
	address         std.Address
	snapshotManager *snapshot.Manager
}

var airdropToken grc20.Token

// NewAirdrop creates a new Airdrop instance
func NewAirdrop(token grc20.Token, config Config, addr std.Address) *Airdrop {
	airdropToken = token
	return &Airdrop{
		token:           token,
		config:          config,
		claimedBitmap:   make(map[uint64]uint64),
		address:         addr,
		snapshotManager: snapshot.NewManager(),
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
	airdropBalance := a.token.BalanceOf(std.GetOrigCaller())
	if airdropBalance < claim.Amount.Uint64() {
		panic(ErrInsufficientBalance)
	}

	err := a.token.Transfer(claim.Claimee, claim.Amount.Uint64())
	if err != nil {
		panic(err)
	}

	// Update the bitmap
	a.claimedBitmap[word] = bitmap | mask

	return true, nil
}

// Claim64 processes up to 64 claims in a single batch
func (a *Airdrop) Claim64(claims []Claim) (uint8, error) {
	if len(claims) == 0 || len(claims) > 64 {
		panic(ErrInvalidClaimsCount)
	}

	if claims[0].ID%64 != 0 {
		panic(ErrFirstClaimIsNot64)
	}

	word := claims[0].ID / 64
	bitmap := a.claimedBitmap[word]

	var (
		claimedCount uint8
		totalAmount  uint64
	)

	// calculate total amount and check if any claim is already processed
	for i, claim := range claims {
		index := uint64(i)
		mask := uint64(1) << index
		alreadyClaimed := bitmap&mask != 0

		if !alreadyClaimed {
			totalAmount += claim.Amount.Uint64()
		}
	}

	// check has enough balance to transfer
	airdropBalance := a.token.BalanceOf(std.GetOrigCaller())
	if airdropBalance < totalAmount {
		panic(ErrInsufficientBalance)
	}

	// process claims
	for i, claim := range claims {
		index := uint64(i)
		mask := uint64(1) << index

		alreadyClaimed := bitmap&mask != 0
		if alreadyClaimed {
			continue
		}

		err := a.token.Transfer(claim.Claimee, claim.Amount.Uint64())
		if err != nil {
			return claimedCount, err
		}

		bitmap |= mask
		claimedCount++
	}

	a.claimedBitmap[word] = bitmap
	return claimedCount, nil
}

// Refund refunds the remaining tokens to the specified address after the refundable timestamp
func (a *Airdrop) Refund() error {
	if a.config.RefundableTimestamp == 0 {
		panic(ErrRefundNotAllowed)
	}

	if uint64(timeNow().Unix()) < a.config.RefundableTimestamp {
		panic(ErrTooEarly)
	}

	balance := a.token.BalanceOf(a.address)
	if balance == 0 {
		panic(ErrNoBalance)
	}

	err := a.token.TransferFrom(a.address, a.config.RefundTo, balance)
	if err != nil {
		panic(err)
	}

	return nil
}

// GetConfig returns the airdrop configuration
func (a *Airdrop) GetConfig() Config {
	return a.config
}

func (a *Airdrop) GetAddress() std.Address {
	return a.address
}

// CreateSnapshot creates a new snapshot of the current state
func (a *Airdrop) CreateSnapshot(caller string) uint64 {
	callerAddr := std.Address(caller)
	return a.snapshotManager.CreateSnapshot(a.claimedBitmap, a.token.BalanceOf(callerAddr))
}

// IsClaimedAtSnapshot checks if a claim was made at a specific snapshot
func (a *Airdrop) IsClaimedAtSnapshot(snapshotID uint64, claimID uint64) (bool, error) {
	return a.snapshotManager.IsClaimedAtSnapshot(snapshotID, claimID)
}

// GetSnapshot retrieves a specific snapshot
func (a *Airdrop) GetSnapshot(id uint64) (snapshot.Snapshot, error) {
	return a.snapshotManager.GetSnapshot(id)
}
