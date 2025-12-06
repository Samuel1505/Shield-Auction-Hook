// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { Deployers } from "v4-periphery/lib/v4-core/test/utils/Deployers.sol";
import { PoolKey } from "@uniswap/v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/types/PoolId.sol";
import { Currency, CurrencyLibrary } from "@uniswap/v4-core/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/interfaces/IHooks.sol";
import { Hooks } from "@uniswap/v4-core/libraries/Hooks.sol";
import { TickMath } from "@uniswap/v4-core/libraries/TickMath.sol";
import { ModifyLiquidityParams, SwapParams } from "@uniswap/v4-core/types/PoolOperation.sol";

import { ShieldAuctionHook } from "../src/ShieldAuctionHook.sol";
import { IAVSDirectory } from "../src/IAVSDirectory.sol";
import { IPriceOracle } from "../src/IPriceOracle.sol";
import { AuctionLib } from "../src/Auction.sol";
import { MockAVSDirectory } from "./MockAVSDirectory.sol";
import { MockPriceOracle } from "./MockPriceOracle.sol";

/**
 * @title TestFixture
 * @notice Base fixture for setting up ShieldAuctionHook tests
 */
contract TestFixture is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    ShieldAuctionHook public hook;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;

    address public constant AVS_ADDRESS = address(0x1234);
    address public constant FEE_RECIPIENT = address(0x5678);
    uint256 public constant DEFAULT_LVR_THRESHOLD = 100; // 1% in basis points

    PoolKey public poolKey;
    PoolId public poolId;

    // Test users
    address public owner = address(this);
    address public operator1 = makeAddr("operator1");
    address public operator2 = makeAddr("operator2");
    address public operator3 = makeAddr("operator3");
    address public lp1 = makeAddr("lp1");
    address public lp2 = makeAddr("lp2");
    address public lp3 = makeAddr("lp3");
    address public bidder1 = makeAddr("bidder1");
    address public bidder2 = makeAddr("bidder2");
    address public bidder3 = makeAddr("bidder3");

    uint160 public INIT_SQRT_PRICE;

    // Hook permissions mask
    uint160 public hookPermissionsMask = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG;

    function setUp() public virtual {
        // Deploy mocks
        avsDirectory = new MockAVSDirectory();
        priceOracle = new MockPriceOracle();

        // Deploy PoolManager and routers
        deployFreshManagerAndRouters();

        // Calculate hook address with proper permissions
        hook = ShieldAuctionHook(
            payable(address(
                    uint160(type(uint160).max & clearAllHookPermissionsMask | hookPermissionsMask)
                ))
        );

        // Deploy hook to the calculated address
        deployCodeTo(
            "ShieldAuctionHook",
            abi.encode(
                manager,
                avsDirectory,
                AVS_ADDRESS,
                priceOracle,
                FEE_RECIPIENT,
                DEFAULT_LVR_THRESHOLD
            ),
            address(hook)
        );

        // Set up currencies
        deployMintAndApprove2Currencies();

        // Create pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        poolId = poolKey.toId();

        // Initialize pool at 1:1 price
        INIT_SQRT_PRICE = uint160(TickMath.getSqrtPriceAtTick(0));
        manager.initialize(poolKey, INIT_SQRT_PRICE);

        // Add initial liquidity to make swaps work
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 1e24, // Large liquidity for testing
                salt: 0
            }),
            ""
        );

        // Set up price oracle with 1:1 price
        priceOracle.setPrice(currency0, currency1, 1e18, false);

        // Authorize operators
        avsDirectory.setOperatorStatus(
            AVS_ADDRESS, operator1, IAVSDirectory.OperatorAVSRegistrationStatus.REGISTERED
        );
        avsDirectory.setOperatorStatus(
            AVS_ADDRESS, operator2, IAVSDirectory.OperatorAVSRegistrationStatus.REGISTERED
        );
        avsDirectory.setOperatorStatus(
            AVS_ADDRESS, operator3, IAVSDirectory.OperatorAVSRegistrationStatus.REGISTERED
        );
    }

    /**
     * @notice Create an auction by performing a swap with price deviation
     */
    function createAuction() internal returns (bytes32) {
        setPriceDeviationAboveThreshold();
        swap(poolKey, true, -1e18, "");
        return hook.activeAuctions(poolId);
    }

    /**
     * @notice Set price deviation above threshold to trigger auction
     */
    function setPriceDeviationAboveThreshold() internal {
        priceOracle.setPrice(currency0, currency1, 1.02e18, false);
    }

    /**
     * @notice Set price deviation below threshold
     */
    function setPriceDeviationBelowThreshold() internal {
        priceOracle.setPrice(currency0, currency1, 1.005e18, false);
    }

    /**
     * @notice Get auction struct
     */
    function getAuction(bytes32 auctionId)
        internal
        view
        returns (
            PoolId poolId_,
            uint256 startTime,
            uint256 duration,
            bool isActive,
            bool isComplete,
            address winner,
            uint256 winningBid,
            uint256 totalBids
        )
    {
        return hook.auctions(auctionId);
    }

    /**
     * @notice Commit a bid
     */
    function commitBid(bytes32 auctionId, address bidder, uint256 amount, uint256 nonce)
        internal
        returns (bytes32)
    {
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        vm.prank(bidder);
        hook.commitBid(auctionId, commitment);
        return commitment;
    }

    /**
     * @notice Reveal a bid
     */
    function revealBid(bytes32 auctionId, address operator, uint256 amount, uint256 nonce)
        internal
    {
        vm.prank(operator);
        hook.revealBid(auctionId, amount, nonce);
    }

    /**
     * @notice Fast forward time
     */
    function fastForward(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    /**
     * @notice Fast forward past auction duration
     */
    function fastForwardPastAuctionDuration() internal {
        fastForward(hook.MAX_AUCTION_DURATION() + 1);
    }

    /**
     * @notice End an auction if it's still active, otherwise do nothing
     */
    function endAuctionIfActive(bytes32 auctionId) internal {
        (,,, bool isActive, bool isComplete,,,) = hook.auctions(auctionId);
        if (isActive && !isComplete) {
            vm.prank(owner);
            hook.endAuction(auctionId);
        }
    }

    /**
     * @notice End an auction idempotently - fast forward past duration if needed, then end
     */
    function endAuctionIdempotent(bytes32 auctionId) internal {
        (, uint256 startTime, uint256 duration,, bool isComplete,,,) = hook.auctions(auctionId);

        // If already complete, do nothing
        if (isComplete) {
            return;
        }

        // Fast forward past auction duration if needed
        uint256 endTime = startTime + duration;
        if (block.timestamp < endTime) {
            vm.warp(endTime + 1);
        }

        // End the auction (will be idempotent if already ended)
        vm.prank(owner);
        hook.endAuction(auctionId);
    }
}

