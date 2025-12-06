// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { PoolKey } from "@uniswap/v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/types/PoolId.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/types/Currency.sol";
import { ShieldAuctionHook } from "../../src/hooks/ShieldAuctionHook.sol";
import { AuctionLib } from "../../src/libraries/Auction.sol";
import { IAVSDirectory } from "../../src/interfaces/IAVSDirectory.sol";
import { IPriceOracle } from "../../src/interfaces/IPriceOracle.sol";
import { MockAVSDirectory } from "./MockAVSDirectory.sol";
import { MockPriceOracle } from "./MockPriceOracle.sol";

/**
 * @title TestHelpers
 * @notice Utility functions for testing ShieldAuctionHook
 */
library TestHelpers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    /**
     * @notice Generate a random address
     */
    function randomAddress(uint256 seed) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed)))));
    }

    /**
     * @notice Generate a random uint256
     */
    function randomUint256(uint256 seed, uint256 max) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed))) % max;
    }

    /**
     * @notice Generate a random bid commitment
     */
    function generateRandomCommitment(address bidder, uint256 amount, uint256 nonce)
        internal
        pure
        returns (bytes32)
    {
        return AuctionLib.generateCommitment(bidder, amount, nonce);
    }

    /**
     * @notice Create a valid bid amount (above minimum)
     */
    function createValidBidAmount(uint256 seed) internal pure returns (uint256) {
        uint256 minBid = 1e15; // MIN_BID
        return minBid + (seed % (1000 ether - minBid));
    }

    /**
     * @notice Create a valid LVR threshold
     */
    function createValidLVRThreshold(uint256 seed) internal pure returns (uint256) {
        return 1 + (seed % 10000); // Between 1 and 10000 basis points
    }

    /**
     * @notice Create a price that triggers auction (above threshold)
     */
    function createTriggerPrice(uint256 basePrice, uint256 threshold)
        internal
        pure
        returns (uint256)
    {
        // Price deviation should exceed threshold
        uint256 deviation = (basePrice * (threshold + 100)) / 10000; // Add extra to exceed threshold
        return basePrice + deviation;
    }

    /**
     * @notice Create a price that doesn't trigger auction (below threshold)
     */
    function createNonTriggerPrice(uint256 basePrice, uint256 threshold)
        internal
        pure
        returns (uint256)
    {
        // Price deviation should be below threshold
        uint256 deviation = (basePrice * (threshold - 1)) / 10000;
        return basePrice + deviation;
    }

    /**
     * @notice Calculate price deviation in basis points
     */
    function calculatePriceDeviation(uint256 price1, uint256 price2)
        internal
        pure
        returns (uint256)
    {
        if (price1 == 0 || price2 == 0) return 0;

        if (price1 > price2) {
            return ((price1 - price2) * 10000) / price2;
        } else {
            return ((price2 - price1) * 10000) / price1;
        }
    }

    /**
     * @notice Verify reward distribution percentages sum correctly
     */
    function verifyRewardPercentages(ShieldAuctionHook hook, uint256 totalAmount)
        internal
        view
        returns (
            uint256 lpReward,
            uint256 operatorReward,
            uint256 protocolFee,
            uint256 gasCompensation,
            uint256 total
        )
    {
        lpReward = (totalAmount * hook.LP_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();
        operatorReward = (totalAmount * hook.AVS_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();
        protocolFee = (totalAmount * hook.PROTOCOL_FEE_PERCENTAGE()) / hook.BASIS_POINTS();
        gasCompensation = (totalAmount * hook.GAS_COMPENSATION_PERCENTAGE()) / hook.BASIS_POINTS();
        total = lpReward + operatorReward + protocolFee + gasCompensation;
    }

    /**
     * @notice Get auction struct from hook
     */
    function getAuction(ShieldAuctionHook hook, bytes32 auctionId)
        internal
        view
        returns (AuctionLib.Auction memory)
    {
        (
            PoolId poolId,
            uint256 startTime,
            uint256 duration,
            bool isActive,
            bool isComplete,
            address winner,
            uint256 winningBid,
            uint256 totalBids
        ) = hook.auctions(auctionId);

        return AuctionLib.Auction({
            poolId: poolId,
            startTime: startTime,
            duration: duration,
            isActive: isActive,
            isComplete: isComplete,
            winner: winner,
            winningBid: winningBid,
            totalBids: totalBids
        });
    }

    /**
     * @notice Get bid struct from hook
     */
    function getBid(ShieldAuctionHook hook, bytes32 auctionId, address bidder)
        internal
        view
        returns (AuctionLib.Bid memory)
    {
        (address bidderAddr, uint256 amount, bytes32 commitment, bool revealed, uint256 timestamp) =
            hook.revealedBids(auctionId, bidder);

        return AuctionLib.Bid({
            bidder: bidderAddr,
            amount: amount,
            commitment: commitment,
            revealed: revealed,
            timestamp: timestamp
        });
    }

    /**
     * @notice Check if auction should be active based on time
     */
    function shouldAuctionBeActive(AuctionLib.Auction memory auction, uint256 currentTime)
        internal
        pure
        returns (bool)
    {
        if (!auction.isActive) return false;
        if (auction.isComplete) return false;
        if (currentTime < auction.startTime) return false;
        if (currentTime >= auction.startTime + auction.duration) return false;
        return true;
    }

    /**
     * @notice Check if auction should be ended based on time
     */
    function shouldAuctionBeEnded(AuctionLib.Auction memory auction, uint256 currentTime)
        internal
        pure
        returns (bool)
    {
        if (auction.duration == type(uint256).max) return false;
        if (auction.startTime > type(uint256).max - auction.duration) return false;
        return currentTime >= auction.startTime + auction.duration;
    }
}

