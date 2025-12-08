# Shield Auction Hook – Overview

Shield Auction Hook is a Uniswap v4 hook that mitigates Loss Versus Rebalancing (LVR) by running short sealed-bid auctions whenever pool price deviates materially from an external oracle price. EigenLayer operators compete to capture MEV; proceeds are redistributed to LPs, operators, and the protocol.

## Design Goals
- Detect LVR opportunities using an external price oracle.
- Trigger per-pool, per-block sealed-bid auctions on significant swaps.
- Pay auction proceeds to LPs (85%), AVS operator (10% incl. gas), and protocol (3%).
- Keep integration minimal: only hook permissions and oracle/AVS wiring are required.
- Remain pausible and admin-configurable for safety.

## Key Contracts
- `ShieldAuctionHook`: main hook; intercepts `beforeSwap`/`afterSwap`, tracks liquidity, orchestrates auctions and reward accounting.
- `AuctionLib`: data structures and helpers for auctions, bid commitments, and time calculations.
- `IPriceOracle`: interface for external price feed used to detect price deviation and staleness.
- `IAVSDirectory`: interface to EigenLayer AVS Directory for operator registration checks.
- `HookMiner`: helper to mine a CREATE2 hook address that satisfies Uniswap v4 permission bits.

## Hook Permissions
`ShieldAuctionHook` requires these permissions: `beforeSwap`, `afterSwap`, `afterAddLiquidity`, `afterRemoveLiquidity`. The deployed address must embed these flags in its low 160 bits (standard v4 hook requirement). Use `HookMiner` or equivalent address mining to find a valid address for deployment.

## Flow Summary
1. **Liquidity tracking** (`afterAddLiquidity` / `afterRemoveLiquidity`): track per-pool LP liquidity to simplify proportional reward accounting.
2. **Swap interception** (`beforeSwap`): if swap size is meaningful and price deviation from oracle meets `lvrThreshold`, start a new sealed-bid auction for the pool (one active auction per pool).
3. **Auction lifecycle**:
   - Start: create `AuctionLib.Auction` with 12s duration (`MAX_AUCTION_DURATION`), store active auction id per pool.
   - Commit: authorized operators submit bid commitments (`commitBid`), counted toward `totalBids`.
   - Reveal: only authorized operators (`onlyAuthorizedOperator`) reveal bids; highest revealed bid tracked as winner.
   - End: when duration elapses, `afterSwap` finalizes (`_endAuction`), records winner, and moves proceeds to reward buckets.
4. **Reward distribution** (`_distributeRewards`): split winning bid into LP rewards (85%), operator reward (10% incl. gas comp), protocol fee (3%), gas compensation (2% counted within operator share). LP rewards are currently pooled and claimable per pool.
5. **Claims** (`claimRewards`): LPs withdraw accumulated rewards for a pool (simplified event-based transfer placeholder).
6. **Admin controls**: owner may pause/unpause, set LVR threshold, fee recipient, and authorize/deauthorize operators in addition to AVS registration.

## Auction Mechanics
- **Trigger**: price deviation in basis points between pool spot and oracle price >= `lvrThreshold` (configurable, e.g., 100 = 1%) and swap size >= 0.1 ETH equivalent.
- **Duration**: 12 seconds (approx. one block); only one active auction per pool.
- **Sealed-bid**: commitments are `keccak256(bidder, amount, nonce)` (see `AuctionLib.generateCommitment`). Reveal validates commitment and enforces `MIN_BID` (0.001 ETH).
- **Winning**: highest revealed bid becomes winner; auction is idempotently finalized once ended.

## External Dependencies
- **Uniswap v4 Core/Periphery**: hook ABI and permission bits; hook must be deployed to a mined address.
- **Price Oracle**: must implement `IPriceOracle`, provide fresh prices, and expose staleness checks.
- **EigenLayer AVS Directory**: used to verify operator registration (`avsOperatorStatus`) in addition to owner-managed allowlist.

## Events and Observability
- `AuctionStarted`, `AuctionEnded`, `BidCommitted`, `BidRevealed`, `MEVDistributed`, `RewardsClaimed`, `LiquidityTracked`, `OperatorAuthorized/Deauthorized`, `LVRThresholdUpdated`.
- Useful for off-chain indexers and operator UIs to track auction lifecycle and rewards.

## Safety Considerations
- **Reentrancy**: guarded via `ReentrancyGuard` on external entry points.
- **Pause switch**: all swap hooks respect `whenNotPaused`.
- **Oracle risk**: stale/zero prices skip auction triggers; integrators must ensure robust oracle feeds.
- **Accounting simplification**: liquidity tracking is simplified; production deployments should replace with precise per-position accounting and real token transfers.
- **Permissions correctness**: deploying to an address without proper hook flags will brick the pool; always validate mined address before deployment.


