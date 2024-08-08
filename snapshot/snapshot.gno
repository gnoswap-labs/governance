package snapshot

import (
	"errors"
	"time"
)

// Snapshot represents a point-in-time capture  of the state of a system.
type Snapshot struct {
	ID              uint64
	Timestamp       int64
	ClaimedBitmap   map[uint64]uint64
	RemainingTokens uint64
}

// Manager manages the creation and retrieval of snapshots.
type Manager struct {
	snapshots      []Snapshot
	lastSnapshotID uint64
}

func NewManager() *Manager {
	return &Manager{
		snapshots:      make([]Snapshot, 0),
		lastSnapshotID: 0,
	}
}

// CreateSnapshot generates a new snapshot with the given claimed bitmap and remaining tokens.
//
// It returns the ID of the newly created snapshot.
func (m *Manager) CreateSnapshot(claimedBitmap map[uint64]uint64, remainingTokens uint64) uint64 {
	m.lastSnapshotID++
	snapshot := Snapshot{
		ID:              m.lastSnapshotID,
		Timestamp:       time.Now().Unix(),
		ClaimedBitmap:   make(map[uint64]uint64),
		RemainingTokens: remainingTokens,
	}

	// deep copy for current claimedBitmap
	for k, v := range claimedBitmap {
		snapshot.ClaimedBitmap[k] = v
	}

	m.snapshots = append(m.snapshots, snapshot)
	return m.lastSnapshotID
}

// GetSnapshot retrieves a snapshot by its ID.
//
// It returns the snapshot if found, otherwise an error.
func (m *Manager) GetSnapshot(id uint64) (Snapshot, error) {
	for _, snapshot := range m.snapshots {
		if snapshot.ID == id {
			return snapshot, nil
		}
	}
	return Snapshot{}, errors.New("snapshot not found")
}

// IsClaimedAtSnapshot checks if a specifix claim was made at the time of a given snapshot.
//
// It returns true if the claim was made, false if not.
func (m *Manager) IsClaimedAtSnapshot(snapshotID, claimID uint64) (bool, error) {
	snapshot, err := m.GetSnapshot(snapshotID)
	if err != nil {
		return false, err
	}

	word, index := claimIDToBitmapIndex(claimID)
	bitmap, exists := snapshot.ClaimedBitmap[word]
	if !exists {
		return false, nil
	}

	return bitmap&(1<<index) != 0, nil
}

func claimIDToBitmapIndex(claimID uint64) (word uint64, index uint64) {
	word = claimID / 64
	index = claimID % 64
	return
}
