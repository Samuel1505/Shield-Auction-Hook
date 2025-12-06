// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IPoolManager } from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/types/PoolId.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/types/BeforeSwapDelta.sol";
import { BaseHook } from "v4-periphery/src/utils/BaseHook.sol";
import { Hooks } from "@uniswap/v4-core/libraries/Hooks.sol";
import { CurrencyLibrary, Currency } from "@uniswap/v4-core/types/Currency.sol";
import { BalanceDelta } from "@uniswap/v4-core/types/BalanceDelta.sol";
import { StateLibrary } from "@uniswap/v4-core/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/libraries/TickMath.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { IAVSDirectory } from "./IAVSDirectory.sol";
import { IPriceOracle } from "./IPriceOracle.sol";
import { AuctionLib } from "./Auction.sol";
import { ModifyLiquidityParams, SwapParams } from "@uniswap/v4-core/types/PoolOperation.sol";

/**
 * @title ShieldAuctionHook
 * @author Shield Auction Hook Team
 * @notice A Uniswap v4 Hook that mitigates Loss Versus Rebalancing (LVR) through
 *         EigenLayer-powered sealed-bid auctions
 * @dev This hook intercepts swaps to run block-level auctions, redistributing MEV to LPs
 */
contract ShieldAuctionHook is BaseHook, ReentrancyGuard, Ownable, Pausable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using AuctionLib for AuctionLib.Auction;
    using StateLibrary for IPoolManager;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum bid amount (0.001 ETH)
    uint256 public constant MIN_BID = 1e15;

    /// @notice Maximum auction duration in seconds (12 seconds = 1 block on most chains)
    uint256 public constant MAX_AUCTION_DURATION = 12;

    /// @notice LP reward percentage (85%)
    uint256 public constant LP_REWARD_PERCENTAGE = 8500;

    /// @notice AVS operator reward percentage (10%)
    uint256 public constant AVS_REWARD_PERCENTAGE = 1000;

    /// @notice Protocol fee percentage (3%)
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 300;

    /// @notice Gas compensation percentage (2%)
    uint256 public constant GAS_COMPENSATION_PERCENTAGE = 200;

    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice EigenLayer AVS Directory for operator validation
    IAVSDirectory public immutable avsDirectory;

    /// @notice AVS address for this hook
    address public immutable avsAddress;

    /// @notice Price oracle for LVR detection
    IPriceOracle public immutable priceOracle;

    /// @notice Mapping of pool to active auctions
    mapping(PoolId => bytes32) public activeAuctions;

    /// @notice Mapping of auction ID to auction data
    mapping(bytes32 => AuctionLib.Auction) public auctions;

    /// @notice Mapping of auction ID to bid commitments
    mapping(bytes32 => mapping(address => bytes32)) public bidCommitments;

    /// @notice Mapping of auction ID to revealed bids
    mapping(bytes32 => mapping(address => AuctionLib.Bid)) public revealedBids;

    /// @notice Mapping of pool to accumulated LP rewards
    mapping(PoolId => uint256) public poolRewards;

    /// @notice Mapping of LP to claimable rewards per pool
    mapping(PoolId => mapping(address => uint256)) public lpRewards;

    /// @notice Mapping of pool to total liquidity (for reward calculation)
    mapping(PoolId => uint256) public totalLiquidity;

    /// @notice Mapping of pool to LP liquidity positions
    mapping(PoolId => mapping(address => uint256)) public lpLiquidity;

    /// @notice Authorized AVS operators
    mapping(address => bool) public authorizedOperators;

    /// @notice Protocol fee recipient
    address public feeRecipient;

    /// @notice LVR threshold for triggering auctions (in basis points, e.g., 100 = 1%)
    uint256 public lvrThreshold;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuctionStarted(
        bytes32 indexed auctionId, PoolId indexed poolId, uint256 startTime, uint256 duration
    );

    event AuctionEnded(
        bytes32 indexed auctionId, PoolId indexed poolId, address indexed winner, uint256 winningBid
    );

    event MEVDistributed(
        PoolId indexed poolId,
        uint256 totalAmount,
        uint256 lpRewards,
        uint256 operatorRewards,
        uint256 protocolFees
    );

    event BidCommitted(bytes32 indexed auctionId, address indexed bidder, bytes32 commitment);

    event BidRevealed(bytes32 indexed auctionId, address indexed bidder, uint256 amount);

    event RewardsClaimed(PoolId indexed poolId, address indexed lp, uint256 amount);

    event LiquidityTracked(PoolId indexed poolId, address indexed lp, uint256 liquidity);

    event OperatorAuthorized(address indexed operator);
    event OperatorDeauthorized(address indexed operator);
    event LVRThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorizedOperator() {
        require(
            authorizedOperators[msg.sender]
                || avsDirectory.avsOperatorStatus(avsAddress, msg.sender)
                    == IAVSDirectory.OperatorAVSRegistrationStatus.REGISTERED,
            "ShieldAuctionHook: not authorized operator"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IPoolManager _poolManager,
        IAVSDirectory _avsDirectory,
        address _avsAddress,
        IPriceOracle _priceOracle,
        address _feeRecipient,
        uint256 _lvrThreshold
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        require(address(_avsDirectory) != address(0), "ShieldAuctionHook: invalid AVS directory");
        require(_avsAddress != address(0), "ShieldAuctionHook: invalid AVS address");
        require(address(_priceOracle) != address(0), "ShieldAuctionHook: invalid price oracle");
        require(_feeRecipient != address(0), "ShieldAuctionHook: invalid fee recipient");
        require(
            _lvrThreshold > 0 && _lvrThreshold <= BASIS_POINTS,
            "ShieldAuctionHook: invalid LVR threshold"
        );

        avsDirectory = _avsDirectory;
        avsAddress = _avsAddress;
        priceOracle = _priceOracle;
        feeRecipient = _feeRecipient;
        lvrThreshold = _lvrThreshold;
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the hook permissions
     * @return Permissions struct indicating which hooks are implemented
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Called before swap to potentially trigger LVR auction
     */
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        whenNotPaused
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();

        // Check if LVR threshold is exceeded
        if (_shouldTriggerAuction(key, params)) {
            _startAuction(poolId);
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @notice Called after swap to handle auction results and distribute MEV
     */
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        bytes32 auctionId = activeAuctions[poolId];

        // If there's an active auction, end it and distribute rewards
        if (auctionId != bytes32(0)) {
            AuctionLib.Auction storage auction = auctions[auctionId];
            if (auction.isAuctionEnded()) {
                _endAuction(auctionId, poolId);
            }
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    /**
     * @notice Track liquidity when added
     */
    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        // Track liquidity position (simplified - in production, use actual position calculation)
        if (params.liquidityDelta > 0) {
            lpLiquidity[poolId][sender] += uint256(params.liquidityDelta);
            totalLiquidity[poolId] += uint256(params.liquidityDelta);
            emit LiquidityTracked(poolId, sender, uint256(params.liquidityDelta));
        }

        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    /**
     * @notice Track liquidity when removed
     */
    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();

        // Track liquidity removal
        if (params.liquidityDelta < 0) {
            uint256 liquidityToRemove = uint256(-params.liquidityDelta);
            uint256 currentLiquidity = lpLiquidity[poolId][sender];

            // Only remove up to what the LP has
            uint256 actualRemoval =
                liquidityToRemove > currentLiquidity ? currentLiquidity : liquidityToRemove;

            if (actualRemoval > 0) {
                lpLiquidity[poolId][sender] -= actualRemoval;
                // Prevent underflow in totalLiquidity
                if (totalLiquidity[poolId] >= actualRemoval) {
                    totalLiquidity[poolId] -= actualRemoval;
                } else {
                    totalLiquidity[poolId] = 0;
                }
            }
        }

        return (BaseHook.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    /*//////////////////////////////////////////////////////////////
                           AUCTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Start a new auction for a pool
     * @param poolId The pool ID to start an auction for
     */
    function _startAuction(PoolId poolId) internal {
        // Check if there's already an active auction
        bytes32 existingAuctionId = activeAuctions[poolId];
        if (existingAuctionId != bytes32(0)) {
            AuctionLib.Auction storage existingAuction = auctions[existingAuctionId];
            if (existingAuction.isAuctionActive()) {
                return; // Auction already active
            }
        }

        // Generate new auction ID
        bytes32 auctionId = keccak256(abi.encodePacked(poolId, block.number, block.timestamp));

        // Create new auction
        auctions[auctionId] = AuctionLib.Auction({
            poolId: poolId,
            startTime: block.timestamp,
            duration: MAX_AUCTION_DURATION,
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });

        activeAuctions[poolId] = auctionId;

        emit AuctionStarted(auctionId, poolId, block.timestamp, MAX_AUCTION_DURATION);
    }

    /**
     * @notice Commit a bid to an auction (sealed bid)
     * @param auctionId The auction ID
     * @param commitment The hash commitment of the bid
     */
    function commitBid(bytes32 auctionId, bytes32 commitment) external nonReentrant {
        AuctionLib.Auction storage auction = auctions[auctionId];
        require(auction.isAuctionActive(), "ShieldAuctionHook: auction not active");
        require(
            bidCommitments[auctionId][msg.sender] == bytes32(0),
            "ShieldAuctionHook: bid already committed"
        );

        bidCommitments[auctionId][msg.sender] = commitment;
        auction.totalBids++;

        emit BidCommitted(auctionId, msg.sender, commitment);
    }

    /**
     * @notice Reveal a bid commitment
     * @param auctionId The auction ID
     * @param amount The bid amount
     * @param nonce The nonce used in the commitment
     */
    function revealBid(bytes32 auctionId, uint256 amount, uint256 nonce)
        external
        nonReentrant
        onlyAuthorizedOperator
    {
        AuctionLib.Auction storage auction = auctions[auctionId];
        require(auction.isAuctionActive(), "ShieldAuctionHook: auction not active");

        bytes32 commitment = bidCommitments[auctionId][msg.sender];
        require(commitment != bytes32(0), "ShieldAuctionHook: no commitment found");
        require(
            !revealedBids[auctionId][msg.sender].revealed, "ShieldAuctionHook: bid already revealed"
        );

        // Verify commitment
        require(
            AuctionLib.verifyCommitment(commitment, msg.sender, amount, nonce),
            "ShieldAuctionHook: invalid commitment"
        );

        require(amount >= MIN_BID, "ShieldAuctionHook: bid below minimum");

        // Store revealed bid
        revealedBids[auctionId][msg.sender] = AuctionLib.Bid({
            bidder: msg.sender,
            amount: amount,
            commitment: commitment,
            revealed: true,
            timestamp: block.timestamp
        });

        // Update winning bid if this is higher
        if (amount > auction.winningBid) {
            auction.winningBid = amount;
            auction.winner = msg.sender;
        }

        emit BidRevealed(auctionId, msg.sender, amount);
    }

    /**
     * @notice End an auction and distribute rewards
     * @param auctionId The auction ID
     * @param poolId The pool ID
     */
    function _endAuction(bytes32 auctionId, PoolId poolId) internal {
        AuctionLib.Auction storage auction = auctions[auctionId];

        // If already complete, do nothing (idempotent)
        if (auction.isComplete) {
            return;
        }

        // Allow ending if auction has ended by time, even if isAuctionActive() returns false
        // This handles the case where time has passed but auction hasn't been auto-ended
        require(
            auction.isAuctionActive() || auction.isAuctionEnded(),
            "ShieldAuctionHook: auction not active"
        );
        require(auction.isAuctionEnded(), "ShieldAuctionHook: auction not ended");

        auction.isActive = false;
        auction.isComplete = true;

        // Clear active auction
        if (activeAuctions[poolId] == auctionId) {
            delete activeAuctions[poolId];
        }

        uint256 winningBid = auction.winningBid;
        address winner = auction.winner;

        if (winningBid > 0 && winner != address(0)) {
            // Collect payment from winner (simplified - in production, handle actual token transfers)
            // For now, we'll track the proceeds
            poolRewards[poolId] += winningBid;

            // Distribute rewards
            _distributeRewards(poolId, winningBid);
        }

        emit AuctionEnded(auctionId, poolId, winner, winningBid);
    }

    /**
     * @notice Manually end an auction (admin function)
     * @param auctionId The auction ID
     */
    function endAuction(bytes32 auctionId) external onlyOwner {
        AuctionLib.Auction storage auction = auctions[auctionId];
        // If auction is already complete, do nothing (idempotent)
        if (auction.isComplete) {
            return;
        }
        PoolId poolId = auction.poolId;
        _endAuction(auctionId, poolId);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim LP rewards for a pool
     * @param poolId The pool ID
     */
    function claimRewards(PoolId poolId) external nonReentrant {
        uint256 reward = lpRewards[poolId][msg.sender];
        require(reward > 0, "ShieldAuctionHook: no rewards to claim");

        lpRewards[poolId][msg.sender] = 0;

        // Transfer reward (simplified - in production, use actual token)
        // For now, we'll just emit the event
        emit RewardsClaimed(poolId, msg.sender, reward);

        // In production: Currency.wrap(address(0)).transfer(msg.sender, reward);
    }

    /**
     * @notice Distribute rewards from auction proceeds
     * @param poolId The pool ID
     * @param totalAmount The total amount to distribute
     */
    function _distributeRewards(PoolId poolId, uint256 totalAmount) internal {
        uint256 lpReward = (totalAmount * LP_REWARD_PERCENTAGE) / BASIS_POINTS;
        uint256 operatorReward = (totalAmount * AVS_REWARD_PERCENTAGE) / BASIS_POINTS;
        uint256 protocolFee = (totalAmount * PROTOCOL_FEE_PERCENTAGE) / BASIS_POINTS;
        // Note: gasCompensation is included in operatorReward for the winning bidder

        // Distribute LP rewards proportionally
        uint256 totalPoolLiquidity = totalLiquidity[poolId];
        if (totalPoolLiquidity > 0) {
            // Store rewards for LPs to claim (simplified distribution)
            // In production, calculate per-LP rewards based on their liquidity share
            poolRewards[poolId] += lpReward;
        }

        // Transfer protocol fee
        // In production: Currency.wrap(address(0)).transfer(feeRecipient, protocolFee);

        // Operator reward (including gas compensation) goes to the winning bidder (already handled)

        emit MEVDistributed(poolId, totalAmount, lpReward, operatorReward, protocolFee);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Authorize or deauthorize AVS operators
     * @param operator The operator address
     * @param authorized Whether to authorize or deauthorize
     */
    function setOperatorAuthorization(address operator, bool authorized) external onlyOwner {
        require(operator != address(0), "ShieldAuctionHook: invalid operator");
        authorizedOperators[operator] = authorized;

        if (authorized) {
            emit OperatorAuthorized(operator);
        } else {
            emit OperatorDeauthorized(operator);
        }
    }

    /**
     * @notice Update the LVR threshold
     * @param newThreshold The new LVR threshold in basis points
     */
    function setLVRThreshold(uint256 newThreshold) external onlyOwner {
        require(
            newThreshold > 0 && newThreshold <= BASIS_POINTS, "ShieldAuctionHook: invalid threshold"
        );
        uint256 oldThreshold = lvrThreshold;
        lvrThreshold = newThreshold;
        emit LVRThresholdUpdated(oldThreshold, newThreshold);
    }

    /**
     * @notice Update the fee recipient
     * @param newFeeRecipient The new fee recipient address
     */
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "ShieldAuctionHook: invalid address");
        feeRecipient = newFeeRecipient;
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if an auction should be triggered based on LVR
     * @param key The pool key
     * @param params The swap parameters
     * @return Whether to trigger an auction
     */
    function _shouldTriggerAuction(PoolKey calldata key, SwapParams calldata params)
        internal
        view
        returns (bool)
    {
        // Only trigger on significant swaps
        if (!_isSignificantSwap(params)) {
            return false;
        }

        // Get current pool price and external price
        uint256 poolPrice = _getPoolPrice(key);
        uint256 externalPrice = priceOracle.getPrice(key.currency0, key.currency1);

        // Handle edge cases
        if (poolPrice == 0 || externalPrice == 0) {
            return false;
        }

        // Check if price oracle data is stale
        if (priceOracle.isPriceStale(key.currency0, key.currency1)) {
            return false;
        }

        // Calculate price deviation
        uint256 priceDeviation;
        if (poolPrice > externalPrice) {
            priceDeviation = ((poolPrice - externalPrice) * BASIS_POINTS) / externalPrice;
        } else {
            priceDeviation = ((externalPrice - poolPrice) * BASIS_POINTS) / poolPrice;
        }

        // Trigger auction if deviation exceeds threshold
        return priceDeviation >= lvrThreshold;
    }

    /**
     * @notice Get the current pool price
     * @param key The pool key
     * @return The current pool price in 18 decimals
     */
    function _getPoolPrice(PoolKey calldata key) internal view returns (uint256) {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) {
            return 0;
        }

        // Convert sqrtPriceX96 to actual price
        // price = (sqrtPriceX96 / 2^96)^2
        // For token1/token0 price
        uint256 priceX96 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 Q96 = 2 ** 96;

        // Price in Q192 format, convert to 18 decimals
        // price = (priceX96 / Q96) * (10^18 / Q96) = priceX96 * 10^18 / Q96^2
        uint256 price = (priceX96 * 1e18) / (Q96 * Q96);

        return price;
    }

    /**
     * @notice Check if a swap is significant enough to trigger auction
     * @param params The swap parameters
     * @return Whether the swap is significant
     */
    function _isSignificantSwap(SwapParams calldata params) internal pure returns (bool) {
        // Only trigger on swaps with meaningful size
        // This is a simplified check - in production, use actual token amounts
        uint256 amount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);

        // Minimum swap size threshold (e.g., 0.1 ETH equivalent)
        uint256 minSwapSize = 1e17; // 0.1 ETH

        return amount >= minSwapSize;
    }
}
