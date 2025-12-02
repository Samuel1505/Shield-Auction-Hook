// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAVSDirectory} from "../../src/interfaces/IAVSDirectory.sol";

/**
 * @title MockAVSDirectory
 * @notice Mock implementation of IAVSDirectory for testing
 */
contract MockAVSDirectory is IAVSDirectory {
    mapping(address => mapping(address => OperatorAVSRegistrationStatus)) public avsOperatorStatuses;
    
    function setOperatorStatus(
        address avs,
        address operator,
        OperatorAVSRegistrationStatus status
    ) external {
        avsOperatorStatuses[avs][operator] = status;
    }
    
    function avsOperatorStatus(
        address avs,
        address operator
    ) external view override returns (OperatorAVSRegistrationStatus) {
        return avsOperatorStatuses[avs][operator];
    }
    
    function registerOperatorToAVS(
        address operator,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external override {
        avsOperatorStatuses[msg.sender][operator] = OperatorAVSRegistrationStatus.REGISTERED;
    }
    
    function deregisterOperatorFromAVS(address operator) external override {
        avsOperatorStatuses[msg.sender][operator] = OperatorAVSRegistrationStatus.UNREGISTERED;
    }
}

