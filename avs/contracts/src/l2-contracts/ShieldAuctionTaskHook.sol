// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ShieldAuctionTaskHook
 * @notice Simplified L2 task hook for Shield Auction AVS
 * @dev This is a simplified version that doesn't depend on EigenLayer contracts
 * This contract handles:
 * - Task validation
 * - Task execution coordination
 * - Fee calculation
 */
contract ShieldAuctionTaskHook is Ownable, ReentrancyGuard {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Address of the main Shield Auction Hook contract
    address public immutable shieldAuctionHook;
    
    /// @notice Address of the L1 service manager
    address public immutable serviceManager;
    
    /// @notice Base task fee in wei
    uint256 public constant BASE_TASK_FEE = 0.001 ether;
    
    /// @notice Task fee multiplier (in basis points)
    uint256 public constant TASK_FEE_MULTIPLIER = 10000; // 100%
    
    /// @notice Mapping of task types to their specific fees
    mapping(string => uint256) public taskTypeFees;
    
    /// @notice Mapping of task IDs to their information
    mapping(bytes32 => TaskInfo) public tasks;
    
    /// @notice Total tasks created
    uint256 public totalTasks;
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct TaskInfo {
        bytes32 taskId;
        string taskType;
        address creator;
        uint256 createdAt;
        uint256 fee;
        bool isCompleted;
        bytes resultData;
    }
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TaskCreated(bytes32 indexed taskId, string taskType, address indexed creator, uint256 fee);
    event TaskCompleted(bytes32 indexed taskId, bytes resultData);
    event TaskFeeUpdated(string taskType, uint256 oldFee, uint256 newFee);
    
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Constructor for the Shield Auction Task Hook
     * @param _shieldAuctionHook The address of the main Shield Auction Hook
     * @param _serviceManager The address of the L1 service manager
     */
    constructor(address _shieldAuctionHook, address _serviceManager) Ownable(msg.sender) {
        require(_shieldAuctionHook != address(0), "Invalid hook address");
        require(_serviceManager != address(0), "Invalid service manager address");
        shieldAuctionHook = _shieldAuctionHook;
        serviceManager = _serviceManager;
        // Initialize default task type fees
        taskTypeFees["price_monitoring"] = BASE_TASK_FEE;
        taskTypeFees["auction_coordination"] = BASE_TASK_FEE * 2;
        taskTypeFees["auction_resolution"] = BASE_TASK_FEE * 3;
        taskTypeFees["proceeds_distribution"] = BASE_TASK_FEE * 2;
    }
    
    /*//////////////////////////////////////////////////////////////
                            TASK VALIDATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Validate task data before creation
     * @param taskData The task data to validate
     * @return True if valid, false otherwise
     */
    function validatePreTaskCreation(bytes calldata taskData) external pure returns (bool) {
        // Basic validation - check if task data is not empty
        return taskData.length > 0;
    }
    
    /**
     * @notice Handle post-task creation logic
     * @param taskId The task identifier
     * @param taskData The task data
     */
    function handlePostTaskCreation(bytes32 taskId, bytes calldata taskData) external {
        require(taskId != bytes32(0), "Invalid task ID");
        require(taskData.length > 0, "Invalid task data");
        
        // Parse task type from data (simplified)
        string memory taskType = "unknown";
        if (taskData.length >= 4) {
            bytes4 selector = bytes4(taskData[0:4]);
            if (selector == 0x12345678) {
                taskType = "price_monitoring";
            } else if (selector == 0x87654321) {
                taskType = "auction_coordination";
            } else if (selector == 0x11111111) {
                taskType = "auction_resolution";
            } else if (selector == 0x22222222) {
                taskType = "proceeds_distribution";
            }
        }
        
        uint256 fee = calculateTaskFee(taskId, taskData);
        
        tasks[taskId] = TaskInfo({
            taskId: taskId,
            taskType: taskType,
            creator: msg.sender,
            createdAt: block.timestamp,
            fee: fee,
            isCompleted: false,
            resultData: ""
        });
        
        totalTasks++;
        
        emit TaskCreated(taskId, taskType, msg.sender, fee);
    }
    
    /**
     * @notice Validate task result data before submission
     * @param taskId The task identifier
     * @param resultData The result data to validate
     * @return True if valid, false otherwise
     */
    function validatePreTaskResultSubmission(bytes32 taskId, bytes calldata resultData) external view returns (bool) {
        require(tasks[taskId].taskId != bytes32(0), "Task not found");
        require(!tasks[taskId].isCompleted, "Task already completed");
        require(resultData.length > 0, "Invalid result data");
        
        return true;
    }
    
    /**
     * @notice Handle post-task result submission logic
     * @param taskId The task identifier
     * @param resultData The result data
     */
    function handlePostTaskResultSubmission(bytes32 taskId, bytes calldata resultData) external {
        require(tasks[taskId].taskId != bytes32(0), "Task not found");
        require(!tasks[taskId].isCompleted, "Task already completed");
        require(resultData.length > 0, "Invalid result data");
        
        tasks[taskId].isCompleted = true;
        tasks[taskId].resultData = resultData;
        
        emit TaskCompleted(taskId, resultData);
    }
    
    /**
     * @notice Calculate the fee for a task
     * @param taskId The task identifier
     * @param taskData The task data
     * @return The calculated fee
     */
    function calculateTaskFee(bytes32 taskId, bytes calldata taskData) public view returns (uint256) {
        // Parse task type from data (simplified)
        string memory taskType = "unknown";
        if (taskData.length >= 4) {
            bytes4 selector = bytes4(taskData[0:4]);
            if (selector == 0x12345678) {
                taskType = "price_monitoring";
            } else if (selector == 0x87654321) {
                taskType = "auction_coordination";
            } else if (selector == 0x11111111) {
                taskType = "auction_resolution";
            } else if (selector == 0x22222222) {
                taskType = "proceeds_distribution";
            }
        }
        
        return taskTypeFees[taskType];
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update task type fee
     * @param taskType The task type
     * @param newFee The new fee
     */
    function updateTaskTypeFee(string calldata taskType, uint256 newFee) external onlyOwner {
        require(newFee > 0, "Invalid fee");
        
        uint256 oldFee = taskTypeFees[taskType];
        taskTypeFees[taskType] = newFee;
        
        emit TaskFeeUpdated(taskType, oldFee, newFee);
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get task information
     * @param taskId The task identifier
     * @return The task information
     */
    function getTaskInfo(bytes32 taskId) external view returns (TaskInfo memory) {
        return tasks[taskId];
    }
    
    /**
     * @notice Check if a task is valid
     * @param taskId The task identifier
     * @return True if valid, false otherwise
     */
    function isTaskValid(bytes32 taskId) external view returns (bool) {
        return tasks[taskId].taskId != bytes32(0);
    }
    
    /**
     * @notice Get total number of tasks
     * @return The total number of tasks
     */
    function getTotalTasks() external view returns (uint256) {
        return totalTasks;
    }
    
    /**
     * @notice Get the Shield Auction Hook address
     * @return The address of the main Shield Auction Hook
     */
    function getShieldAuctionHook() external view returns (address) {
        return shieldAuctionHook;
    }
}

