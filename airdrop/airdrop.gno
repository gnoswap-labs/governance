package airdrop

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"std"
	"time"

	"gno.land/p/demo/grc/grc20"
	i256 "gno.land/p/demo/int256"
	"gno.land/p/demo/merkle"
	u256 "gno.land/p/demo/uint256"
)

var (
	ErrInvalidProof              = errors.New("INVALID_PROOF")
	ErrInvalidClaimsCount        = errors.New("INVALID_CLAIMS_COUNT")
	ErrFirstClaimIsNot128        = errors.New("FIRST_CLAIM_MUST_BE_MULT_128")
	ErrRefundableTimestampNotSet = errors.New("REFUNDABLE_TIMESTAMP_NOT_SET")
	ErrTooEarlyToRefund          = errors.New("TOO_EARLY_TO_REFUND")
)

type Claim struct {
	ID      uint64
	Claimee string
	Amount  *u256.Uint // ? u256
}

func (c Claim) Bytes() []byte {
	var buf bytes.Buffer
	idBytes := make([]byte, 8)
	binary.BigEndian.PutUint64(idBytes, c.ID)
	buf.Write(idBytes)
	buf.Write([]byte(c.Claimee))
	amountStr := c.Amount.ToString()
	buf.Write([]byte(amountStr))
	return buf.Bytes()
}

type Config struct {
	Root                [32]byte
	RefundableTimestamp uint64 // TODO: timelock
	RefundTo            std.Address
}

type Airdrop struct {
	token         grc20.IGRC20
	config        Config
	claimedBitmap map[uint64]*u256.Uint
	merkleTree    *merkle.Tree
}

type IAirdrop interface {
	GetToken() string
	GetConfig() Config
	Claim(claim Claim, proof [][]byte) bool
	Claim128(claims []Claim, remainingProof [][]byte) uint8
	IsClaimed(claimID uint64) bool
	Refund()
}

// NewAirdrop creates a new Airdrop instance
func NewAirdrop(token grc20.IGRC20, config Config, claims []Claim) (*Airdrop, error) {
	// create Merkle tree
	//
	// need to know the number of claims to create the hashables slice
	hashables := make([]merkle.Hashable, len(claims))
	for i, claim := range claims {
		hashables[i] = claim
	}
	tree := merkle.NewTree(hashables)

	// verify that the computed root matches the provided root
	// if hex.EncodeToString(tree.Root()) != hex.EncodeToString(config.Root[:]) {
	// 	return nil, errors.New("computed root does not match provided root")
	// }

	return &Airdrop{
		token:         token,
		config:        config,
		claimedBitmap: make(map[uint64]*u256.Uint),
		merkleTree:    tree,
	}, nil
}

// GetToken returns the token address
// func (a *Airdrop) GetToken() std.Address {
// 	// TODO: get its address
// 	return a.token.GetAddress()
// }

// GetConfig returns the airdrop configuration
func (a *Airdrop) GetConfig() Config {
	return a.config
}

// IsClaimed checks if a claim has been made (claimed)
func (a *Airdrop) IsClaimed(claimID uint64) bool {
	word, index := a.claimIDToBitmapIndex(claimID)
	bitmap, exists := a.claimedBitmap[word]
	if !exists {
		return false
	}
	mask := new(u256.Uint).Lsh(u256.NewUint(1), uint(index))
	return new(u256.Uint).And(bitmap, mask).Cmp(u256.Zero()) != 0
}

// claimIDToBitmapIndex converts a claim ID to bitmap index
func (a *Airdrop) claimIDToBitmapIndex(claimID uint64) (word uint64, index uint8) {
	word = claimID / 256
	index = uint8(claimID % 256)
	return
}

// Claim processes a single claim
func (a *Airdrop) Claim(claim Claim, proof [][]byte) (bool, error) {
	valid, err := a.verifyProof(claim, proof)
	if err != nil {
		return false, err
	}
	if !valid {
		return false, ErrInvalidProof
	}

	word, index := a.claimIDToBitmapIndex(claim.ID)
	bitmap, exists := a.claimedBitmap[word]
	if !exists {
		bitmap = u256.Zero()
	}
	mask := new(u256.Uint).Lsh(u256.NewUint(1), uint(index))
	alreadyClaimed := new(u256.Uint).And(bitmap, mask).Cmp(u256.Zero()) != 0

	if alreadyClaimed {
		return false, nil // XXX should we return an error?
	}

	// update the bitmap
	newBitmap := new(u256.Uint).Or(bitmap, mask)
	a.claimedBitmap[word] = newBitmap

	// transfer tokens
	err = a.token.Transfer(std.Address(claim.Claimee), claim.Amount.Uint64())
	if err != nil {
		return false, err
	}

	return true, nil
}

// verifyProof checks if the merkle proof is valid
func (a *Airdrop) verifyProof(claim Claim, proff [][]byte) (bool, error) {
	proof, err := a.merkleTree.Proof(claim)
	if err != nil {
		return false, err
	}
	return a.merkleTree.Verify(claim, proof), nil
}

// Claim128 processes up to 128 claims in a single batch
func (a *Airdrop) Claim128(claims []Claim, remainingProof [][]byte) (uint8, error) {
	if len(claims) == 0 || len(claims) > 128 {
		return 0, ErrInvalidClaimsCount
	}

	// verify that the first claim ID is a multiple of 128
	if claims[0].ID%128 != 0 {
		return 0, ErrFirstClaimIsNot128
	}

	word := claims[0].ID / 256
	bitmap, exists := a.claimedBitmap[word]
	if !exists {
		bitmap = u256.Zero()
	}

	var claimedCount uint8

	for i, claim := range claims {
		index := uint8(i)
		mask := new(u256.Uint).Lsh(u256.NewUint(1), uint(index))
		alreadyClaimed := new(u256.Uint).And(bitmap, mask).Cmp(u256.Zero()) != 0

		if !alreadyClaimed {
			bitmap = new(u256.Uint).Or(bitmap, mask)
			err := a.token.Transfer(std.Address(claim.Claimee), claim.Amount.Uint64())
			if err != nil {
				return claimedCount, err
			}
			claimedCount++
		}
	}

	a.claimedBitmap[word] = bitmap
	return claimedCount, nil
}

// func (a *Airdrop) Refund() error {
// 	if a.config.RefundableTimestamp == 0 {
// 		return ErrRefundableTimestampNotSet
// 	}

// 	currentTime := uint64(time.Now().Unix())
// 	if currentTime < a.config.RefundableTimestamp {
// 		return ErrTooEarlyToRefund
// 	}

// 	balance, err:= a.token.BalanceOf(a.GetToken()) // ?
// 	if err != nil {
// 		return err
// 	}

// 	return a.token.Transfer(a.config.RefundTo, balance)
// }
