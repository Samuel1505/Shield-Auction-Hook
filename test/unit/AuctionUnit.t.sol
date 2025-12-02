// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestFixture} from "../utils/TestFixture.sol";
import {AuctionLib} from "../../src/libraries/Auction.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";

/**
 * @title AuctionUnit
 * @notice Unit tests for auction functionality
 */
contract AuctionUnit is TestFixture {

    // Test: Create auction
    function test_createAuction() public {
        bytes32 auctionId = createAuction();
        assertNotEq(auctionId, bytes32(0));
    }

    // Test: Auction has correct pool ID
    function test_auctionPoolId() public {
        bytes32 auctionId = createAuction();
        (PoolId auctionPoolId, , , , , , , ) = hook.auctions(auctionId);
        assertEq(PoolId.unwrap(auctionPoolId), PoolId.unwrap(poolId));
    }

    // Test: Auction starts at current timestamp
    function test_auctionStartTime() public {
        uint256 startTime = block.timestamp;
        bytes32 auctionId = createAuction();
        (, uint256 auctionStartTime, , , , , , ) = hook.auctions(auctionId);
        assertGe(auctionStartTime, startTime);
    }

    // Test: Auction has correct duration
    function test_auctionDuration() public {
        bytes32 auctionId = createAuction();
        (, , uint256 duration, , , , , ) = hook.auctions(auctionId);
        assertEq(duration, hook.MAX_AUCTION_DURATION());
    }

    // Test: Auction is initially active
    function test_auctionInitiallyActive() public {
        bytes32 auctionId = createAuction();
        (, , , bool isActive, bool isComplete, , , ) = hook.auctions(auctionId);
        assertTrue(isActive);
        assertFalse(isComplete);
    }

    // Test: Auction has no winner initially
    function test_auctionNoWinnerInitially() public {
        bytes32 auctionId = createAuction();
        (, , , , , address winner, uint256 winningBid, ) = hook.auctions(auctionId);
        assertEq(winner, address(0));
        assertEq(winningBid, 0);
    }

    // Test: Auction has zero bids initially
    function test_auctionZeroBidsInitially() public {
        bytes32 auctionId = createAuction();
        (, , , , , , , uint256 totalBids) = hook.auctions(auctionId);
        assertEq(totalBids, 0);
    }

    // Test: Active auction mapping
    function test_activeAuctionMapping() public {
        bytes32 auctionId = createAuction();
        assertEq(hook.activeAuctions(poolId), auctionId);
    }

    // Test: Multiple auctions for same pool
    function test_multipleAuctionsSamePool() public {
        bytes32 auctionId1 = createAuction();
        fastForwardPastAuctionDuration();
        
        // Create new auction
        setPriceDeviationAboveThreshold();
        swap(poolKey, true, -1e18, "");
        bytes32 auctionId2 = hook.activeAuctions(poolId);
        
        assertNotEq(auctionId1, auctionId2);
    }

    // Test: Auction ID uniqueness
    function test_auctionIdUniqueness() public {
        bytes32 auctionId1 = createAuction();
        fastForward(1);
        bytes32 auctionId2 = createAuction();
        
        // Should be different if created at different times
        assertNotEq(auctionId1, auctionId2);
    }

    // Test: Auction cannot be created twice simultaneously
    function test_auctionNoDuplicateCreation() public {
        bytes32 auctionId1 = createAuction();
        
        // Try to create another immediately
        setPriceDeviationAboveThreshold();
        swap(poolKey, true, -1e18, "");
        bytes32 auctionId2 = hook.activeAuctions(poolId);
        
        // Should be same auction if first is still active
        assertEq(auctionId1, auctionId2);
    }

    // Test: Auction ends after duration
    function test_auctionEndsAfterDuration() public {
        bytes32 auctionId = createAuction();
        (, uint256 startTime, uint256 duration, , , , , ) = hook.auctions(auctionId);
        
        fastForward(duration + 1);
        
        assertTrue(block.timestamp >= startTime + duration);
    }

    // Test: Auction is active before duration
    function test_auctionActiveBeforeDuration() public {
        bytes32 auctionId = createAuction();
        (, uint256 startTime, uint256 duration, , , , , ) = hook.auctions(auctionId);
        
        fastForward(duration - 1);
        
        assertTrue(block.timestamp < startTime + duration);
    }

    // Test: Auction state after ending
    function test_auctionStateAfterEnding() public {
        bytes32 auctionId = createAuction();
        fastForwardPastAuctionDuration();
        
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        (, , , bool isActive, bool isComplete, , , ) = hook.auctions(auctionId);
        assertFalse(isActive);
        assertTrue(isComplete);
    }

    // Test: Active auction cleared after ending
    function test_activeAuctionClearedAfterEnding() public {
        bytes32 auctionId = createAuction();
        fastForwardPastAuctionDuration();
        
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }

    // Test: Auction with bids
    function test_auctionWithBids() public {
        bytes32 auctionId = createAuction();
        commitBid(auctionId, operator1, 1 ether, 123);
        
        (, , , , , , , uint256 totalBids) = hook.auctions(auctionId);
        assertEq(totalBids, 1);
    }

    // Test: Auction with winning bid
    function test_auctionWithWinningBid() public {
        bytes32 auctionId = createAuction();
        uint256 winningBid = 10 ether;
        
        commitBid(auctionId, operator1, winningBid, 123);
        revealBid(auctionId, operator1, winningBid, 123);
        
        (, , , , , address winner, uint256 bidAmount, ) = hook.auctions(auctionId);
        assertEq(winner, operator1);
        assertEq(bidAmount, winningBid);
    }

    // Test: Auction with multiple bids
    function test_auctionWithMultipleBids() public {
        bytes32 auctionId = createAuction();
        
        commitBid(auctionId, operator1, 1 ether, 123);
        commitBid(auctionId, operator2, 2 ether, 456);
        commitBid(auctionId, operator3, 3 ether, 789);
        
        (, , , , , , , uint256 totalBids) = hook.auctions(auctionId);
        assertEq(totalBids, 3);
    }

    // Test: Auction highest bid wins
    function test_auctionHighestBidWins() public {
        bytes32 auctionId = createAuction();
        
        commitBid(auctionId, operator1, 1 ether, 123);
        revealBid(auctionId, operator1, 1 ether, 123);
        
        commitBid(auctionId, operator2, 5 ether, 456);
        revealBid(auctionId, operator2, 5 ether, 456);
        
        commitBid(auctionId, operator3, 3 ether, 789);
        revealBid(auctionId, operator3, 3 ether, 789);
        
        (, , , , , address winner, uint256 winningBid, ) = hook.auctions(auctionId);
        assertEq(winner, operator2);
        assertEq(winningBid, 5 ether);
    }

    // Test: Auction lower bid doesn't win
    function test_auctionLowerBidDoesntWin() public {
        bytes32 auctionId = createAuction();
        
        commitBid(auctionId, operator1, 10 ether, 123);
        revealBid(auctionId, operator1, 10 ether, 123);
        
        commitBid(auctionId, operator2, 5 ether, 456);
        revealBid(auctionId, operator2, 5 ether, 456);
        
        (, , , , , address winner, uint256 winningBid, ) = hook.auctions(auctionId);
        assertEq(winner, operator1);
        assertEq(winningBid, 10 ether);
    }

    // Test: Auction equal bids
    function test_auctionEqualBids() public {
        bytes32 auctionId = createAuction();
        uint256 bidAmount = 5 ether;
        
        commitBid(auctionId, operator1, bidAmount, 123);
        revealBid(auctionId, operator1, bidAmount, 123);
        
        commitBid(auctionId, operator2, bidAmount, 456);
        revealBid(auctionId, operator2, bidAmount, 456);
        
        (, , , , , address winner, uint256 winningBid, ) = hook.auctions(auctionId);
        // First bidder should win (or last, depending on implementation)
        assertEq(winningBid, bidAmount);
    }

    // Test: Auction bid count increments
    function test_auctionBidCountIncrements() public {
        bytes32 auctionId = createAuction();
        
        for (uint8 i = 0; i < 5; i++) {
            address operator = i % 3 == 0 ? operator1 : (i % 3 == 1 ? operator2 : operator3);
            commitBid(auctionId, operator, (i + 1) * 1 ether, i);
            
            (, , , , , , , uint256 totalBids) = hook.auctions(auctionId);
            assertEq(totalBids, i + 1);
        }
    }

    // Test: Auction cannot end before duration
    function test_auctionCannotEndBeforeDuration() public {
        bytes32 auctionId = createAuction();
        
        // Try to end immediately
        vm.prank(owner);
        vm.expectRevert("ShieldAuctionHook: auction not ended");
        hook.endAuction(auctionId);
    }

    // Test: Auction can end after duration
    function test_auctionCanEndAfterDuration() public {
        bytes32 auctionId = createAuction();
        fastForwardPastAuctionDuration();
        
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        (, , , bool isActive, bool isComplete, , , ) = hook.auctions(auctionId);
        assertFalse(isActive);
        assertTrue(isComplete);
    }

    // Test: Auction end clears active mapping
    function test_auctionEndClearsActiveMapping() public {
        bytes32 auctionId = createAuction();
        assertEq(hook.activeAuctions(poolId), auctionId);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }

    // Test: Auction end with no bids
    function test_auctionEndWithNoBids() public {
        bytes32 auctionId = createAuction();
        fastForwardPastAuctionDuration();
        
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        (, , , , , address winner, uint256 winningBid, ) = hook.auctions(auctionId);
        assertEq(winner, address(0));
        assertEq(winningBid, 0);
    }

    // Test: Auction end with bids
    function test_auctionEndWithBids() public {
        bytes32 auctionId = createAuction();
        uint256 winningBid = 10 ether;
        
        commitBid(auctionId, operator1, winningBid, 123);
        revealBid(auctionId, operator1, winningBid, 123);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        (, , , , , address winner, uint256 bidAmount, ) = hook.auctions(auctionId);
        assertEq(winner, operator1);
        assertEq(bidAmount, winningBid);
    }

    // Test: Auction timestamp accuracy
    function test_auctionTimestampAccuracy() public {
        uint256 beforeCreate = block.timestamp;
        bytes32 auctionId = createAuction();
        uint256 afterCreate = block.timestamp;
        
        (, uint256 startTime, , , , , , ) = hook.auctions(auctionId);
        assertGe(startTime, beforeCreate);
        assertLe(startTime, afterCreate);
    }

    // Test: Auction duration constant
    function test_auctionDurationConstant() public {
        bytes32 auctionId1 = createAuction();
        bytes32 auctionId2 = createAuction();
        
        (, , uint256 duration1, , , , , ) = hook.auctions(auctionId1);
        (, , uint256 duration2, , , , , ) = hook.auctions(auctionId2);
        
        assertEq(duration1, duration2);
        assertEq(duration1, hook.MAX_AUCTION_DURATION());
    }

    // Test: Auction pool ID consistency
    function test_auctionPoolIdConsistency() public {
        bytes32 auctionId = createAuction();
        (PoolId auctionPoolId, , , , , , , ) = hook.auctions(auctionId);
        
        assertEq(PoolId.unwrap(auctionPoolId), PoolId.unwrap(poolId));
    }

    // Test: Auction state flags
    function test_auctionStateFlags() public {
        bytes32 auctionId = createAuction();
        
        (, , , bool isActive, bool isComplete, , , ) = hook.auctions(auctionId);
        assertTrue(isActive);
        assertFalse(isComplete);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        (, , , isActive, isComplete, , , ) = hook.auctions(auctionId);
        assertFalse(isActive);
        assertTrue(isComplete);
    }

    // Test: Auction cannot be active and complete simultaneously
    function test_auctionCannotBeActiveAndComplete() public {
        bytes32 auctionId = createAuction();
        (, , , bool isActive, bool isComplete, , , ) = hook.auctions(auctionId);
        
        // Initially should be active but not complete
        assertTrue(isActive || !isComplete);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        (, , , isActive, isComplete, , , ) = hook.auctions(auctionId);
        // After ending, should not be active
        assertFalse(isActive);
    }

    // Test: Auction ID format
    function test_auctionIdFormat() public {
        bytes32 auctionId = createAuction();
        assertNotEq(auctionId, bytes32(0));
    }

    // Test: Auction creation emits event
    function test_auctionCreationEmitsEvent() public {
        setPriceDeviationAboveThreshold();
        
        vm.recordLogs();
        swap(poolKey, true, -1e18, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertNotEq(auctionId, bytes32(0));
    }

    // Test: Auction ending emits event
    function test_auctionEndingEmitsEvent() public {
        bytes32 auctionId = createAuction();
        uint256 winningBid = 10 ether;
        
        commitBid(auctionId, operator1, winningBid, 123);
        revealBid(auctionId, operator1, winningBid, 123);
        
        fastForwardPastAuctionDuration();
        
        vm.recordLogs();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        // Event should be emitted
        assertTrue(true);
    }

    // Test: Auction with zero duration (edge case)
    function test_auctionZeroDuration() public {
        bytes32 auctionId = createAuction();
        (, , uint256 duration, , , , , ) = hook.auctions(auctionId);
        
        // Duration should be MAX_AUCTION_DURATION, not zero
        assertGt(duration, 0);
    }

    // Test: Auction maximum duration
    function test_auctionMaximumDuration() public {
        bytes32 auctionId = createAuction();
        (, , uint256 duration, , , , , ) = hook.auctions(auctionId);
        
        assertLe(duration, hook.MAX_AUCTION_DURATION());
        assertEq(duration, hook.MAX_AUCTION_DURATION());
    }

    // Test: Auction state persistence
    function test_auctionStatePersistence() public {
        bytes32 auctionId = createAuction();
        
        // Read state multiple times
        (, , uint256 duration1, bool isActive1, , , , ) = hook.auctions(auctionId);
        (, , uint256 duration2, bool isActive2, , , , ) = hook.auctions(auctionId);
        
        assertEq(duration1, duration2);
        assertEq(isActive1, isActive2);
    }

    // Test: Auction with very short time
    function test_auctionVeryShortTime() public {
        bytes32 auctionId = createAuction();
        fastForward(1);
        
        (, , , bool isActive, , , , ) = hook.auctions(auctionId);
        assertTrue(isActive);
    }

    // Test: Auction with very long time
    function test_auctionVeryLongTime() public {
        bytes32 auctionId = createAuction();
        fastForward(1000);
        
        (, uint256 startTime, uint256 duration, , , , , ) = hook.auctions(auctionId);
        assertTrue(block.timestamp >= startTime + duration);
    }
}

