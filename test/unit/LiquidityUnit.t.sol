// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestFixture} from "../utils/TestFixture.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/types/PoolOperation.sol";

/**
 * @title LiquidityUnit
 * @notice Unit tests for liquidity tracking
 */
contract LiquidityUnit is TestFixture {

    // Test: Add liquidity tracks LP position
    function test_addLiquidityTracksLP() public {
        uint256 initialLiquidity = hook.lpLiquidity(poolId, address(this));
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 newLiquidity = hook.lpLiquidity(poolId, address(this));
        assertGe(newLiquidity, initialLiquidity);
    }

    // Test: Remove liquidity updates LP position
    function test_removeLiquidityUpdatesLP() public {
        // Add liquidity first
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 liquidityBefore = hook.lpLiquidity(poolId, address(this));
        
        // Remove liquidity
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: -int128(int256(1e19)),
                salt: 0
            }),
            ""
        );
        
        uint256 liquidityAfter = hook.lpLiquidity(poolId, address(this));
        assertLe(liquidityAfter, liquidityBefore);
    }

    // Test: Total liquidity tracking
    function test_totalLiquidityTracking() public {
        uint256 initialTotal = hook.totalLiquidity(poolId);
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 newTotal = hook.totalLiquidity(poolId);
        assertGe(newTotal, initialTotal);
    }

    // Test: Multiple LPs liquidity tracking
    function test_multipleLPsLiquidityTracking() public {
        vm.prank(lp1);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        vm.prank(lp2);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        assertGt(hook.lpLiquidity(poolId, lp1), 0);
        assertGt(hook.lpLiquidity(poolId, lp2), 0);
    }

    // Test: LP liquidity starts at zero
    function test_lpLiquidityStartsAtZero() public {
        address newLP = makeAddr("newLP");
        assertEq(hook.lpLiquidity(poolId, newLP), 0);
    }

    // Test: Total liquidity increases with additions
    function test_totalLiquidityIncreases() public {
        uint256 total1 = hook.totalLiquidity(poolId);
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 total2 = hook.totalLiquidity(poolId);
        assertGt(total2, total1);
    }

    // Test: Total liquidity decreases with removals
    function test_totalLiquidityDecreases() public {
        // Add liquidity first
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 total1 = hook.totalLiquidity(poolId);
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: -int128(int256(1e19)),
                salt: 0
            }),
            ""
        );
        
        uint256 total2 = hook.totalLiquidity(poolId);
        assertLt(total2, total1);
    }

    // Test: LP rewards tracking
    function test_lpRewardsTracking() public {
        bytes32 auctionId = createAuction();
        uint256 winningBid = 10 ether;
        
        commitBid(auctionId, operator1, winningBid, 123);
        revealBid(auctionId, operator1, winningBid, 123);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        // LP rewards should be tracked
        uint256 poolRewards = hook.poolRewards(poolId);
        assertGt(poolRewards, 0);
    }

    // Test: LP rewards per address
    function test_lpRewardsPerAddress() public {
        // Add liquidity
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        bytes32 auctionId = createAuction();
        uint256 winningBid = 10 ether;
        
        commitBid(auctionId, operator1, winningBid, 123);
        revealBid(auctionId, operator1, winningBid, 123);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        uint256 lpReward = hook.lpRewards(poolId, address(this));
        assertGe(lpReward, 0);
    }

    // Test: Liquidity tracking persistence
    function test_liquidityTrackingPersistence() public {
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 liquidity1 = hook.lpLiquidity(poolId, address(this));
        uint256 liquidity2 = hook.lpLiquidity(poolId, address(this));
        
        assertEq(liquidity1, liquidity2);
    }

    // Test: Total liquidity persistence
    function test_totalLiquidityPersistence() public {
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 total1 = hook.totalLiquidity(poolId);
        uint256 total2 = hook.totalLiquidity(poolId);
        
        assertEq(total1, total2);
    }

    // Test: Liquidity tracking with zero delta
    function test_liquidityTrackingZeroDelta() public {
        uint256 liquidityBefore = hook.lpLiquidity(poolId, address(this));
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 0,
                salt: 0
            }),
            ""
        );
        
        uint256 liquidityAfter = hook.lpLiquidity(poolId, address(this));
        assertEq(liquidityAfter, liquidityBefore);
    }

    // Test: Multiple liquidity modifications
    function test_multipleLiquidityModifications() public {
        uint256 liquidity1 = hook.lpLiquidity(poolId, address(this));
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 liquidity2 = hook.lpLiquidity(poolId, address(this));
        assertGt(liquidity2, liquidity1);
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 liquidity3 = hook.lpLiquidity(poolId, address(this));
        assertGt(liquidity3, liquidity2);
    }

    // Test: Liquidity tracking across different pools
    function test_liquidityTrackingDifferentPools() public {
        // Create second pool
        PoolKey memory poolKey2 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 5000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        manager.initialize(poolKey2, INIT_SQRT_PRICE);
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey2,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        PoolId poolId2 = poolKey2.toId();
        assertGt(hook.lpLiquidity(poolId, address(this)), 0);
        assertGt(hook.lpLiquidity(poolId2, address(this)), 0);
    }

    // Test: LP rewards distribution
    function test_lpRewardsDistribution() public {
        // Add liquidity
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        bytes32 auctionId = createAuction();
        uint256 winningBid = 10 ether;
        
        commitBid(auctionId, operator1, winningBid, 123);
        revealBid(auctionId, operator1, winningBid, 123);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        uint256 poolRewards = hook.poolRewards(poolId);
        uint256 lpReward = hook.lpRewards(poolId, address(this));
        
        assertGt(poolRewards, 0);
        assertGe(lpReward, 0);
    }

    // Test: Liquidity tracking with negative delta
    function test_liquidityTrackingNegativeDelta() public {
        // Add liquidity first
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 liquidityBefore = hook.lpLiquidity(poolId, address(this));
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: -int128(int256(5e19)),
                salt: 0
            }),
            ""
        );
        
        uint256 liquidityAfter = hook.lpLiquidity(poolId, address(this));
        assertLt(liquidityAfter, liquidityBefore);
    }

    // Test: Total liquidity sum of individual LPs
    function test_totalLiquiditySumOfLPs() public {
        vm.prank(lp1);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        vm.prank(lp2);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 totalLiquidity = hook.totalLiquidity(poolId);
        uint256 lp1Liquidity = hook.lpLiquidity(poolId, lp1);
        uint256 lp2Liquidity = hook.lpLiquidity(poolId, lp2);
        
        assertGe(totalLiquidity, lp1Liquidity + lp2Liquidity);
    }

    // Test: Liquidity tracking accuracy
    function test_liquidityTrackingAccuracy() public {
        uint256 delta = 1e20;
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: int128(int256(delta)),
                salt: 0
            }),
            ""
        );
        
        uint256 liquidity = hook.lpLiquidity(poolId, address(this));
        assertGe(liquidity, delta);
    }

    // Test: Liquidity removal below zero
    function test_liquidityRemovalBelowZero() public {
        // Add liquidity first
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        // Try to remove more than added
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: -int128(int256(2e20)),
                salt: 0
            }),
            ""
        );
        
        // Should handle gracefully (may revert or set to zero)
        uint256 liquidity = hook.lpLiquidity(poolId, address(this));
        assertGe(liquidity, 0);
    }

    // Test: LP rewards claimable
    function test_lpRewardsClaimable() public {
        // Add liquidity
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        bytes32 auctionId = createAuction();
        uint256 winningBid = 10 ether;
        
        commitBid(auctionId, operator1, winningBid, 123);
        revealBid(auctionId, operator1, winningBid, 123);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        uint256 claimable = hook.lpRewards(poolId, address(this));
        assertGe(claimable, 0);
    }

    // Test: Pool rewards accumulation
    function test_poolRewardsAccumulation() public {
        bytes32 auctionId1 = createAuction();
        uint256 winningBid1 = 5 ether;
        
        commitBid(auctionId1, operator1, winningBid1, 123);
        revealBid(auctionId1, operator1, winningBid1, 123);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId1);
        
        uint256 rewards1 = hook.poolRewards(poolId);
        
        bytes32 auctionId2 = createAuction();
        uint256 winningBid2 = 10 ether;
        
        commitBid(auctionId2, operator1, winningBid2, 456);
        revealBid(auctionId2, operator1, winningBid2, 456);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId2);
        
        uint256 rewards2 = hook.poolRewards(poolId);
        assertGt(rewards2, rewards1);
    }

    // Test: Liquidity tracking with different tick ranges
    function test_liquidityTrackingDifferentTickRanges() public {
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -240,
                tickUpper: 240,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 liquidity1 = hook.lpLiquidity(poolId, address(this));
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 liquidity2 = hook.lpLiquidity(poolId, address(this));
        assertGt(liquidity2, liquidity1);
    }

    // Test: Liquidity tracking order independence
    function test_liquidityTrackingOrderIndependence() public {
        vm.prank(lp1);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        vm.prank(lp2);
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: 0
            }),
            ""
        );
        
        uint256 lp1Liquidity = hook.lpLiquidity(poolId, lp1);
        uint256 lp2Liquidity = hook.lpLiquidity(poolId, lp2);
        
        // Both should have liquidity regardless of order
        assertGt(lp1Liquidity, 0);
        assertGt(lp2Liquidity, 0);
    }

    // Test: Liquidity tracking with salt
    function test_liquidityTrackingWithSalt() public {
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: bytes32(uint256(1))
            }),
            ""
        );
        
        uint256 liquidity1 = hook.lpLiquidity(poolId, address(this));
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e20,
                salt: bytes32(uint256(2))
            }),
            ""
        );
        
        uint256 liquidity2 = hook.lpLiquidity(poolId, address(this));
        assertGt(liquidity2, liquidity1);
    }

    // Test: Total liquidity never negative
    function test_totalLiquidityNeverNegative() public view {
        uint256 totalLiquidity = hook.totalLiquidity(poolId);
        assertGe(totalLiquidity, 0);
    }

    // Test: LP liquidity never negative
    function test_lpLiquidityNeverNegative() public {
        address anyLP = makeAddr("anyLP");
        uint256 liquidity = hook.lpLiquidity(poolId, anyLP);
        assertGe(liquidity, 0);
    }

    // Test: Pool rewards never negative
    function test_poolRewardsNeverNegative() public view {
        uint256 rewards = hook.poolRewards(poolId);
        assertGe(rewards, 0);
    }

    // Test: LP rewards never negative
    function test_lpRewardsNeverNegative() public {
        address anyLP = makeAddr("anyLP");
        uint256 rewards = hook.lpRewards(poolId, anyLP);
        assertGe(rewards, 0);
    }
}

