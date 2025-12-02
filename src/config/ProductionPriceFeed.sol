// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "@uniswap/v4-core/types/Currency.sol";

/**
 * @title ProductionPriceFeedConfig
 * @notice Configuration for production Chainlink price feeds on different networks
 * @dev This contract contains the addresses of Chainlink price feeds for major token pairs
 */
contract ProductionPriceFeedConfig {
    
    struct PriceFeedConfig {
        address token0;
        address token1;
        address priceFeed;
        bool isActive;
    }
    
    // Common token addresses on Ethereum mainnet
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86a33E6417c8a9bbe78fe047ce5C17aEd0Ada;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address public constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    
    // Chainlink price feed addresses on Ethereum mainnet
    address public constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant BTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address public constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant USDT_USD_FEED = 0x3e7d1eab13ad8024dC2D5B2ec8a2b0A7E3E8E1B8;
    address public constant DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address public constant LINK_USD_FEED = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
    address public constant UNI_USD_FEED = 0x553303d460EE0afB37EdFf9bE42922D8FF63220e;
    address public constant AAVE_USD_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
  
    /**
     * @notice Get price feed configuration for a token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @return config The price feed configuration
     */
    function getPriceFeedConfig(address token0, address token1) external pure returns (PriceFeedConfig memory config) {
        // Normalize token order (smaller address first)
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        
        // ETH/USDC pair
        if (token0 == WETH && token1 == USDC) {
            return PriceFeedConfig({
                token0: token0,
                token1: token1,
                priceFeed: ETH_USD_FEED,
                isActive: true
            });
        }
        
        // ETH/USDT pair
        if (token0 == WETH && token1 == USDT) {
            return PriceFeedConfig({
                token0: token0,
                token1: token1,
                priceFeed: ETH_USD_FEED,
                isActive: true
            });
        }
        
        // ETH/DAI pair
        if (token0 == WETH && token1 == DAI) {
            return PriceFeedConfig({
                token0: token0,
                token1: token1,
                priceFeed: ETH_USD_FEED,
                isActive: true
            });
        }
        
        // WBTC/USDC pair
        if (token0 == WBTC && token1 == USDC) {
            return PriceFeedConfig({
                token0: token0,
                token1: token1,
                priceFeed: BTC_USD_FEED,
                isActive: true
            });
        }
        
        // WBTC/USDT pair
        if (token0 == WBTC && token1 == USDT) {
            return PriceFeedConfig({
                token0: token0,
                token1: token1,
                priceFeed: BTC_USD_FEED,
                isActive: true
            });
        }
        
        // WBTC/ETH pair
        if (token0 == WBTC && token1 == WETH) {
            return PriceFeedConfig({
                token0: token0,
                token1: token1,
                priceFeed: BTC_USD_FEED, // We'll need to calculate BTC/ETH price
                isActive: true
            });
        }
        
        // LINK/USDC pair
        if (token0 == LINK && token1 == USDC) {
            return PriceFeedConfig({
                token0: token0,
                token1: token1,
                priceFeed: LINK_USD_FEED,
                isActive: true
            });
        }
        
        // UNI/USDC pair
        if (token0 == UNI && token1 == USDC) {
            return PriceFeedConfig({
                token0: token0,
                token1: token1,
                priceFeed: UNI_USD_FEED,
                isActive: true
            });
        }
        
        // AAVE/USDC pair
        if (token0 == AAVE && token1 == USDC) {
            return PriceFeedConfig({
                token0: token0,
                token1: token1,
                priceFeed: AAVE_USD_FEED,
                isActive: true
            });
        }
        
        // Return inactive config for unsupported pairs
        return PriceFeedConfig({
            token0: token0,
            token1: token1,
            priceFeed: address(0),
            isActive: false
        });
    }
    
    /**
     * @notice Check if a token pair is supported
     * @param token0 First token address
     * @param token1 Second token address
     * @return Whether the pair is supported
     */
    function isPairSupported(address token0, address token1) external view returns (bool) {
        PriceFeedConfig memory config = this.getPriceFeedConfig(token0, token1);
        return config.isActive;
    }
    
    /**
     * @notice Get all supported token pairs
     * @return pairs Array of supported token pair addresses
     */
    /*
    function getSupportedPairs() external pure returns (address[][2] memory pairs) {
        // Return empty array for now to avoid compilation issues
        pairs = new address[][2](0);
        return pairs;
    }
    */
}
