# Shield Auction Hook – Integration Guide

This guide explains how to deploy and wire Shield Auction Hook into a Uniswap v4 pool, connect EigenLayer operators, and operate the sealed-bid auction flow.

## Prerequisites
- Foundry toolchain (`forge`, `anvil`), Uniswap v4 core/periphery libraries available at compile time.
- Access to a price oracle implementing `IPriceOracle` that returns fresh, non-stale prices for the traded pair.
- Access to EigenLayer AVS Directory (`IAVSDirectory`) and an AVS address that operators register against.
- A deployer capable of CREATE2 address mining (see `HookMiner`) so the hook address encodes required permissions.

## Required Hook Permissions
The hook uses `beforeSwap`, `afterSwap`, `afterAddLiquidity`, and `afterRemoveLiquidity`. The deployed address must have the corresponding permission bits set in its low 160 bits. If the address does not satisfy the mask, the PoolManager will reject the hook.

### Mining a Valid Address
Use `HookMiner` to compute a CREATE2 salt that yields a valid address:
```solidity
import { HookMiner } from "../src/HookMiner.sol";
import { Hooks } from "@uniswap/v4-core/libraries/Hooks.sol";

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
```
Deploy with CREATE2 using the mined `hookAddress` and `salt`.

## Deployment Steps
1. **Collect dependencies**:
   - `poolManager`: deployed Uniswap v4 `PoolManager`.
   - `avsDirectory`: EigenLayer AVS directory address.
   - `avsAddress`: your AVS identifier.
   - `priceOracle`: contract implementing `IPriceOracle`.
   - `feeRecipient`: protocol fee sink.
   - `lvrThreshold`: deviation threshold in basis points (1% = 100).
2. **Mine hook address** with the permission flags (above) and constructor args.
3. **Deploy hook** via CREATE2 to the mined address.
4. **Create / initialize pool** with `PoolKey` pointing `hooks` to the deployed address:
```solidity
PoolKey memory key = PoolKey({
    currency0: token0,
    currency1: token1,
    fee: 3000,
    tickSpacing: 60,
    hooks: IHooks(hookAddress)
});
poolManager.initialize(key, initSqrtPriceX96);
```
5. **Seed liquidity** so swaps can execute and auctions can be triggered.
6. **Authorize operators**:
   - Register operators in EigenLayer for your AVS (`avsOperatorStatus` must be `REGISTERED`), **and/or**
   - Owner calls `setOperatorAuthorization(operator, true)` for an allowlist override.
7. **Configure threshold/fees** as needed via owner functions (`setLVRThreshold`, `setFeeRecipient`).

## Runtime Behavior
- **Triggering**: On `beforeSwap`, if swap size ≥ 0.1 ETH-equivalent and price deviation vs. oracle ≥ `lvrThreshold`, a 12s auction is started for that pool (one at a time).
- **Commit phase**: Operators call `commitBid(auctionId, commitment)` with `commitment = keccak256(bidder, amount, nonce)`; `amount` must be ≥ `MIN_BID` (0.001 ETH).
- **Reveal phase**: Authorized operators call `revealBid(auctionId, amount, nonce)`. Highest revealed bid wins; bid counts recorded.
- **Finalize**: When duration elapses, the next `afterSwap` call auto-finalizes (`_endAuction`), splits proceeds (85% LPs / 10% operator incl. gas / 3% protocol), and emits `AuctionEnded` + `MEVDistributed`.
- **LP claims**: LPs call `claimRewards(poolId)` to withdraw their share (simplified event placeholder for now).
- **Pausing**: Owner can pause/unpause; when paused, swap hooks revert and no auctions start.

## Oracle Expectations
- `getPrice(token0, token1)` returns token1/token0 price in 18 decimals.
- `isPriceStale` must return `true` when data is outdated; stale prices suppress auctions.
- Returning zero prices disables triggers for that pair.

## Operator UX Tips
- Pre-compute commitments off-chain using `AuctionLib.generateCommitment(bidder, amount, nonce)`.
- Track auctions via `AuctionStarted`/`AuctionEnded` events per `poolId`.
- Use `auctions(auctionId)` view to read state; `getTimeRemaining` helper is available in `AuctionLib`.

## Testing Locally
- Build: `forge build`
- Run tests: `forge test -vvv`
- Gas snapshot: `forge snapshot`
The test suite (`test/ShieldAuctionHook.t.sol`) demonstrates end-to-end setup, permissioned deployment, auction triggers, bidding, reveals, and admin controls; use it as reference for your own scripts.

## Production Hardening Notes
- Replace placeholder reward transfers with real token payouts (native/ ERC20) and accurate per-position accounting.
- Consider slashing/penalty mechanisms for failing operators.
- Use robust, multi-source oracle data and tighter staleness windows.
- Tune `MIN_BID`, `MAX_AUCTION_DURATION`, and swap-size thresholds for target chain conditions.
- Monitor events for operational alerts and invariant checks.


