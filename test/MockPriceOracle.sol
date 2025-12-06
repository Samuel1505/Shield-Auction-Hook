// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IPriceOracle } from "../../src/interfaces/IPriceOracle.sol";
import { Currency } from "@uniswap/v4-core/types/Currency.sol";

/**
 * @title MockPriceOracle
 * @notice Mock implementation of IPriceOracle for testing
 */
contract MockPriceOracle is IPriceOracle {
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        bool isStale;
    }

    mapping(Currency => mapping(Currency => PriceData)) public prices;
    uint256 public staleThreshold = 300; // 5 minutes default

    function setPrice(Currency token0, Currency token1, uint256 price, bool isStale) external {
        prices[token0][token1] =
            PriceData({ price: price, timestamp: block.timestamp, isStale: isStale });
    }

    function setStaleThreshold(uint256 threshold) external {
        staleThreshold = threshold;
    }

    function getPrice(Currency token0, Currency token1) external view override returns (uint256) {
        PriceData memory data = prices[token0][token1];
        if (data.price == 0) {
            // Return default 1:1 price if not set
            return 1e18;
        }
        return data.price;
    }

    function getPriceAtTime(
        Currency token0,
        Currency token1,
        uint256 /* timestamp */
    )
        external
        view
        override
        returns (uint256)
    {
        PriceData memory data = prices[token0][token1];
        if (data.price == 0) {
            return 1e18;
        }
        return data.price;
    }

    function isPriceStale(Currency token0, Currency token1) external view override returns (bool) {
        PriceData memory data = prices[token0][token1];
        if (data.price == 0) return true;
        if (data.isStale) return true;
        if (block.timestamp - data.timestamp > staleThreshold) return true;
        return false;
    }

    function getLastUpdateTime(Currency token0, Currency token1)
        external
        view
        override
        returns (uint256)
    {
        return prices[token0][token1].timestamp;
    }
}

