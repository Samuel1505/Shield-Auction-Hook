// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { TestFixture } from "./TestFixture.sol";
import { AuctionLib } from "../../src/libraries/Auction.sol";

/**
 * @title BidUnit
 * @notice Unit tests for bid functionality
 */
contract BidUnit is TestFixture {
    // Test: Commit bid
    function test_commitBid() public {
        bytes32 auctionId = createAuction();
        bytes32 commitment = AuctionLib.generateCommitment(operator1, 1 ether, 123);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment);

        assertEq(hook.bidCommitments(auctionId, operator1), commitment);
    }

    // Test: Commit bid increments total bids
    function test_commitBidIncrementsTotalBids() public {
        bytes32 auctionId = createAuction();

        commitBid(auctionId, operator1, 1 ether, 123);
        (,,,,,,, uint256 totalBids) = hook.auctions(auctionId);
        assertEq(totalBids, 1);

        commitBid(auctionId, operator2, 2 ether, 456);
        (,,,,,,, totalBids) = hook.auctions(auctionId);
        assertEq(totalBids, 2);
    }

    // Test: Cannot commit bid twice
    function test_cannotCommitBidTwice() public {
        bytes32 auctionId = createAuction();
        bytes32 commitment = AuctionLib.generateCommitment(operator1, 1 ether, 123);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment);

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: bid already committed");
        hook.commitBid(auctionId, commitment);
    }

    // Test: Cannot commit bid to inactive auction
    function test_cannotCommitBidToInactiveAuction() public {
        bytes32 auctionId = createAuction();
        fastForwardPastAuctionDuration();

        bytes32 commitment = AuctionLib.generateCommitment(operator1, 1 ether, 123);
        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: auction not active");
        hook.commitBid(auctionId, commitment);
    }

    // Test: Reveal bid
    function test_revealBid() public {
        bytes32 auctionId = createAuction();
        uint256 amount = 1 ether;
        uint256 nonce = 123;

        commitBid(auctionId, operator1, amount, nonce);
        revealBid(auctionId, operator1, amount, nonce);

        (, uint256 revealedAmount,, bool revealed,) = hook.revealedBids(auctionId, operator1);
        assertEq(revealedAmount, amount);
        assertTrue(revealed);
    }

    // Test: Reveal bid updates winning bid
    function test_revealBidUpdatesWinningBid() public {
        bytes32 auctionId = createAuction();
        uint256 amount = 5 ether;

        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        (,,,,, address winner, uint256 winningBid,) = hook.auctions(auctionId);
        assertEq(winner, operator1);
        assertEq(winningBid, amount);
    }

    // Test: Reveal bid with higher amount updates winner
    function test_revealBidHigherAmountUpdatesWinner() public {
        bytes32 auctionId = createAuction();

        commitBid(auctionId, operator1, 1 ether, 123);
        revealBid(auctionId, operator1, 1 ether, 123);

        commitBid(auctionId, operator2, 10 ether, 456);
        revealBid(auctionId, operator2, 10 ether, 456);

        (,,,,, address winner, uint256 winningBid,) = hook.auctions(auctionId);
        assertEq(winner, operator2);
        assertEq(winningBid, 10 ether);
    }

    // Test: Reveal bid with lower amount doesn't update winner
    function test_revealBidLowerAmountDoesntUpdateWinner() public {
        bytes32 auctionId = createAuction();

        commitBid(auctionId, operator1, 10 ether, 123);
        revealBid(auctionId, operator1, 10 ether, 123);

        commitBid(auctionId, operator2, 1 ether, 456);
        revealBid(auctionId, operator2, 1 ether, 456);

        (,,,,, address winner, uint256 winningBid,) = hook.auctions(auctionId);
        assertEq(winner, operator1);
        assertEq(winningBid, 10 ether);
    }

    // Test: Cannot reveal without commitment
    function test_cannotRevealWithoutCommitment() public {
        bytes32 auctionId = createAuction();

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: no commitment found");
        hook.revealBid(auctionId, 1 ether, 123);
    }

    // Test: Cannot reveal with wrong nonce
    function test_cannotRevealWithWrongNonce() public {
        bytes32 auctionId = createAuction();
        commitBid(auctionId, operator1, 1 ether, 123);

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: invalid commitment");
        hook.revealBid(auctionId, 1 ether, 999);
    }

    // Test: Cannot reveal with wrong amount
    function test_cannotRevealWithWrongAmount() public {
        bytes32 auctionId = createAuction();
        commitBid(auctionId, operator1, 1 ether, 123);

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: invalid commitment");
        hook.revealBid(auctionId, 2 ether, 123);
    }

    // Test: Cannot reveal bid below minimum
    function test_cannotRevealBidBelowMinimum() public {
        bytes32 auctionId = createAuction();
        uint256 amount = hook.MIN_BID() - 1;

        commitBid(auctionId, operator1, amount, 123);

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: bid below minimum");
        hook.revealBid(auctionId, amount, 123);
    }

    // Test: Cannot reveal bid twice
    function test_cannotRevealBidTwice() public {
        bytes32 auctionId = createAuction();
        uint256 amount = 1 ether;

        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: bid already revealed");
        hook.revealBid(auctionId, amount, 123);
    }

    // Test: Cannot reveal bid to inactive auction
    function test_cannotRevealBidToInactiveAuction() public {
        bytes32 auctionId = createAuction();
        commitBid(auctionId, operator1, 1 ether, 123);

        fastForwardPastAuctionDuration();

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: auction not active");
        hook.revealBid(auctionId, 1 ether, 123);
    }

    // Test: Commitment hash generation
    function test_commitmentHashGeneration() public {
        address bidder = operator1;
        uint256 amount = 1 ether;
        uint256 nonce = 123;

        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        assertNotEq(commitment, bytes32(0));
    }

    // Test: Commitment verification
    function test_commitmentVerification() public {
        address bidder = operator1;
        uint256 amount = 1 ether;
        uint256 nonce = 123;

        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        assertTrue(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce));
    }

    // Test: Commitment verification fails with wrong bidder
    function test_commitmentVerificationWrongBidder() public {
        uint256 amount = 1 ether;
        uint256 nonce = 123;

        bytes32 commitment = AuctionLib.generateCommitment(operator1, amount, nonce);
        assertFalse(AuctionLib.verifyCommitment(commitment, operator2, amount, nonce));
    }

    // Test: Commitment verification fails with wrong amount
    function test_commitmentVerificationWrongAmount() public {
        address bidder = operator1;
        uint256 nonce = 123;

        bytes32 commitment = AuctionLib.generateCommitment(bidder, 1 ether, nonce);
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, 2 ether, nonce));
    }

    // Test: Commitment verification fails with wrong nonce
    function test_commitmentVerificationWrongNonce() public {
        address bidder = operator1;
        uint256 amount = 1 ether;

        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, 123);
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount, 456));
    }

    // Test: Multiple commitments from different bidders
    function test_multipleCommitmentsDifferentBidders() public {
        bytes32 auctionId = createAuction();

        bytes32 commitment1 = AuctionLib.generateCommitment(operator1, 1 ether, 123);
        bytes32 commitment2 = AuctionLib.generateCommitment(operator2, 2 ether, 456);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment1);

        vm.prank(operator2);
        hook.commitBid(auctionId, commitment2);

        assertEq(hook.bidCommitments(auctionId, operator1), commitment1);
        assertEq(hook.bidCommitments(auctionId, operator2), commitment2);
    }

    // Test: Bid commitment storage
    function test_bidCommitmentStorage() public {
        bytes32 auctionId = createAuction();
        bytes32 commitment = AuctionLib.generateCommitment(operator1, 1 ether, 123);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment);

        assertEq(hook.bidCommitments(auctionId, operator1), commitment);
        assertEq(hook.bidCommitments(auctionId, operator2), bytes32(0));
    }

    // Test: Revealed bid storage
    function test_revealedBidStorage() public {
        bytes32 auctionId = createAuction();
        uint256 amount = 1 ether;

        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        (address bidder, uint256 bidAmount, bytes32 commitment, bool revealed, uint256 timestamp) =
            hook.revealedBids(auctionId, operator1);

        assertEq(bidder, operator1);
        assertEq(bidAmount, amount);
        assertTrue(revealed);
        assertGt(timestamp, 0);
    }

    // Test: Revealed bid timestamp
    function test_revealedBidTimestamp() public {
        bytes32 auctionId = createAuction();
        uint256 beforeReveal = block.timestamp;

        commitBid(auctionId, operator1, 1 ether, 123);
        revealBid(auctionId, operator1, 1 ether, 123);

        uint256 afterReveal = block.timestamp;
        (,,,, uint256 timestamp) = hook.revealedBids(auctionId, operator1);

        assertGe(timestamp, beforeReveal);
        assertLe(timestamp, afterReveal);
    }

    // Test: Bid commitment uniqueness
    function test_bidCommitmentUniqueness() public {
        bytes32 commitment1 = AuctionLib.generateCommitment(operator1, 1 ether, 123);
        bytes32 commitment2 = AuctionLib.generateCommitment(operator1, 1 ether, 456);

        assertNotEq(commitment1, commitment2);
    }

    // Test: Same commitment with same parameters
    function test_sameCommitmentSameParameters() public {
        bytes32 commitment1 = AuctionLib.generateCommitment(operator1, 1 ether, 123);
        bytes32 commitment2 = AuctionLib.generateCommitment(operator1, 1 ether, 123);

        assertEq(commitment1, commitment2);
    }

    // Test: Bid amount minimum
    function test_bidAmountMinimum() public {
        bytes32 auctionId = createAuction();
        uint256 minBid = hook.MIN_BID();

        commitBid(auctionId, operator1, minBid, 123);
        revealBid(auctionId, operator1, minBid, 123);

        (, uint256 revealedAmount,,,) = hook.revealedBids(auctionId, operator1);
        assertEq(revealedAmount, minBid);
    }

    // Test: Bid amount above minimum
    function test_bidAmountAboveMinimum() public {
        bytes32 auctionId = createAuction();
        uint256 amount = hook.MIN_BID() * 2;

        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        (, uint256 revealedAmount,,,) = hook.revealedBids(auctionId, operator1);
        assertEq(revealedAmount, amount);
    }

    // Test: Winning bid persistence
    function test_winningBidPersistence() public {
        bytes32 auctionId = createAuction();
        uint256 amount = 10 ether;

        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        (,,,,, address winner1, uint256 winningBid1,) = hook.auctions(auctionId);

        // Add lower bid
        commitBid(auctionId, operator2, 5 ether, 456);
        revealBid(auctionId, operator2, 5 ether, 456);

        (,,,,, address winner2, uint256 winningBid2,) = hook.auctions(auctionId);

        assertEq(winner1, winner2);
        assertEq(winningBid1, winningBid2);
        assertEq(winningBid1, amount);
    }

    // Test: Equal bids - first wins
    function test_equalBidsFirstWins() public {
        bytes32 auctionId = createAuction();
        uint256 amount = 5 ether;

        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        commitBid(auctionId, operator2, amount, 456);
        revealBid(auctionId, operator2, amount, 456);

        (,,,,, address winner, uint256 winningBid,) = hook.auctions(auctionId);
        assertEq(winningBid, amount);
        // Winner should be operator1 (first one)
        assertEq(winner, operator1);
    }

    // Test: Bid commitment before reveal
    function test_bidCommitmentBeforeReveal() public {
        bytes32 auctionId = createAuction();
        bytes32 commitment = AuctionLib.generateCommitment(operator1, 1 ether, 123);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment);

        (
            address bidderAddr,
            uint256 bidAmt,
            bytes32 commitmentVal,
            bool revealed,
            uint256 timestamp
        ) = hook.revealedBids(auctionId, operator1);
        assertFalse(revealed);
    }

    // Test: Bid commitment after reveal
    function test_bidCommitmentAfterReveal() public {
        bytes32 auctionId = createAuction();
        uint256 amount = 1 ether;

        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        bytes32 commitment = hook.bidCommitments(auctionId, operator1);
        assertNotEq(commitment, bytes32(0));
    }

    // Test: Multiple reveals same auction
    function test_multipleRevealsSameAuction() public {
        bytes32 auctionId = createAuction();

        commitBid(auctionId, operator1, 1 ether, 123);
        revealBid(auctionId, operator1, 1 ether, 123);

        commitBid(auctionId, operator2, 2 ether, 456);
        revealBid(auctionId, operator2, 2 ether, 456);

        commitBid(auctionId, operator3, 3 ether, 789);
        revealBid(auctionId, operator3, 3 ether, 789);

        (,,,,, address winner, uint256 winningBid,) = hook.auctions(auctionId);
        assertEq(winner, operator3);
        assertEq(winningBid, 3 ether);
    }

    // Test: Bid commitment hash collision resistance
    function test_bidCommitmentHashCollisionResistance() public {
        bytes32 commitment1 = AuctionLib.generateCommitment(operator1, 1 ether, 123);
        bytes32 commitment2 = AuctionLib.generateCommitment(operator2, 2 ether, 456);

        // Very low probability of collision
        assertNotEq(commitment1, commitment2);
    }

    // Test: Bid commitment with zero amount
    function test_bidCommitmentZeroAmount() public {
        bytes32 auctionId = createAuction();
        bytes32 commitment = AuctionLib.generateCommitment(operator1, 0, 123);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment);

        // Should commit but reveal will fail
        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: bid below minimum");
        hook.revealBid(auctionId, 0, 123);
    }

    // Test: Bid commitment with maximum amount
    function test_bidCommitmentMaximumAmount() public {
        bytes32 auctionId = createAuction();
        uint256 maxAmount = type(uint128).max;

        commitBid(auctionId, operator1, maxAmount, 123);
        revealBid(auctionId, operator1, maxAmount, 123);

        (, uint256 revealedAmount,,,) = hook.revealedBids(auctionId, operator1);
        assertEq(revealedAmount, maxAmount);
    }

    // Test: Bid commitment with zero nonce
    function test_bidCommitmentZeroNonce() public {
        bytes32 auctionId = createAuction();
        bytes32 commitment = AuctionLib.generateCommitment(operator1, 1 ether, 0);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment);

        revealBid(auctionId, operator1, 1 ether, 0);

        (, uint256 revealedAmount,,,) = hook.revealedBids(auctionId, operator1);
        assertEq(revealedAmount, 1 ether);
    }

    // Test: Bid commitment with maximum nonce
    function test_bidCommitmentMaximumNonce() public {
        bytes32 auctionId = createAuction();
        uint256 maxNonce = type(uint256).max;
        bytes32 commitment = AuctionLib.generateCommitment(operator1, 1 ether, maxNonce);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment);

        revealBid(auctionId, operator1, 1 ether, maxNonce);

        (, uint256 revealedAmount,,,) = hook.revealedBids(auctionId, operator1);
        assertEq(revealedAmount, 1 ether);
    }

    // Test: Bid commitment order independence
    function test_bidCommitmentOrderIndependence() public {
        bytes32 auctionId = createAuction();

        commitBid(auctionId, operator1, 1 ether, 123);
        commitBid(auctionId, operator2, 2 ether, 456);
        commitBid(auctionId, operator3, 3 ether, 789);

        revealBid(auctionId, operator3, 3 ether, 789);
        revealBid(auctionId, operator1, 1 ether, 123);
        revealBid(auctionId, operator2, 2 ether, 456);

        (,,,,, address winner, uint256 winningBid,) = hook.auctions(auctionId);
        assertEq(winner, operator3);
        assertEq(winningBid, 3 ether);
    }

    // Test: Bid commitment storage persistence
    function test_bidCommitmentStoragePersistence() public {
        bytes32 auctionId = createAuction();
        bytes32 commitment = AuctionLib.generateCommitment(operator1, 1 ether, 123);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment);

        // Read multiple times
        bytes32 commitment1 = hook.bidCommitments(auctionId, operator1);
        bytes32 commitment2 = hook.bidCommitments(auctionId, operator1);

        assertEq(commitment1, commitment2);
        assertEq(commitment1, commitment);
    }

    // Test: Revealed bid storage persistence
    function test_revealedBidStoragePersistence() public {
        bytes32 auctionId = createAuction();
        uint256 amount = 1 ether;

        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        // Read multiple times
        (, uint256 amount1,, bool revealed1,) = hook.revealedBids(auctionId, operator1);
        (, uint256 amount2,, bool revealed2,) = hook.revealedBids(auctionId, operator1);

        assertEq(amount1, amount2);
        assertEq(amount1, amount);
        assertEq(revealed1, revealed2);
        assertTrue(revealed1);
    }

    // Test: Bid commitment with different operators
    function test_bidCommitmentDifferentOperators() public {
        bytes32 auctionId = createAuction();

        commitBid(auctionId, operator1, 1 ether, 123);
        commitBid(auctionId, operator2, 2 ether, 123); // Same nonce, different operator

        bytes32 commitment1 = hook.bidCommitments(auctionId, operator1);
        bytes32 commitment2 = hook.bidCommitments(auctionId, operator2);

        assertNotEq(commitment1, commitment2);
    }

    // Test: Bid commitment with same operator different amounts
    function test_bidCommitmentSameOperatorDifferentAmounts() public {
        bytes32 auctionId = createAuction();

        commitBid(auctionId, operator1, 1 ether, 123);

        // Cannot commit again
        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: bid already committed");
        hook.commitBid(auctionId, AuctionLib.generateCommitment(operator1, 2 ether, 456));
    }

    // Test: Reveal updates winner correctly
    function test_revealUpdatesWinnerCorrectly() public {
        bytes32 auctionId = createAuction();

        commitBid(auctionId, operator1, 5 ether, 123);
        revealBid(auctionId, operator1, 5 ether, 123);

        (,,,,, address winner1, uint256 bid1,) = hook.auctions(auctionId);
        assertEq(winner1, operator1);
        assertEq(bid1, 5 ether);

        commitBid(auctionId, operator2, 10 ether, 456);
        revealBid(auctionId, operator2, 10 ether, 456);

        (,,,,, address winner2, uint256 bid2,) = hook.auctions(auctionId);
        assertEq(winner2, operator2);
        assertEq(bid2, 10 ether);
    }
}

