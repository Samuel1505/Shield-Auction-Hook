// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IAVSDirectory
 * @notice Interface for EigenLayer AVS Directory
 * @dev This interface matches the EigenLayer AVSDirectory contract
 */
interface IAVSDirectory {
    /**
     * @notice Enum representing the registration status of an operator with an AVS
     */
    enum OperatorAVSRegistrationStatus {
        UNREGISTERED, // Operator not registered to AVS
        REGISTERED // Operator registered to AVS
    }

    /**
     * @notice Signature structure for operator registration
     */
    struct SignatureWithSaltAndExpiry {
        bytes signature;
        bytes32 salt;
        uint256 expiry;
    }

    /**
     * @notice Returns the registration status of each operator for a given AVS
     * @param avs The AVS address
     * @param operator The operator address
     * @return The registration status
     */
    function avsOperatorStatus(address avs, address operator)
        external
        view
        returns (OperatorAVSRegistrationStatus);

    /**
     * @notice Register an operator to an AVS
     * @param operator The operator address
     * @param operatorSignature The signature, salt, and expiry
     */
    function registerOperatorToAVS(
        address operator,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external;

    /**
     * @notice Deregister an operator from an AVS
     * @param operator The operator address
     */
    function deregisterOperatorFromAVS(address operator) external;
}
