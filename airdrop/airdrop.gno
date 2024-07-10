package airdrop

import (
	"encoding/binary"
	"errors"
	"std"
	"time"

	"gno.land/p/demo/grc/grc20"
	"gno.land/p/demo/merkle"
	"gno.land/p/demo/uint256"
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

func (c Claim) Bytes() []byte {
	b := make([]byte, 8+20+32) // 8 bytes for ID, 20 bytes for address, 32 bytes for amount
	binary.BigEndian.PutUint64(b[:8], c.ID)
	copy(b[8:28], c.Claimee[:])
	
	// convert u256 to bytes
	lowBits, _ := c.Amount.Uint64WithOverflow()
	binary.BigEndian.PutUint64(b[28:36], lowBits)

	// shift right by 64 bits and get the next 64 bits
	shiftedAmount := new(uint256.Uint).Rsh(c.Amount, 64)
	midLowBits, _ := shiftedAmount.Uint64WithOverflow()
	binary.BigEndian.PutUint64(b[36:44], midLowBits)

	// shift right by 128 bits and get the next 64 bits
	shiftedAmount = new(uint256.Uint).Rsh(shiftedAmount, 64)
	midHighBits, _ := shiftedAmount.Uint64WithOverflow()
	binary.BigEndian.PutUint64(b[44:52], midHighBits)

	// shift right by 192 bits and get the next 64 bits
	shiftedAmount = new(uint256.Uint).Rsh(shiftedAmount, 64)
	highBits, _ := shiftedAmount.Uint64WithOverflow()
	binary.BigEndian.PutUint64(b[52:60], highBits)

	return b
}

// Snapshot represents a snapshot of the airdrop contract
type Snapshot struct {
	Root string
	Timestamp uint64
}

// Config represents the airdrop configuration
type Config struct {
	RefundableTimestamp uint64
	RefundTo            std.Address
}

// Airdrop represents the airdrop contract
type Airdrop struct {
	token         grc20.Token
	config        Config
	claimedBitmap map[uint64]uint64
	address       std.Address
	snapshots     []Snapshot
	claims	      []Claim
}

// NewAirdrop creates a new Airdrop instance
func NewAirdrop(token grc20.Token, config Config, addr std.Address, initialClaims []Claim) *Airdrop {
	a := &Airdrop{
		token:         token,
		config:        config,
		claimedBitmap: make(map[uint64]uint64),
		address:       addr,
		claims:        initialClaims,
	}
	a.CreateSnapshot()
	return a
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
func (a *Airdrop) Claim(claim Claim, proof []merkle.Node) bool {
	// verify the claim against the latest snapshot
	if !a.VerifySnapshot(claim, proof, len(a.snapshots)-1) {
		panic("INVALID_PROOF")
	}

	word, index := a.claimIDToBitmapIndex(claim.ID)
	bitmap := a.claimedBitmap[word]
	mask := uint64(1) << index
	alreadyClaimed := bitmap&mask != 0

	if alreadyClaimed {
		return false
	}

	// check if the airdrop contract has enough balance to transfer
	airdropBalance := a.token.BalanceOf(a.address)
	if airdropBalance < claim.Amount.Uint64() {
		panic(ErrInsufficientBalance)
	}

	err := a.token.Transfer(claim.Claimee, claim.Amount.Uint64())
	if err != nil {
		panic(err)
	}

	// Update the bitmap
	a.claimedBitmap[word] = bitmap | mask

	return true
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

func (a *Airdrop) AddClaim(claim Claim) {
	a.claims = append(a.claims, claim)
	a.CreateSnapshot()
}

func (a *Airdrop) GetLatestRoot() string {
	if len(a.snapshots) == 0 {
		return ""
	}
	return a.snapshots[len(a.snapshots)-1].Root
}

// CreateSnapshot creates a new snapshot of the current state
func (a *Airdrop) CreateSnapshot() {
	hashable := make([]merkle.Hashable, len(a.claims))
	for i, claim := range a.claims {
		hashable[i] = merkle.Hashable(claim)
	}
	tree := merkle.NewTree(hashable)
	root := tree.Root()
	snapshot := Snapshot{
		Root: root,
		Timestamp: uint64(timeNow().Unix()),
	}
	a.snapshots = append(a.snapshots, snapshot)
}

func (a *Airdrop) GetProof(claim Claim) []merkle.Node {
	hashables := make([]merkle.Hashable, len(a.claims))
	for i, c := range a.claims {
		hashables[i] = c
	}

	tree := merkle.NewTree(hashables)
	p, _ := tree.Proof(claim)
	return p
}

// Verifysnapshot verifies if a claim is valid at a specific snapshot
func (a *Airdrop) VerifySnapshot(claim Claim, proof []merkle.Node, snapshotIndex int) bool {
	if snapshotIndex >= len(a.snapshots) {
		return false
	}
	snapshot := a.snapshots[snapshotIndex]
	return merkle.Verify(snapshot.Root, claim, proof)
}

// GetConfig returns the airdrop configuration
func (a *Airdrop) GetConfig() Config {
	return a.config
}

func (a *Airdrop) GetAddress() std.Address {
	return a.address
}
