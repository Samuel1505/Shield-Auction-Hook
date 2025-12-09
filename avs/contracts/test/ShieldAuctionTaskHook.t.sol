// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {ShieldAuctionTaskHook} from "../src/l2-contracts/ShieldAuctionTaskHook.sol";
import {ITaskMailboxTypes} from "@eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";

contract ShieldAuctionTaskHookTest is Test {
    ShieldAuctionTaskHook public taskHook;
    
    // Mock addresses
    address public constant MOCK_SHIELD_HOOK = address(0x1);
    address public constant MOCK_SERVICE_MANAGER = address(0x2);
    address public constant MOCK_CALLER = address(0x3);
    
    function setUp() public {
        taskHook = new ShieldAuctionTaskHook(MOCK_SHIELD_HOOK, MOCK_SERVICE_MANAGER);
        
        vm.label(MOCK_SHIELD_HOOK, "MainShieldHook");
        vm.label(MOCK_SERVICE_MANAGER, "ServiceManager");
        vm.label(MOCK_CALLER, "TaskCaller");
    }
    
    function testTaskHookDeployment() public {
        assertEq(taskHook.getShieldAuctionHook(), MOCK_SHIELD_HOOK);
        console.log("Task hook correctly references main Shield hook");
    }
    
    function testTaskTypeConstants() public {
        bytes32[] memory supportedTypes = taskHook.getSupportedTaskTypes();
        
        assertEq(supportedTypes.length, 4);
        console.log("Supports 4 Shield auction task types");
        
        // Test that task types are properly defined
        assertTrue(supportedTypes[0] != bytes32(0), "SHIELD_MONITORING type defined");
        assertTrue(supportedTypes[1] != bytes32(0), "AUCTION_CREATION type defined");
        assertTrue(supportedTypes[2] != bytes32(0), "BID_VALIDATION type defined");
        assertTrue(supportedTypes[3] != bytes32(0), "SETTLEMENT type defined");
    }
    
    function testTaskFeeStructure() public {
        bytes32 monitoringType = keccak256("SHIELD_MONITORING");
        uint96 fee = taskHook.getTaskTypeFee(monitoringType);
        
        assertGt(fee, 0, "Monitoring task should have non-zero fee");
        console.log("Shield monitoring task fee:", fee);
        
        bytes32 settlementType = keccak256("SETTLEMENT");
        uint96 settlementFee = taskHook.getTaskTypeFee(settlementType);
        
        assertGt(settlementFee, fee, "Settlement should cost more than monitoring");
        console.log("Settlement task fee:", settlementFee);
    }
    
    function testTaskValidationBasic() public {
        // Create a minimal task params structure
        bytes memory payload = abi.encodePacked(keccak256("SHIELD_MONITORING"));
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            payload: payload
        });
        
        // This should not revert for valid task type
        try taskHook.validatePreTaskCreation(MOCK_CALLER, taskParams) {
            console.log("Basic task validation passed");
        } catch {
            fail("Basic task validation should not revert");
        }
    }
    
    function testConnectorPattern() public {
        // Test that this is a connector, not business logic
        console.log("Testing L2 connector pattern");
        
        // The task hook should:
        // 1. Interface with EigenLayer task system
        // 2. Reference the main Shield hook (business logic)
        // 3. NOT implement auction logic itself
        
        assertEq(taskHook.getShieldAuctionHook(), MOCK_SHIELD_HOOK, "Should reference main hook");
        
        // Test that it calculates fees (coordination function)
        bytes memory payload = abi.encodePacked(keccak256("SHIELD_MONITORING"));
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            payload: payload
        });
        
        uint96 fee = taskHook.calculateTaskFee(taskParams);
        assertGt(fee, 0, "Should calculate task fees");
        
        console.log("L2 connector pattern test passed");
    }
    
    function testInvalidTaskType() public {
        bytes memory invalidPayload = abi.encodePacked(keccak256("INVALID_TYPE"));
        
        ITaskMailboxTypes.TaskParams memory taskParams = ITaskMailboxTypes.TaskParams({
            payload: invalidPayload
        });
        
        // Should revert for unsupported task type
        vm.expectRevert("Unsupported task type");
        taskHook.validatePreTaskCreation(MOCK_CALLER, taskParams);
        
        console.log("Invalid task type properly rejected");
    }
}

