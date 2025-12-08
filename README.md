# Shield Auction Hook
Mitigate Loss Versus Rebalancing (LVR) in Uniswap v4 pools by running per-block sealed-bid auctions that redirect MEV to LPs. EigenLayer operators bid to execute profitable rebalancing; proceeds are split across LPs, the winning operator (incl. gas), and the protocol.

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Contracts](#contracts)
- [Auction Flow](#auction-flow)
- [Rewards & Fees](#rewards--fees)
- [Hook Permissions & Address Mining](#hook-permissions--address-mining)
- [Setup](#setup)
- [Building & Testing](#building--testing)
- [Deployment](#deployment)
- [Admin & Ops](#admin--ops)
- [Security Notes](#security-notes)
- [License](#license)

## Overview
- Detect LVR opportunities by comparing pool spot price to an external oracle.
- On significant swaps and sufficient deviation, start a short sealed-bid auction (12s).
- Authorized EigenLayer operators commit/reveal bids; highest bid wins.
- Winning bid proceeds are distributed: 85% LPs, 10% operator (incl. gas comp), 3% protocol fee.
- Pausable, owner-governed thresholds and operator allowlist in addition to EigenLayer registration.

## Architecture
- **Uniswap v4 Hook**: Implements `beforeSwap`, `afterSwap`, `afterAddLiquidity`, `afterRemoveLiquidity`.
- **Oracle**: Any contract implementing `IPriceOracle` supplying fresh prices and staleness checks.
- **EigenLayer AVS Directory**: Verifies operator registration status for reveal-phase authorization.
- **Sealed-bid auctions**: Commit via hash, reveal with amount+nonce; tracked per pool, one active at a time.
- **Liquidity tracking**: Simplified per-LP liquidity accounting to apportion LP rewards (placeholder; production should use precise position accounting and real token transfers).

## Contracts
- `src/ShieldAuctionHook.sol`: Core hook; triggers auctions, validates bids, finalizes, and accounts rewards.
- `src/Auction.sol` (`AuctionLib`): Auction/bid structs, commitment helpers, timing utilities.
- `src/IPriceOracle.sol`: Oracle interface for price + staleness.
- `src/IAVSDirectory.sol`: EigenLayer AVS Directory interface for operator registration checks.
- `src/HookMiner.sol`: Utility to mine a CREATE2 hook address with required permission bits.
- Tests & mocks: `test/ShieldAuctionHook.t.sol`, `test/MockAVSDirectory.sol`, `test/MockPriceOracle.sol`.

## Auction Flow
1. **Trigger** (`beforeSwap`): If swap size ≥ 0.1 ETH-equivalent and price deviation vs. oracle ≥ `lvrThreshold`, start a 12s auction for that pool (skip if one already active).
2. **Commit**: Operators call `commitBid(auctionId, commitment)` where `commitment = keccak256(bidder, amount, nonce)`.
3. **Reveal**: Authorized operators call `revealBid(auctionId, amount, nonce)`; `amount` must satisfy `MIN_BID` (0.001 ETH). Highest revealed bid tracked.
4. **Finalize** (`afterSwap`): When duration has elapsed, the next swap ends the auction, records winner, and allocates proceeds.
5. **LP Claims**: LPs call `claimRewards(poolId)` to withdraw accumulated rewards (event placeholder; wire real transfers in production).

## Rewards & Fees
- **LP reward**: 85% (`LP_REWARD_PERCENTAGE`)
- **AVS operator reward**: 10% (`AVS_REWARD_PERCENTAGE`, includes gas compensation)
- **Protocol fee**: 3% (`PROTOCOL_FEE_PERCENTAGE`)
- **Gas compensation**: 2% (`GAS_COMPENSATION_PERCENTAGE`, counted inside operator share)
- Percentages sum to `BASIS_POINTS` (10,000).

## Hook Permissions & Address Mining
Required permissions: `beforeSwap`, `afterSwap`, `afterAddLiquidity`, `afterRemoveLiquidity`. The deployed hook address must encode these flags in its low 160 bits (Uniswap v4 requirement). Mine a valid CREATE2 address with `HookMiner`:
```solidity
import { HookMiner } from "./src/HookMiner.sol";
import { Hooks } from "@uniswap/v4-core/libraries/Hooks.sol";
import { ShieldAuctionHook } from "./src/ShieldAuctionHook.sol";

uint160 flags = Hooks.BEFORE_SWAP_FLAG
    | Hooks.AFTER_SWAP_FLAG
    | Hooks.AFTER_ADD_LIQUIDITY_FLAG
    | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG;

(address hookAddress, bytes32 salt) = HookMiner.find(
    deployer,
    flags,
    type(ShieldAuctionHook).creationCode,
    abi.encode(poolManager, avsDirectory, avsAddress, priceOracle, feeRecipient, lvrThreshold)
);
// Deploy with CREATE2 to hookAddress using the mined salt.
```

## Setup
1. Install Foundry: `curl -L https://foundry.paradigm.xyz | bash` then `foundryup`.
2. Fetch deps (if using submodules): `git submodule update --init --recursive`.
3. Ensure Uniswap v4 core/periphery, EigenLayer interfaces, and OZ are available (already vendored under `lib/`).

## Building & Testing
- Build: `forge build`
- Test (verbose): `forge test -vvv`
- Format: `forge fmt`
- Gas report: `forge snapshot`
- Local node: `anvil`

Key tests: `test/ShieldAuctionHook.t.sol` covers deployment, permission mask correctness, auction lifecycle, bidding/reveal, reward math, LVR detection, admin controls, and pause behavior.

## Deployment
Constructor args (ShieldAuctionHook):
- `IPoolManager poolManager`
- `IAVSDirectory avsDirectory`
- `address avsAddress`
- `IPriceOracle priceOracle`
- `address feeRecipient`
- `uint256 lvrThreshold` (basis points; e.g., 100 = 1%)

Deployment outline:
1. Mine hook address with required permission flags (see above).
2. Deploy via CREATE2 with mined salt and constructor args.
3. Create pool using `PoolKey` pointing `hooks` to the deployed hook address, then `initialize`.
4. Seed liquidity so swaps can occur.
5. Register operators in EigenLayer for your AVS and/or owner-allowlist them via `setOperatorAuthorization`.

## Admin & Ops
- `setOperatorAuthorization(operator, bool)`: owner allowlist override in addition to AVS registration.
- `setLVRThreshold(newBps)`: adjust deviation trigger.
- `setFeeRecipient(addr)`: update protocol fee sink.
- `pause()` / `unpause()`: halt or resume swap hooks and auction triggering.
- View helpers: `activeAuctions(poolId)`, `auctions(auctionId)`, `bidCommitments`, `revealedBids`, `poolRewards`, `lpRewards`, `lpLiquidity`, `totalLiquidity`.

## Security Notes
- Hook is pausable and uses `ReentrancyGuard`, but production deployments must:
  - Replace placeholder reward transfers with real token/native payouts.
  - Use robust multi-source oracles and strict staleness windows.
  - Harden liquidity accounting (current version is simplified).
  - Monitor events (`AuctionStarted`, `AuctionEnded`, `MEVDistributed`, etc.) for operations and alerting.
- Deploying to an address without correct permission bits will brick the hook; always validate mined address before use.

## License
MIT
