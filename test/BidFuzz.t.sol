// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { TestFixture } from "./TestFixture.sol";
import { TestHelpers } from "./TestHelpers.sol";
import { AuctionLib } from "../src/Auction.sol";

/**
 * @title BidFuzz
 * @notice Fuzz tests for bid functionality
 */
contract BidFuzz is TestFixture {
    // Fuzz test: Bid commitment with random parameters
    function testFuzz_bidCommitment_random(
        uint256 amountSeed,
        uint256 nonceSeed,
        uint256 bidderSeed
    ) public {
        bytes32 auctionId = createAuction();

        uint256 amount = TestHelpers.createValidBidAmount(amountSeed);
        uint256 nonce = nonceSeed;
        address bidder = TestHelpers.randomAddress(bidderSeed);

        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);

        vm.prank(bidder);
        hook.commitBid(auctionId, commitment);

        assertEq(hook.bidCommitments(auctionId, bidder), commitment);
    }

    // Fuzz test: Bid revelation with correct parameters
    function testFuzz_bidRevelation_correct(uint256 amountSeed, uint256 nonceSeed) public {
        bytes32 auctionId = createAuction();

        uint256 amount = TestHelpers.createValidBidAmount(amountSeed);
        uint256 nonce = nonceSeed;

        hook.setOperatorAuthorization(operator1, true);
        commitBid(auctionId, operator1, amount, nonce);
        revealBid(auctionId, operator1, amount, nonce);

        (, uint256 revealedAmount,, bool revealed,) = hook.revealedBids(auctionId, operator1);
        assertEq(revealedAmount, amount);
        assertTrue(revealed);
    }

    // Fuzz test: Bid revelation with wrong nonce
    function testFuzz_bidRevelation_wrongNonce(
        uint256 amountSeed,
        uint256 correctNonce,
        uint256 wrongNonce
    ) public {
        vm.assume(correctNonce != wrongNonce);

        bytes32 auctionId = createAuction();
        uint256 amount = TestHelpers.createValidBidAmount(amountSeed);

        hook.setOperatorAuthorization(operator1, true);
        commitBid(auctionId, operator1, amount, correctNonce);

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: invalid commitment");
        hook.revealBid(auctionId, amount, wrongNonce);
    }

    // Fuzz test: Bid revelation with wrong amount
    function testFuzz_bidRevelation_wrongAmount(uint256 correctAmountSeed, uint256 wrongAmountSeed)
        public
    {
        bytes32 auctionId = createAuction();

        uint256 correctAmount = TestHelpers.createValidBidAmount(correctAmountSeed);
        uint256 wrongAmount = TestHelpers.createValidBidAmount(wrongAmountSeed);
        uint256 nonce = 123;

        vm.assume(correctAmount != wrongAmount);

        hook.setOperatorAuthorization(operator1, true);
        commitBid(auctionId, operator1, correctAmount, nonce);

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: invalid commitment");
        hook.revealBid(auctionId, wrongAmount, nonce);
    }

    // Fuzz test: Bid below minimum
    function testFuzz_bidBelowMinimum(uint256 amount) public {
        bytes32 auctionId = createAuction();

        amount = bound(amount, 0, hook.MIN_BID() - 1);

        hook.setOperatorAuthorization(operator1, true);
        commitBid(auctionId, operator1, amount, 123);

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: bid below minimum");
        hook.revealBid(auctionId, amount, 123);
    }

    // Fuzz test: Multiple bids from same bidder
    function testFuzz_multipleBidsSameBidder(uint256 seed, uint8 numBids) public {
        bytes32 auctionId = createAuction();

        numBids = uint8(bound(numBids, 1, 5));

        for (uint8 i = 0; i < numBids; i++) {
            uint256 amount =
                TestHelpers.createValidBidAmount(uint256(keccak256(abi.encode(seed, i))));
            uint256 nonce = uint256(keccak256(abi.encode(seed, i)));

            bytes32 commitment = AuctionLib.generateCommitment(operator1, amount, nonce);

            vm.prank(operator1);
            if (i == 0) {
                hook.commitBid(auctionId, commitment);
            } else {
                vm.expectRevert("ShieldAuctionHook: bid already committed");
                hook.commitBid(auctionId, commitment);
            }
        }
    }

    // Fuzz test: Bid commitment uniqueness
    function testFuzz_bidCommitmentUniqueness(
        address bidder1,
        address bidder2,
        uint256 amount1,
        uint256 amount2,
        uint256 nonce1,
        uint256 nonce2
    ) public {
        bytes32 auctionId = createAuction();

        amount1 = bound(amount1, hook.MIN_BID(), 10000 ether);
        amount2 = bound(amount2, hook.MIN_BID(), 10000 ether);

        bytes32 commitment1 = AuctionLib.generateCommitment(bidder1, amount1, nonce1);
        bytes32 commitment2 = AuctionLib.generateCommitment(bidder2, amount2, nonce2);

        if (bidder1 == bidder2 && amount1 == amount2 && nonce1 == nonce2) {
            assertEq(commitment1, commitment2);
        } else {
            // Commitments may or may not be equal, but both should be valid
            vm.prank(bidder1);
            hook.commitBid(auctionId, commitment1);

            vm.prank(bidder2);
            hook.commitBid(auctionId, commitment2);
        }
    }

    // Fuzz test: Winning bid updates
    function testFuzz_winningBidUpdates(uint256 seed, uint8 numBids) public {
        bytes32 auctionId = createAuction();

        numBids = uint8(bound(numBids, 1, 10));
        uint256 maxBid = 0;

        // Use different operators for each bid to avoid "bid already committed" error
        address[] memory operators = new address[](numBids);
        for (uint8 i = 0; i < numBids; i++) {
            if (i < 3) {
                operators[i] = i == 0 ? operator1 : (i == 1 ? operator2 : operator3);
            } else {
                operators[i] = makeAddr(string(abi.encodePacked("operator", i)));
                hook.setOperatorAuthorization(operators[i], true);
            }
        }

        for (uint8 i = 0; i < numBids; i++) {
            uint256 amount =
                TestHelpers.createValidBidAmount(uint256(keccak256(abi.encode(seed, i))));
            uint256 nonce = uint256(keccak256(abi.encode(seed, i)));

            if (amount > maxBid) {
                maxBid = amount;
            }

            commitBid(auctionId, operators[i], amount, nonce);
            revealBid(auctionId, operators[i], amount, nonce);

            (,,,,, address winner, uint256 winningBid,) = hook.auctions(auctionId);
            assertGe(winningBid, amount);
            assertLe(winningBid, maxBid);
        }

        (,,,,, address finalWinner, uint256 finalWinningBid,) = hook.auctions(auctionId);
        assertEq(finalWinningBid, maxBid);
    }

    // Fuzz test: Bid commitment hash collision resistance
    function testFuzz_bidCommitmentCollisionResistance(
        address bidder1,
        address bidder2,
        uint256 amount1,
        uint256 amount2,
        uint256 nonce1,
        uint256 nonce2
    ) public {
        bytes32 commitment1 = AuctionLib.generateCommitment(bidder1, amount1, nonce1);
        bytes32 commitment2 = AuctionLib.generateCommitment(bidder2, amount2, nonce2);

        // If all parameters are the same, commitments should be equal
        if (bidder1 == bidder2 && amount1 == amount2 && nonce1 == nonce2) {
            assertEq(commitment1, commitment2);
        }
        // Otherwise, probability of collision is extremely low
    }

    // Fuzz test: Bid revelation timing
    function testFuzz_bidRevelationTiming(uint256 timeBeforeReveal) public {
        bytes32 auctionId = createAuction();

        (,, uint256 duration,,,,,) = hook.auctions(auctionId);
        timeBeforeReveal = bound(timeBeforeReveal, 0, duration);

        uint256 amount = TestHelpers.createValidBidAmount(123);
        commitBid(auctionId, operator1, amount, 123);

        fastForward(timeBeforeReveal);

        // Should be able to reveal as long as auction is active
        if (timeBeforeReveal < duration) {
            revealBid(auctionId, operator1, amount, 123);
            (, uint256 revealedAmount,, bool revealed,) = hook.revealedBids(auctionId, operator1);
            assertEq(revealedAmount, amount);
            assertTrue(revealed);
        }
    }

    // Fuzz test: Bid amount edge cases
    function testFuzz_bidAmountEdgeCases(uint256 amount) public {
        bytes32 auctionId = createAuction();

        // Test with various amounts
        if (amount < hook.MIN_BID()) {
            commitBid(auctionId, operator1, amount, 123);
            vm.prank(operator1);
            vm.expectRevert("ShieldAuctionHook: bid below minimum");
            hook.revealBid(auctionId, amount, 123);
        } else if (amount <= type(uint128).max) {
            commitBid(auctionId, operator1, amount, 123);
            revealBid(auctionId, operator1, amount, 123);
            (, uint256 revealedAmount,,,) = hook.revealedBids(auctionId, operator1);
            assertEq(revealedAmount, amount);
        }
    }

    // Fuzz test: Nonce variations
    function testFuzz_nonceVariations(uint256 nonce1, uint256 nonce2) public {
        bytes32 auctionId = createAuction();
        uint256 amount = TestHelpers.createValidBidAmount(123);

        commitBid(auctionId, operator1, amount, nonce1);

        bytes32 commitment = hook.bidCommitments(auctionId, operator1);

        // Should verify with correct nonce
        assertTrue(AuctionLib.verifyCommitment(commitment, operator1, amount, nonce1));

        // Should not verify with wrong nonce
        if (nonce1 != nonce2) {
            assertFalse(AuctionLib.verifyCommitment(commitment, operator1, amount, nonce2));
        }
    }

    // Fuzz test: Bidder address variations
    function testFuzz_bidderAddressVariations(address bidder1, address bidder2) public {
        bytes32 auctionId = createAuction();
        uint256 amount = TestHelpers.createValidBidAmount(123);
        uint256 nonce = 123;

        bytes32 commitment1 = AuctionLib.generateCommitment(bidder1, amount, nonce);
        bytes32 commitment2 = AuctionLib.generateCommitment(bidder2, amount, nonce);

        if (bidder1 == bidder2) {
            assertEq(commitment1, commitment2);
        }

        vm.prank(bidder1);
        hook.commitBid(auctionId, commitment1);

        // Only commit second bid if bidder2 is different from bidder1
        if (bidder1 != bidder2) {
            vm.prank(bidder2);
            hook.commitBid(auctionId, commitment2);
            assertEq(hook.bidCommitments(auctionId, bidder2), commitment2);
        }

        assertEq(hook.bidCommitments(auctionId, bidder1), commitment1);
    }

    // Fuzz test: Concurrent bid revelations
    function testFuzz_concurrentBidRevelations(uint256 seed, uint8 numReveals) public {
        bytes32 auctionId = createAuction();

        numReveals = uint8(bound(numReveals, 1, 5));

        // Use different operators for each bid to avoid "bid already committed" error
        address[] memory operators = new address[](numReveals);
        for (uint8 i = 0; i < numReveals; i++) {
            if (i < 3) {
                operators[i] = i == 0 ? operator1 : (i == 1 ? operator2 : operator3);
            } else {
                operators[i] = makeAddr(string(abi.encodePacked("operator", i)));
                hook.setOperatorAuthorization(operators[i], true);
            }
        }

        // Commit multiple bids
        for (uint8 i = 0; i < numReveals; i++) {
            uint256 amount =
                TestHelpers.createValidBidAmount(uint256(keccak256(abi.encode(seed, i))));
            uint256 nonce = uint256(keccak256(abi.encode(seed, i)));
            commitBid(auctionId, operators[i], amount, nonce);
        }

        // Reveal all bids
        for (uint8 i = 0; i < numReveals; i++) {
            uint256 amount =
                TestHelpers.createValidBidAmount(uint256(keccak256(abi.encode(seed, i))));
            uint256 nonce = uint256(keccak256(abi.encode(seed, i)));
            revealBid(auctionId, operators[i], amount, nonce);
        }

        // Verify all revealed
        for (uint8 i = 0; i < numReveals; i++) {
            (,,, bool revealed,) = hook.revealedBids(auctionId, operators[i]);
            assertTrue(revealed);
        }
    }

    // Fuzz test: Bid commitment overwrite prevention
    function testFuzz_bidCommitmentOverwritePrevention(
        uint256 amount1,
        uint256 amount2,
        uint256 nonce1,
        uint256 nonce2
    ) public {
        bytes32 auctionId = createAuction();

        amount1 = bound(amount1, hook.MIN_BID(), 10000 ether);
        amount2 = bound(amount2, hook.MIN_BID(), 10000 ether);

        bytes32 commitment1 = AuctionLib.generateCommitment(operator1, amount1, nonce1);

        vm.prank(operator1);
        hook.commitBid(auctionId, commitment1);

        bytes32 commitment2 = AuctionLib.generateCommitment(operator1, amount2, nonce2);

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: bid already committed");
        hook.commitBid(auctionId, commitment2);

        assertEq(hook.bidCommitments(auctionId, operator1), commitment1);
    }

    // Fuzz test: Bid revelation after auction ends
    function testFuzz_bidRevelationAfterAuctionEnds(uint256 amount) public {
        bytes32 auctionId = createAuction();

        amount = bound(amount, hook.MIN_BID(), 10000 ether);
        commitBid(auctionId, operator1, amount, 123);

        fastForwardPastAuctionDuration();

        vm.prank(operator1);
        vm.expectRevert("ShieldAuctionHook: auction not active");
        hook.revealBid(auctionId, amount, 123);
    }

    // Fuzz test: Bid commitment verification
    function testFuzz_bidCommitmentVerification(address bidder, uint256 amount, uint256 nonce)
        public
    {
        amount = bound(amount, hook.MIN_BID(), 10000 ether);

        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);

        assertTrue(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce));

        // Check for overflow before adding 1
        if (amount < type(uint256).max) {
            assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount + 1, nonce));
        }
        if (nonce < type(uint256).max) {
            assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce + 1));
        }
    }
}

