// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestFixture} from "../utils/TestFixture.sol";
import {TestHelpers} from "../utils/TestHelpers.sol";
import {AuctionLib} from "../../src/libraries/Auction.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";

/**
 * @title AuctionInvariants
 * @notice Invariant tests for auction system
 */
contract AuctionInvariants is TestFixture {

    // Invariant: Total reward percentages always sum to BASIS_POINTS
    function test_invariant_rewardPercentagesSum() public view {
        uint256 total = hook.LP_REWARD_PERCENTAGE() + 
                       hook.AVS_REWARD_PERCENTAGE() + 
                       hook.PROTOCOL_FEE_PERCENTAGE() + 
                       hook.GAS_COMPENSATION_PERCENTAGE();
        assertEq(total, hook.BASIS_POINTS());
    }

    // Invariant: MIN_BID is always positive
    function test_invariant_minBidPositive() public view {
        assertGt(hook.MIN_BID(), 0);
    }

    // Invariant: MAX_AUCTION_DURATION is always positive
    function test_invariant_maxAuctionDurationPositive() public view {
        assertGt(hook.MAX_AUCTION_DURATION(), 0);
    }

    // Invariant: LVR threshold is within valid range
    function test_invariant_lvrThresholdRange() public view {
        assertGe(hook.lvrThreshold(), 1);
        assertLe(hook.lvrThreshold(), 10000);
    }

    // Invariant: Fee recipient is never zero address
    function test_invariant_feeRecipientNotZero() public view {
        assertNotEq(hook.feeRecipient(), address(0));
    }

    // Invariant: Active auction count consistency
    function test_invariant_activeAuctionCountConsistency() public {
        bytes32 auctionId = createAuction();
        assertNotEq(auctionId, bytes32(0));
        
        bytes32 activeAuction = hook.activeAuctions(poolId);
        assertEq(activeAuction, auctionId);
    }

    // Invariant: Auction cannot be active and complete simultaneously
    function test_invariant_auctionNotActiveAndComplete() public {
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

    // Invariant: Winning bid is always >= MIN_BID
    function test_invariant_winningBidAboveMinimum() public {
        bytes32 auctionId = createAuction();
        uint256 amount = hook.MIN_BID();
        
        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);
        
        (, , , , , , uint256 winningBid, ) = hook.auctions(auctionId);
        assertGe(winningBid, hook.MIN_BID());
    }

    // Invariant: Total bids count matches actual bids
    function test_invariant_totalBidsCountMatches() public {
        bytes32 auctionId = createAuction();
        
        commitBid(auctionId, operator1, 1 ether, 123);
        commitBid(auctionId, operator2, 2 ether, 456);
        commitBid(auctionId, operator3, 3 ether, 789);
        
        (, , , , , , , uint256 totalBids) = hook.auctions(auctionId);
        assertEq(totalBids, 3);
    }

    // Invariant: Auction duration is always MAX_AUCTION_DURATION
    function test_invariant_auctionDurationConstant() public {
        bytes32 auctionId1 = createAuction();
        bytes32 auctionId2 = createAuction();
        
        (, , uint256 duration1, , , , , ) = hook.auctions(auctionId1);
        (, , uint256 duration2, , , , , ) = hook.auctions(auctionId2);
        
        assertEq(duration1, hook.MAX_AUCTION_DURATION());
        assertEq(duration2, hook.MAX_AUCTION_DURATION());
        assertEq(duration1, duration2);
    }

    // Invariant: Auction start time is always <= current time
    function test_invariant_auctionStartTimeValid() public {
        bytes32 auctionId = createAuction();
        (, uint256 startTime, , , , , , ) = hook.auctions(auctionId);
        
        assertLe(startTime, block.timestamp);
    }

    // Invariant: Winning bid is highest revealed bid
    function test_invariant_winningBidIsHighest() public {
        bytes32 auctionId = createAuction();
        
        commitBid(auctionId, operator1, 1 ether, 123);
        revealBid(auctionId, operator1, 1 ether, 123);
        
        commitBid(auctionId, operator2, 5 ether, 456);
        revealBid(auctionId, operator2, 5 ether, 456);
        
        commitBid(auctionId, operator3, 3 ether, 789);
        revealBid(auctionId, operator3, 3 ether, 789);
        
        (, , , , , , uint256 winningBid, ) = hook.auctions(auctionId);
        assertEq(winningBid, 5 ether);
    }

    // Invariant: Revealed bid amount matches commitment
    function test_invariant_revealedBidMatchesCommitment() public {
        bytes32 auctionId = createAuction();
        uint256 amount = 1 ether;
        uint256 nonce = 123;
        
        bytes32 commitment = AuctionLib.generateCommitment(operator1, amount, nonce);
        commitBid(auctionId, operator1, amount, nonce);
        
        assertTrue(AuctionLib.verifyCommitment(commitment, operator1, amount, nonce));
        
        revealBid(auctionId, operator1, amount, nonce);
        
        (, uint256 revealedAmount, , bool revealed, ) = hook.revealedBids(auctionId, operator1);
        assertEq(revealedAmount, amount);
        assertTrue(revealed);
    }

    // Invariant: Pool ID consistency in auction
    function test_invariant_poolIdConsistency() public {
        bytes32 auctionId = createAuction();
        (PoolId auctionPoolId, , , , , , , ) = hook.auctions(auctionId);
        
        assertEq(PoolId.unwrap(auctionPoolId), PoolId.unwrap(poolId));
    }

    // Invariant: Bid commitment storage persistence
    function test_invariant_bidCommitmentPersistence() public {
        bytes32 auctionId = createAuction();
        bytes32 commitment = AuctionLib.generateCommitment(operator1, 1 ether, 123);
        
        vm.prank(operator1);
        hook.commitBid(auctionId, commitment);
        
        bytes32 storedCommitment1 = hook.bidCommitments(auctionId, operator1);
        bytes32 storedCommitment2 = hook.bidCommitments(auctionId, operator1);
        
        assertEq(storedCommitment1, storedCommitment2);
        assertEq(storedCommitment1, commitment);
    }

    // Invariant: Reward distribution doesn't exceed winning bid
    function test_invariant_rewardDistributionNotExceedBid() public {
        bytes32 auctionId = createAuction();
        uint256 winningBid = 10 ether;
        
        commitBid(auctionId, operator1, winningBid, 123);
        revealBid(auctionId, operator1, winningBid, 123);
        
        (
            uint256 lpReward,
            uint256 operatorReward,
            uint256 protocolFee,
            uint256 gasCompensation,
            uint256 total
        ) = TestHelpers.verifyRewardPercentages(hook, winningBid);
        
        assertLe(total, winningBid);
        assertLe(lpReward, winningBid);
        assertLe(operatorReward, winningBid);
        assertLe(protocolFee, winningBid);
        assertLe(gasCompensation, winningBid);
    }

    // Invariant: LP reward is largest percentage
    function test_invariant_lpRewardLargest() public view {
        assertGt(hook.LP_REWARD_PERCENTAGE(), hook.AVS_REWARD_PERCENTAGE());
        assertGt(hook.LP_REWARD_PERCENTAGE(), hook.PROTOCOL_FEE_PERCENTAGE());
        assertGt(hook.LP_REWARD_PERCENTAGE(), hook.GAS_COMPENSATION_PERCENTAGE());
    }

    // Invariant: Constants don't change
    function test_invariant_constantsImmutable() public view {
        uint256 minBid1 = hook.MIN_BID();
        uint256 minBid2 = hook.MIN_BID();
        assertEq(minBid1, minBid2);
        
        uint256 maxDuration1 = hook.MAX_AUCTION_DURATION();
        uint256 maxDuration2 = hook.MAX_AUCTION_DURATION();
        assertEq(maxDuration1, maxDuration2);
    }

    // Invariant: Auction ID uniqueness
    function test_invariant_auctionIdUniqueness() public {
        bytes32 auctionId1 = createAuction();
        fastForward(1);
        bytes32 auctionId2 = createAuction();
        
        // Should be different if created at different times
        assertNotEq(auctionId1, auctionId2);
    }

    // Invariant: Only one active auction per pool
    function test_invariant_oneActiveAuctionPerPool() public {
        bytes32 auctionId1 = createAuction();
        bytes32 activeAuction = hook.activeAuctions(poolId);
        assertEq(activeAuction, auctionId1);
        
        // Try to create another immediately
        setPriceDeviationAboveThreshold();
        swap(poolKey, true, -1e18, "");
        bytes32 activeAuction2 = hook.activeAuctions(poolId);
        
        // Should be same if first is still active
        assertEq(activeAuction, activeAuction2);
    }

    // Invariant: Bid count increments correctly
    function test_invariant_bidCountIncrements() public {
        bytes32 auctionId = createAuction();
        
        (, , , , , , , uint256 totalBids0) = hook.auctions(auctionId);
        assertEq(totalBids0, 0);
        
        commitBid(auctionId, operator1, 1 ether, 123);
        (, , , , , , , uint256 totalBids1) = hook.auctions(auctionId);
        assertEq(totalBids1, 1);
        
        commitBid(auctionId, operator2, 2 ether, 456);
        (, , , , , , , uint256 totalBids2) = hook.auctions(auctionId);
        assertEq(totalBids2, 2);
    }

    // Invariant: Winner is always a bidder who revealed
    function test_invariant_winnerIsRevealedBidder() public {
        bytes32 auctionId = createAuction();
        
        commitBid(auctionId, operator1, 10 ether, 123);
        revealBid(auctionId, operator1, 10 ether, 123);
        
        commitBid(auctionId, operator2, 5 ether, 456);
        // Don't reveal operator2's bid
        
        (, , , , , address winner, , ) = hook.auctions(auctionId);
        assertEq(winner, operator1); // Should be operator1 who revealed
    }

    // Invariant: Auction state transitions are valid
    function test_invariant_auctionStateTransitions() public {
        bytes32 auctionId = createAuction();
        
        // Initially active
        (, , , bool isActive1, bool isComplete1, , , ) = hook.auctions(auctionId);
        assertTrue(isActive1);
        assertFalse(isComplete1);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        // After ending, should be complete
        (, , , bool isActive2, bool isComplete2, , , ) = hook.auctions(auctionId);
        assertFalse(isActive2);
        assertTrue(isComplete2);
    }

    // Invariant: Revealed bid timestamp is valid
    function test_invariant_revealedBidTimestampValid() public {
        bytes32 auctionId = createAuction();
        uint256 beforeReveal = block.timestamp;
        
        commitBid(auctionId, operator1, 1 ether, 123);
        revealBid(auctionId, operator1, 1 ether, 123);
        
        uint256 afterReveal = block.timestamp;
        (, , , , uint256 timestamp) = hook.revealedBids(auctionId, operator1);
        
        assertGe(timestamp, beforeReveal);
        assertLe(timestamp, afterReveal);
    }

    // Invariant: Commitment hash uniqueness
    function test_invariant_commitmentHashUniqueness() public {
        bytes32 commitment1 = AuctionLib.generateCommitment(operator1, 1 ether, 123);
        bytes32 commitment2 = AuctionLib.generateCommitment(operator2, 2 ether, 456);
        
        assertNotEq(commitment1, commitment2);
    }

    // Invariant: Same parameters produce same commitment
    function test_invariant_sameParametersSameCommitment() public {
        bytes32 commitment1 = AuctionLib.generateCommitment(operator1, 1 ether, 123);
        bytes32 commitment2 = AuctionLib.generateCommitment(operator1, 1 ether, 123);
        
        assertEq(commitment1, commitment2);
    }

    // Invariant: Reward percentages are non-zero
    function test_invariant_rewardPercentagesNonZero() public view {
        assertGt(hook.LP_REWARD_PERCENTAGE(), 0);
        assertGt(hook.AVS_REWARD_PERCENTAGE(), 0);
        assertGt(hook.PROTOCOL_FEE_PERCENTAGE(), 0);
        assertGt(hook.GAS_COMPENSATION_PERCENTAGE(), 0);
    }

    // Invariant: BASIS_POINTS is standard value
    function test_invariant_basisPointsStandard() public view {
        assertEq(hook.BASIS_POINTS(), 10000);
    }

    // Invariant: Auction cannot be ended before duration
    function test_invariant_auctionCannotEndBeforeDuration() public {
        bytes32 auctionId = createAuction();
        
        vm.prank(owner);
        vm.expectRevert("ShieldAuctionHook: auction not ended");
        hook.endAuction(auctionId);
    }

    // Invariant: Active auction cleared after ending
    function test_invariant_activeAuctionClearedAfterEnding() public {
        bytes32 auctionId = createAuction();
        assertEq(hook.activeAuctions(poolId), auctionId);
        
        fastForwardPastAuctionDuration();
        vm.prank(owner);
        hook.endAuction(auctionId);
        
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }

    // Invariant: Winning bid updates correctly
    function test_invariant_winningBidUpdatesCorrectly() public {
        bytes32 auctionId = createAuction();
        
        commitBid(auctionId, operator1, 1 ether, 123);
        revealBid(auctionId, operator1, 1 ether, 123);
        
        (, , , , , , uint256 winningBid1, ) = hook.auctions(auctionId);
        assertEq(winningBid1, 1 ether);
        
        commitBid(auctionId, operator2, 10 ether, 456);
        revealBid(auctionId, operator2, 10 ether, 456);
        
        (, , , , , , uint256 winningBid2, ) = hook.auctions(auctionId);
        assertEq(winningBid2, 10 ether);
        assertGt(winningBid2, winningBid1);
    }

    // Invariant: Lower bid doesn't update winner
    function test_invariant_lowerBidDoesntUpdateWinner() public {
        bytes32 auctionId = createAuction();
        
        commitBid(auctionId, operator1, 10 ether, 123);
        revealBid(auctionId, operator1, 10 ether, 123);
        
        commitBid(auctionId, operator2, 5 ether, 456);
        revealBid(auctionId, operator2, 5 ether, 456);
        
        (, , , , , address winner, uint256 winningBid, ) = hook.auctions(auctionId);
        assertEq(winner, operator1);
        assertEq(winningBid, 10 ether);
    }

    // Invariant: Auction duration is reasonable
    function test_invariant_auctionDurationReasonable() public view {
        assertLe(hook.MAX_AUCTION_DURATION(), 60); // Should be less than a minute
    }

    // Invariant: MIN_BID is reasonable
    function test_invariant_minBidReasonable() public view {
        assertLt(hook.MIN_BID(), 1 ether); // Should be less than 1 ETH
    }

    // Invariant: Owner is set correctly
    function test_invariant_ownerSetCorrectly() public view {
        assertEq(hook.owner(), owner);
        assertNotEq(hook.owner(), address(0));
    }

    // Invariant: AVS directory is set correctly
    function test_invariant_avsDirectorySetCorrectly() public view {
        assertEq(address(hook.avsDirectory()), address(avsDirectory));
    }

    // Invariant: Price oracle is set correctly
    function test_invariant_priceOracleSetCorrectly() public view {
        assertEq(address(hook.priceOracle()), address(priceOracle));
    }

    // Invariant: AVS address is set correctly
    function test_invariant_avsAddressSetCorrectly() public view {
        assertEq(hook.avsAddress(), AVS_ADDRESS);
    }

    // Invariant: Pool manager is set correctly
    function test_invariant_poolManagerSetCorrectly() public view {
        assertEq(address(hook.poolManager()), address(manager));
    }
}

