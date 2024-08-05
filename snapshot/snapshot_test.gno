package snapshot

import (
	"testing"
	"time"
)

func TestNewManager(t *testing.T) {
	manager := NewManager()
	if manager == nil {
		t.Fatal("Expected non-nil manager")
	}
	if len(manager.snapshots) != 0 {
		t.Errorf("Expected empty snapshots, got %d", len(manager.snapshots))
	}
	if manager.lastSnapshotID != 0 {
		t.Errorf("Expected lastSnapshotID to be 0, got %d", manager.lastSnapshotID)
	}
}

func TestCreateSnapshot(t *testing.T) {
	manager := NewManager()
	claimedBitmap := map[uint64]uint64{1: 5, 2: 10}
	remainingTokens := uint64(1000)

	id := manager.CreateSnapshot(claimedBitmap, remainingTokens)

	if id != 1 {
		t.Errorf("Expected snapshot ID 1, got %d", id)
	}

	if len(manager.snapshots) != 1 {
		t.Errorf("Expected 1 snapshot, got %d", len(manager.snapshots))
	}

	snapshot := manager.snapshots[0]
	if snapshot.ID != 1 {
		t.Errorf("Expected snapshot ID 1, got %d", snapshot.ID)
	}
	if snapshot.RemainingTokens != remainingTokens {
		t.Errorf("Expected remaining tokens %d, got %d", remainingTokens, snapshot.RemainingTokens)
	}
	if len(snapshot.ClaimedBitmap) != len(claimedBitmap) {
		t.Errorf("Expected claimed bitmap length %d, got %d", len(claimedBitmap), len(snapshot.ClaimedBitmap))
	}
	for k, v := range claimedBitmap {
		if snapshot.ClaimedBitmap[k] != v {
			t.Errorf("Expected claimed bitmap value %d for key %d, got %d", v, k, snapshot.ClaimedBitmap[k])
		}
	}
}

func TestGetSnapshot(t *testing.T) {
	manager := NewManager()
	manager.CreateSnapshot(map[uint64]uint64{}, 1000)

	snapshot, err := manager.GetSnapshot(1)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if snapshot.ID != 1 {
		t.Errorf("Expected snapshot ID 1, got %d", snapshot.ID)
	}

	_, err = manager.GetSnapshot(2)
	if err == nil {
		t.Error("Expected error for non-existent snapshot, got nil")
	}
}

func TestIsClaimedAtSnapshot(t *testing.T) {
	manager := NewManager()
	claimedBitmap := map[uint64]uint64{1: 5} // 0101 in binary
	manager.CreateSnapshot(claimedBitmap, 1000)

	testCases := []struct {
		claimID  uint64
		expected bool
	}{
		{64, true},   // 1st bit in word 1
		{65, false},  // 2nd bit in word 1
		{66, true},   // 3rd bit in word 1
		{128, false}, // 1st bit in word 2 (not set)
	}

	for _, tc := range testCases {
		claimed, err := manager.IsClaimedAtSnapshot(1, tc.claimID)
		if err != nil {
			t.Errorf("Unexpected error for claimID %d: %v", tc.claimID, err)
		}
		if claimed != tc.expected {
			t.Errorf("For claimID %d, expected claimed: %v, got: %v", tc.claimID, tc.expected, claimed)
		}
	}

	// Test non-existent snapshot
	_, err := manager.IsClaimedAtSnapshot(2, 64)
	if err == nil {
		t.Error("Expected error for non-existent snapshot, got nil")
	}
}

func TestClaimIDToBitmapIndex(t *testing.T) {
	testCases := []struct {
		claimID       uint64
		expectedWord  uint64
		expectedIndex uint64
	}{
		{0, 0, 0},
		{63, 0, 63},
		{64, 1, 0},
		{65, 1, 1},
		{128, 2, 0},
		{1000, 15, 40},
	}

	for _, tc := range testCases {
		word, index := claimIDToBitmapIndex(tc.claimID)
		if word != tc.expectedWord || index != tc.expectedIndex {
			t.Errorf("For claimID %d, expected (word: %d, index: %d), got (word: %d, index: %d)",
				tc.claimID, tc.expectedWord, tc.expectedIndex, word, index)
		}
	}
}

func TestSnapshotTimestamp(t *testing.T) {
	manager := NewManager()
	before := time.Now().Unix()
	manager.CreateSnapshot(map[uint64]uint64{}, 1000)
	after := time.Now().Unix()

	snapshot, _ := manager.GetSnapshot(1)
	if snapshot.Timestamp < before || snapshot.Timestamp > after {
		t.Errorf("Expected timestamp between %d and %d, got %d", before, after, snapshot.Timestamp)
	}
}
