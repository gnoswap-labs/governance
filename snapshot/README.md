# Snapshot

## Overview

The snapshot package provides functionality to capture and mange the state of a system at specific points in time. This package allows for creating, storing, and retrieving snapshots that include claimed bitmaps and the number of remaining tokens.

## Features

- Create and store snapshots
- Retrieve snapshots by ID
- Check claim status at a specific snapshot point

## How it Works

1. The `Manager` type manages a list of snapshots and the last snapshot ID.
2. Each new snapshot is assigned a unique ID and timestamped with the current time.
3. Each snapshot stores a claimed bitmap[^1] and the number of remaining tokens.

## Example

```go
package main

import (
    "gno.land/p/demo/ufmt"
    "gno.land/r/governance/snapshot"
)

func main() {
    // Create a new Manager
    manager := snapshot.NewManager()

    // Create a snapshot
    claimedBitmap := map[uint64]uint64{1: 5}
    remainingTokens := uint64(1000)
    id := manager.CreateSnapshot(claimedBitmap, remainingTokens)

    ufmt.Printf("Created snapshot with ID: %d\n", id)

    // Retrieve a snapshot
    snap, err := manager.GetSnapshot(id)
    if err != nil {
        fmt.Printf("Error retrieving snapshot: %v\n", err)
        return
    }

    ufmt.Printf("Retrieved snapshot: ID=%d, Timestamp=%d, RemainingTokens=%d\n", 
               snap.ID, snap.Timestamp, snap.RemainingTokens)

    // Check a specific claim status
    claimed, err := manager.IsClaimedAtSnapshot(id, 64)
    if err != nil {
        fmt.Printf("Error checking claim: %v\n", err)
        return
    }

    ufmt.Printf("Claim 64 is claimed: %v\n", claimed)
}
```

## License

This package is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.

[^1]: The bitmap is represented as a map of `uint64` value, where each bit represents a state of specific claim.
