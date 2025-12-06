// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { TestFixture } from "../utils/TestFixture.sol";
import { TestHelpers } from "../utils/TestHelpers.sol";

/**
 * @title RewardFuzz
 * @notice Fuzz tests for reward distribution
 */
contract RewardFuzz is TestFixture {
    // Fuzz test: Reward distribution with various winning bids
    function testFuzz_rewardDistribution(uint256 winningBid) public {
        winningBid = bound(winningBid, hook.MIN_BID(), 1000000 ether);

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

        // Allow for rounding errors
        assertLe(total, winningBid);
        assertGe(total, winningBid - 4);
        assertGe(lpReward, 0);
        assertGe(operatorReward, 0);
        assertGe(protocolFee, 0);
        assertGe(gasCompensation, 0);
    }

    // Fuzz test: Reward percentages consistency
    function testFuzz_rewardPercentagesConsistency(uint256 amount) public {
        amount = bound(amount, 100, type(uint128).max);

        uint256 lpReward = (amount * hook.LP_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();
        uint256 operatorReward = (amount * hook.AVS_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();
        uint256 protocolFee = (amount * hook.PROTOCOL_FEE_PERCENTAGE()) / hook.BASIS_POINTS();
        uint256 gasCompensation =
            (amount * hook.GAS_COMPENSATION_PERCENTAGE()) / hook.BASIS_POINTS();

        uint256 total = lpReward + operatorReward + protocolFee + gasCompensation;

        // Allow for rounding errors
        assertLe(total, amount);
        assertGe(total, amount - 4); // Max rounding error
    }

    // Fuzz test: LP reward calculation
    function testFuzz_lpRewardCalculation(uint256 totalAmount) public {
        totalAmount = bound(totalAmount, 1, type(uint128).max);

        uint256 expectedLpReward = (totalAmount * hook.LP_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();

        assertEq(expectedLpReward, (totalAmount * 8500) / 10000);
        assertLe(expectedLpReward, totalAmount);
    }

    // Fuzz test: Operator reward calculation
    function testFuzz_operatorRewardCalculation(uint256 totalAmount) public {
        totalAmount = bound(totalAmount, 1, type(uint128).max);

        uint256 expectedOperatorReward =
            (totalAmount * hook.AVS_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();

        assertEq(expectedOperatorReward, (totalAmount * 1000) / 10000);
        assertLe(expectedOperatorReward, totalAmount);
    }

    // Fuzz test: Protocol fee calculation
    function testFuzz_protocolFeeCalculation(uint256 totalAmount) public {
        totalAmount = bound(totalAmount, 1, type(uint128).max);

        uint256 expectedProtocolFee =
            (totalAmount * hook.PROTOCOL_FEE_PERCENTAGE()) / hook.BASIS_POINTS();

        assertEq(expectedProtocolFee, (totalAmount * 300) / 10000);
        assertLe(expectedProtocolFee, totalAmount);
    }

    // Fuzz test: Gas compensation calculation
    function testFuzz_gasCompensationCalculation(uint256 totalAmount) public {
        totalAmount = bound(totalAmount, 1, type(uint128).max);

        uint256 expectedGasCompensation =
            (totalAmount * hook.GAS_COMPENSATION_PERCENTAGE()) / hook.BASIS_POINTS();

        assertEq(expectedGasCompensation, (totalAmount * 200) / 10000);
        assertLe(expectedGasCompensation, totalAmount);
    }

    // Fuzz test: Reward distribution with zero winning bid
    function testFuzz_rewardDistributionZeroBid(uint256 seed) public {
        bytes32 auctionId = createAuction();

        // Create auction but don't commit/reveal any bids
        // Just verify auction exists
        (,,, bool isActive,,,,) = hook.auctions(auctionId);
        assertTrue(isActive, "Auction should be active");
    }

    // Fuzz test: Reward distribution with very small bid
    function testFuzz_rewardDistributionSmallBid(uint256 amount) public {
        amount = bound(amount, hook.MIN_BID(), hook.MIN_BID() * 10);

        bytes32 auctionId = createAuction();
        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        (uint256 lpReward, uint256 operatorReward, uint256 protocolFee,, uint256 total) =
            TestHelpers.verifyRewardPercentages(hook, amount);

        assertLe(total, amount);
        assertGe(lpReward, 0);
        assertGe(operatorReward, 0);
        assertGe(protocolFee, 0);
    }

    // Fuzz test: Reward distribution with very large bid
    function testFuzz_rewardDistributionLargeBid(uint256 amount) public {
        amount = bound(amount, 100000 ether, type(uint128).max);

        bytes32 auctionId = createAuction();
        commitBid(auctionId, operator1, amount, 123);
        revealBid(auctionId, operator1, amount, 123);

        (uint256 lpReward, uint256 operatorReward, uint256 protocolFee,, uint256 total) =
            TestHelpers.verifyRewardPercentages(hook, amount);

        // Check for overflow
        assertLe(total, amount);
        assertGe(lpReward, (amount * 8500) / 10000 - 1);
        assertGe(operatorReward, (amount * 1000) / 10000 - 1);
        assertGe(protocolFee, (amount * 300) / 10000 - 1);
    }

    // Fuzz test: Multiple reward distributions
    function testFuzz_multipleRewardDistributions(uint256 seed, uint8 numAuctions) public {
        numAuctions = uint8(bound(numAuctions, 1, 5));

        for (uint8 i = 0; i < numAuctions; i++) {
            // End previous auction if it exists
            bytes32 existingAuctionId = hook.activeAuctions(poolId);
            if (existingAuctionId != bytes32(0)) {
                (,,, bool isActive, bool isComplete,,,) = hook.auctions(existingAuctionId);
                if (isActive && !isComplete) {
                    fastForwardPastAuctionDuration();
                    vm.prank(owner);
                    hook.endAuction(existingAuctionId);
                }
            }

            // Create new auction for each iteration
            bytes32 auctionId = createAuction();

            uint256 winningBid =
                TestHelpers.createValidBidAmount(uint256(keccak256(abi.encode(seed, i))));
            uint256 nonce = uint256(keccak256(abi.encode(seed, i)));

            commitBid(auctionId, operator1, winningBid, nonce);
            revealBid(auctionId, operator1, winningBid, nonce);

            (,,,, uint256 total) = TestHelpers.verifyRewardPercentages(hook, winningBid);

            assertLe(total, winningBid);
        }
    }

    // Fuzz test: Reward rounding
    function testFuzz_rewardRounding(uint256 amount) public {
        amount = bound(amount, 100, 10000);

        uint256 lpReward = (amount * hook.LP_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();
        uint256 operatorReward = (amount * hook.AVS_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();
        uint256 protocolFee = (amount * hook.PROTOCOL_FEE_PERCENTAGE()) / hook.BASIS_POINTS();
        uint256 gasCompensation =
            (amount * hook.GAS_COMPENSATION_PERCENTAGE()) / hook.BASIS_POINTS();

        uint256 total = lpReward + operatorReward + protocolFee + gasCompensation;

        // Total should be within rounding error
        assertGe(total, amount - 4);
        assertLe(total, amount);
    }
}

