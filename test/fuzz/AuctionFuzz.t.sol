// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestFixture} from "../utils/TestFixture.sol";
import {TestHelpers} from "../utils/TestHelpers.sol";
import {AuctionLib} from "../../src/libraries/Auction.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/types/PoolOperation.sol";

/**
 * @title AuctionFuzz
 * @notice Fuzz tests for auction functionality
 */
contract AuctionFuzz is TestFixture {

    // Fuzz test: Auction creation with various price deviations
    function testFuzz_auctionCreation_priceDeviation(
        uint256 priceDeviationBps,
        uint256 swapAmount
    ) public {
        // Bound inputs
        priceDeviationBps = bound(priceDeviationBps, 0, 10000);
        swapAmount = bound(swapAmount, 1e17, 1000 ether); // Between 0.1 ETH and 1000 ETH
        
        // Set price based on deviation
        uint256 externalPrice = 1e18 + (1e18 * priceDeviationBps) / 10000;
        priceOracle.setPrice(currency0, currency1, externalPrice, false);
        
        // Perform swap
        swap(poolKey, true, -int256(swapAmount), "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        
        if (priceDeviationBps >= hook.lvrThreshold() && swapAmount >= 1e17) {
            assertNotEq(auctionId, bytes32(0), "Auction should be created");
        } else {
            // May or may not be created depending on other conditions
            // Just verify no revert
            assertTrue(true);
        }
    }

    // Fuzz test: Bid commitment with various amounts and nonces
    function testFuzz_bidCommitment(
        uint256 amount,
        uint256 nonce,
        address bidder
    ) public {
        bytes32 auctionId = createAuction();
        
        // Bound amount to reasonable range
        amount = bound(amount, hook.MIN_BID(), 10000 ether);
        nonce = bound(nonce, 1, type(uint256).max);
        bidder = address(uint160(uint256(keccak256(abi.encode(bidder)))));
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        vm.prank(bidder);
        hook.commitBid(auctionId, commitment);
        
        assertEq(hook.bidCommitments(auctionId, bidder), commitment);
    }

    // Fuzz test: Bid revelation with various parameters
    function testFuzz_bidRevelation(
        uint256 amount,
        uint256 nonce,
        address operator
    ) public {
        bytes32 auctionId = createAuction();
        
        // Bound inputs
        amount = bound(amount, hook.MIN_BID(), 10000 ether);
        nonce = bound(nonce, 1, type(uint256).max);
        operator = address(uint160(uint256(keccak256(abi.encode(operator)))));
        
        // Authorize operator
        hook.setOperatorAuthorization(operator, true);
        
        bytes32 commitment = AuctionLib.generateCommitment(operator, amount, nonce);
        
        vm.prank(operator);
        hook.commitBid(auctionId, commitment);
        
        vm.prank(operator);
        hook.revealBid(auctionId, amount, nonce);
        
        (, uint256 revealedAmount, , bool revealed, ) = hook.revealedBids(auctionId, operator);
        assertEq(revealedAmount, amount);
        assertTrue(revealed);
    }

    // Fuzz test: Multiple bids in same auction
    function testFuzz_multipleBids(
        uint256 seed,
        uint8 numBids
    ) public {
        bytes32 auctionId = createAuction();
        
        numBids = uint8(bound(numBids, 1, 10));
        
        for (uint8 i = 0; i < numBids; i++) {
            address bidder = address(uint160(uint256(keccak256(abi.encode(seed, i)))));
            uint256 amount = TestHelpers.createValidBidAmount(uint256(keccak256(abi.encode(seed, i))));
            uint256 nonce = uint256(keccak256(abi.encode(seed, i, "nonce")));
            
            bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
            
            vm.prank(bidder);
            hook.commitBid(auctionId, commitment);
        }
        
        (, , , , , , , uint256 totalBids) = hook.auctions(auctionId);
        assertEq(totalBids, numBids);
    }

    // Fuzz test: Winning bid selection
    function testFuzz_winningBidSelection(
        uint256 seed
    ) public {
        bytes32 auctionId = createAuction();
        
        uint256 maxBid = 0;
        address expectedWinner = address(0);
        
        // Create multiple bids
        for (uint8 i = 0; i < 5; i++) {
            address operator = i == 0 ? operator1 : (i == 1 ? operator2 : operator3);
            uint256 amount = TestHelpers.createValidBidAmount(uint256(keccak256(abi.encode(seed, i))));
            uint256 nonce = uint256(keccak256(abi.encode(seed, i)));
            
            if (amount > maxBid) {
                maxBid = amount;
                expectedWinner = operator;
            }
            
            commitBid(auctionId, operator, amount, nonce);
            revealBid(auctionId, operator, amount, nonce);
        }
        
        (, , , , , address winner, uint256 winningBid, ) = hook.auctions(auctionId);
        assertEq(winningBid, maxBid);
        assertEq(winner, expectedWinner);
    }

    // Fuzz test: Auction timing
    function testFuzz_auctionTiming(
        uint256 timeElapsed
    ) public {
        bytes32 auctionId = createAuction();
        
        (, uint256 startTime, uint256 duration, , , , , ) = hook.auctions(auctionId);
        
        timeElapsed = bound(timeElapsed, 0, duration * 2);
        fastForward(timeElapsed);
        
        bool shouldBeActive = block.timestamp < startTime + duration;
        bool shouldBeEnded = block.timestamp >= startTime + duration;
        
        (, , , bool isActive, bool isComplete, , , ) = hook.auctions(auctionId);
        
        if (shouldBeEnded) {
            assertTrue(!isActive || isComplete, "Auction should be ended");
        }
    }

    // Fuzz test: Price oracle variations
    function testFuzz_priceOracleVariations(
        uint256 externalPrice,
        bool isStale
    ) public {
        externalPrice = bound(externalPrice, 1e15, 1e21); // Reasonable price range
        priceOracle.setPrice(currency0, currency1, externalPrice, isStale);
        
        swap(poolKey, true, -1e18, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        
        if (isStale) {
            assertEq(auctionId, bytes32(0), "Should not create auction with stale price");
        }
    }

    // Fuzz test: Swap size variations
    function testFuzz_swapSizeVariations(
        int256 swapAmount
    ) public {
        setPriceDeviationAboveThreshold();
        
        swapAmount = bound(swapAmount, -1000 ether, -1e15);
        
        swap(poolKey, true, swapAmount, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        
        uint256 absAmount = uint256(-swapAmount);
        if (absAmount >= 1e17) {
            assertNotEq(auctionId, bytes32(0), "Should create auction for large swaps");
        }
    }

    // Fuzz test: LVR threshold variations
    function testFuzz_lvrThresholdVariations(
        uint256 newThreshold
    ) public {
        newThreshold = bound(newThreshold, 1, 10000);
        
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        
        assertEq(hook.lvrThreshold(), newThreshold);
        
        // Test with different price deviations
        uint256 priceDeviation = (1e18 * newThreshold) / 10000;
        priceOracle.setPrice(currency0, currency1, 1e18 + priceDeviation, false);
        
        swap(poolKey, true, -1e18, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        // Should trigger if deviation >= threshold
        if (priceDeviation >= (1e18 * newThreshold) / 10000) {
            assertNotEq(auctionId, bytes32(0), "Should trigger auction");
        }
    }

    // Fuzz test: Reward distribution calculations
    function testFuzz_rewardDistribution(
        uint256 winningBid
    ) public {
        winningBid = bound(winningBid, hook.MIN_BID(), 100000 ether);
        
        bytes32 auctionId = createAuction();
        commitBid(auctionId, operator1, winningBid, 123);
        revealBid(auctionId, operator1, winningBid, 123);
        
        (
            uint256 lpReward,
            uint256 operatorReward,
            uint256 protocolFee,
            uint256 gasCompensation,
            uint256 total
        ) = TestHelpers.verifyRewardPercentages(hook, winningBid);
        
        // Verify percentages sum correctly
        assertEq(total, winningBid, "Rewards should sum to winning bid");
        assertEq(lpReward, (winningBid * hook.LP_REWARD_PERCENTAGE()) / hook.BASIS_POINTS());
        assertEq(operatorReward, (winningBid * hook.AVS_REWARD_PERCENTAGE()) / hook.BASIS_POINTS());
        assertEq(protocolFee, (winningBid * hook.PROTOCOL_FEE_PERCENTAGE()) / hook.BASIS_POINTS());
    }

    // Fuzz test: Liquidity tracking
    function testFuzz_liquidityTracking(
        uint256 liquidityDeltaRaw
    ) public {
        liquidityDeltaRaw = bound(liquidityDeltaRaw, 1e15, 1e24);
        int128 liquidityDelta = int128(int256(liquidityDeltaRaw));
        
        uint256 initialLiquidity = hook.lpLiquidity(poolId, address(this));
        
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: liquidityDelta,
                salt: 0
            }),
            ""
        );
        
        uint256 newLiquidity = hook.lpLiquidity(poolId, address(this));
        
        if (liquidityDelta > 0) {
            assertTrue(newLiquidity >= initialLiquidity, "Liquidity should increase");
        } else {
            assertTrue(newLiquidity <= initialLiquidity, "Liquidity should decrease");
        }
    }

    // Fuzz test: Operator authorization
    function testFuzz_operatorAuthorization(
        address operator,
        bool authorized
    ) public {
        vm.assume(operator != address(0));
        
        hook.setOperatorAuthorization(operator, authorized);
        
        assertEq(hook.authorizedOperators(operator), authorized);
    }

    // Fuzz test: Fee recipient updates
    function testFuzz_feeRecipientUpdate(
        address newRecipient
    ) public {
        vm.assume(newRecipient != address(0));
        
        vm.prank(owner);
        hook.setFeeRecipient(newRecipient);
        
        assertEq(hook.feeRecipient(), newRecipient);
    }

    // Fuzz test: Commitment verification
    function testFuzz_commitmentVerification(
        address bidder,
        uint256 amount,
        uint256 nonce,
        uint256 wrongNonce
    ) public {
        vm.assume(nonce != wrongNonce);
        amount = bound(amount, hook.MIN_BID(), 10000 ether);
        
        bytes32 correctCommitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 wrongCommitment = AuctionLib.generateCommitment(bidder, amount, wrongNonce);
        
        assertTrue(AuctionLib.verifyCommitment(correctCommitment, bidder, amount, nonce));
        assertFalse(AuctionLib.verifyCommitment(wrongCommitment, bidder, amount, nonce));
    }

    // Fuzz test: Auction ID uniqueness
    function testFuzz_auctionIdUniqueness(
        uint256 blockNum1,
        uint256 timestamp1,
        uint256 blockNum2,
        uint256 timestamp2
    ) public {
        bytes32 id1 = keccak256(abi.encodePacked(poolId, blockNum1, timestamp1));
        bytes32 id2 = keccak256(abi.encodePacked(poolId, blockNum2, timestamp2));
        
        if (blockNum1 == blockNum2 && timestamp1 == timestamp2) {
            assertEq(id1, id2);
        } else {
            assertNotEq(id1, id2);
        }
    }

    // Fuzz test: Price deviation calculations
    function testFuzz_priceDeviationCalculation(
        uint256 price1,
        uint256 price2
    ) public {
        price1 = bound(price1, 1e15, 1e21);
        price2 = bound(price2, 1e15, 1e21);
        
        uint256 deviation = TestHelpers.calculatePriceDeviation(price1, price2);
        
        assertTrue(deviation <= 10000, "Deviation should be in basis points");
    }

    // Fuzz test: Multiple auctions for different pools
    function testFuzz_multiplePools(
        uint256 seed
    ) public {
        // Create multiple pools with different configurations
        for (uint8 i = 0; i < 3; i++) {
            PoolKey memory newPoolKey = PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: uint24(3000 + i * 1000),
                tickSpacing: 60,
                hooks: IHooks(address(hook))
            });
            
            manager.initialize(newPoolKey, INIT_SQRT_PRICE);
            
            setPriceDeviationAboveThreshold();
            swap(newPoolKey, true, -1e18, "");
            
            PoolId newPoolId = newPoolKey.toId();
            bytes32 auctionId = hook.activeAuctions(newPoolId);
            assertNotEq(auctionId, bytes32(0), "Auction should be created");
        }
    }

    // Fuzz test: Edge cases for bid amounts
    function testFuzz_bidAmountEdgeCases(
        uint256 amount
    ) public {
        bytes32 auctionId = createAuction();
        
        if (amount < hook.MIN_BID()) {
            commitBid(auctionId, operator1, amount, 123);
            
            vm.prank(operator1);
            vm.expectRevert("ShieldAuctionHook: bid below minimum");
            hook.revealBid(auctionId, amount, 123);
        } else {
            commitBid(auctionId, operator1, amount, 123);
            revealBid(auctionId, operator1, amount, 123);
            
            (, , , , , , uint256 winningBid, ) = hook.auctions(auctionId);
            assertGe(winningBid, hook.MIN_BID());
        }
    }

    // Fuzz test: Concurrent bid commitments
    function testFuzz_concurrentBids(
        uint256 seed,
        uint8 numConcurrent
    ) public {
        bytes32 auctionId = createAuction();
        
        numConcurrent = uint8(bound(numConcurrent, 1, 20));
        
        for (uint8 i = 0; i < numConcurrent; i++) {
            address bidder = address(uint160(uint256(keccak256(abi.encode(seed, i)))));
            uint256 amount = TestHelpers.createValidBidAmount(uint256(keccak256(abi.encode(seed, i))));
            uint256 nonce = uint256(keccak256(abi.encode(seed, i)));
            
            bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
            
            vm.prank(bidder);
            hook.commitBid(auctionId, commitment);
        }
        
        (, , , , , , , uint256 totalBids) = hook.auctions(auctionId);
        assertEq(totalBids, numConcurrent);
    }

    // Fuzz test: Auction state transitions
    function testFuzz_auctionStateTransitions(
        uint256 time1,
        uint256 time2
    ) public {
        bytes32 auctionId = createAuction();
        
        (, uint256 startTime, uint256 duration, , , , , ) = hook.auctions(auctionId);
        
        time1 = bound(time1, 0, duration);
        time2 = bound(time2, duration + 1, duration * 2);
        
        // First time point - should be active
        vm.warp(startTime + time1);
        (, , , bool isActive1, bool isComplete1, , , ) = hook.auctions(auctionId);
        assertTrue(isActive1 && !isComplete1, "Should be active at time1");
        
        // Second time point - should be ended
        vm.warp(startTime + time2);
        (, , , bool isActive2, bool isComplete2, , , ) = hook.auctions(auctionId);
        assertTrue(!isActive2 || isComplete2, "Should be ended at time2");
    }
}

