// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ShieldAuctionServiceManager
 * @notice Simplified L1 service manager for Shield Auction AVS
 * @dev This is a simplified version that doesn't depend on EigenLayer contracts
 * This contract handles:
 * - Operator registration
 * - Staking management
 * - Task validation (delegates to L2 hook for actual auction logic)
 */
contract ShieldAuctionServiceManager is Ownable, ReentrancyGuard {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Address of the main Shield Auction Hook contract on L2
    address public immutable shieldAuctionHookL2;
    
    /// @notice Minimum stake required for Shield auction operators
    uint256 public constant MINIMUM_SHIELD_STAKE = 10 ether;
    
    /// @notice Mapping of registered operators
    mapping(address => bool) public isRegisteredOperator;
    
    /// @notice Mapping of operator stakes
    mapping(address => uint256) public operatorStakes;
    
    /// @notice Total registered operators
    uint256 public totalOperators;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event ShieldOperatorRegistered(address indexed operator, uint256 stake);
    event ShieldOperatorDeregistered(address indexed operator);
    event ShieldAuctionHookUpdated(address indexed oldHook, address indexed newHook);
    event StakeUpdated(address indexed operator, uint256 oldStake, uint256 newStake);
    
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Constructor for the Shield Auction Service Manager
     * @param _shieldAuctionHookL2 The address of the main Shield Auction Hook on L2
     */
    constructor(address _shieldAuctionHookL2) Ownable(msg.sender) {
        require(_shieldAuctionHookL2 != address(0), "Invalid L2 hook address");
        shieldAuctionHookL2 = _shieldAuctionHookL2;
    }
    
    /*//////////////////////////////////////////////////////////////
                            OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Register a new Shield auction operator
     * @param operator The operator address to register
     */
    function registerOperator(address operator) external onlyOwner {
        require(operator != address(0), "Invalid operator address");
        require(!isRegisteredOperator[operator], "Operator already registered");
        
        isRegisteredOperator[operator] = true;
        totalOperators++;
        
        emit ShieldOperatorRegistered(operator, 0);
    }
    
    /**
     * @notice Deregister a Shield auction operator
     * @param operator The operator address to deregister
     */
    function deregisterOperator(address operator) external onlyOwner {
        require(isRegisteredOperator[operator], "Operator not registered");
        
        isRegisteredOperator[operator] = false;
        totalOperators--;
        
        emit ShieldOperatorDeregistered(operator);
    }
    
    /**
     * @notice Update operator stake
     * @param operator The operator address
     * @param newStake The new stake amount
     */
    function updateOperatorStake(address operator, uint256 newStake) external onlyOwner {
        require(isRegisteredOperator[operator], "Operator not registered");
        
        uint256 oldStake = operatorStakes[operator];
        operatorStakes[operator] = newStake;
        
        emit StakeUpdated(operator, oldStake, newStake);
    }
    
    /*//////////////////////////////////////////////////////////////
                            TASK MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Submit a price discrepancy for auction initiation
     * @param poolId The pool identifier
     * @param dexPrice The DEX price
     * @param cexPrice The CEX price
     */
    function submitPriceDiscrepancy(
        bytes32 poolId,
        uint256 dexPrice,
        uint256 cexPrice
    ) external {
        require(isRegisteredOperator[msg.sender], "Only registered operators");
        require(dexPrice > 0 && cexPrice > 0, "Invalid prices");
        
        // Delegate to L2 hook for actual processing
        // This would typically involve cross-chain communication
        emit PriceDiscrepancySubmitted(poolId, dexPrice, cexPrice);
    }
    
    /**
     * @notice Submit a sealed bid for an auction
     * @param auctionId The auction identifier
     * @param sealedBid The sealed bid hash
     */
    function submitSealedBid(bytes32 auctionId, bytes32 sealedBid) external {
        require(isRegisteredOperator[msg.sender], "Only registered operators");
        require(auctionId != bytes32(0), "Invalid auction ID");
        require(sealedBid != bytes32(0), "Invalid sealed bid");
        
        // Delegate to L2 hook for actual processing
        emit SealedBidSubmitted(auctionId, msg.sender, sealedBid);
    }
    
    /**
     * @notice Reveal a sealed bid
     * @param auctionId The auction identifier
     * @param bidAmount The bid amount
     * @param nonce The nonce used for sealing
     */
    function revealBid(bytes32 auctionId, uint256 bidAmount, uint256 nonce) external {
        require(isRegisteredOperator[msg.sender], "Only registered operators");
        require(auctionId != bytes32(0), "Invalid auction ID");
        require(bidAmount > 0, "Invalid bid amount");
        
        // Delegate to L2 hook for actual processing
        emit BidRevealed(auctionId, msg.sender, bidAmount);
    }
    
    /**
     * @notice Finalize an auction
     * @param auctionId The auction identifier
     */
    function finalizeAuction(bytes32 auctionId) external {
        require(isRegisteredOperator[msg.sender], "Only registered operators");
        require(auctionId != bytes32(0), "Invalid auction ID");
        
        // Delegate to L2 hook for actual processing
        emit AuctionFinalized(auctionId, address(0), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Check if an operator is registered
     * @param operator The operator address
     * @return True if registered, false otherwise
     */
    function isOperatorRegistered(address operator) external view returns (bool) {
        return isRegisteredOperator[operator];
    }
    
    /**
     * @notice Get operator information
     * @param operator The operator address
     * @return registered Whether the operator is registered
     * @return stake The operator's stake amount
     */
    function getOperatorInfo(address operator) external view returns (bool registered, uint256 stake) {
        return (isRegisteredOperator[operator], operatorStakes[operator]);
    }
    
    /**
     * @notice Get total number of registered operators
     * @return The total number of operators
     */
    function getTotalOperators() external view returns (uint256) {
        return totalOperators;
    }
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PriceDiscrepancySubmitted(bytes32 indexed poolId, uint256 dexPrice, uint256 cexPrice);
    event SealedBidSubmitted(bytes32 indexed auctionId, address indexed bidder, bytes32 sealedBid);
    event BidRevealed(bytes32 indexed auctionId, address indexed bidder, uint256 bidAmount);
    event AuctionFinalized(bytes32 indexed auctionId, address indexed winner, uint256 winningBid);
}

