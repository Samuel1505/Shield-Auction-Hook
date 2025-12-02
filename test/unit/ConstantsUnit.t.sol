// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestFixture} from "../utils/TestFixture.sol";

/**
 * @title ConstantsUnit
 * @notice Unit tests for constants
 */
contract ConstantsUnit is TestFixture {

    // Test MIN_BID constant
    function test_MIN_BID_constant() public view {
        assertEq(hook.MIN_BID(), 1e15);
    }

    // Test MAX_AUCTION_DURATION constant
    function test_MAX_AUCTION_DURATION_constant() public view {
        assertEq(hook.MAX_AUCTION_DURATION(), 12);
    }

    // Test LP_REWARD_PERCENTAGE constant
    function test_LP_REWARD_PERCENTAGE_constant() public view {
        assertEq(hook.LP_REWARD_PERCENTAGE(), 8500);
    }

    // Test AVS_REWARD_PERCENTAGE constant
    function test_AVS_REWARD_PERCENTAGE_constant() public view {
        assertEq(hook.AVS_REWARD_PERCENTAGE(), 1000);
    }

    // Test PROTOCOL_FEE_PERCENTAGE constant
    function test_PROTOCOL_FEE_PERCENTAGE_constant() public view {
        assertEq(hook.PROTOCOL_FEE_PERCENTAGE(), 300);
    }

    // Test GAS_COMPENSATION_PERCENTAGE constant
    function test_GAS_COMPENSATION_PERCENTAGE_constant() public view {
        assertEq(hook.GAS_COMPENSATION_PERCENTAGE(), 200);
    }

    // Test BASIS_POINTS constant
    function test_BASIS_POINTS_constant() public view {
        assertEq(hook.BASIS_POINTS(), 10000);
    }

    // Test constants sum correctly
    function test_constantsSumCorrectly() public view {
        uint256 total = hook.LP_REWARD_PERCENTAGE() + 
                       hook.AVS_REWARD_PERCENTAGE() + 
                       hook.PROTOCOL_FEE_PERCENTAGE() + 
                       hook.GAS_COMPENSATION_PERCENTAGE();
        assertEq(total, hook.BASIS_POINTS());
    }

    // Test MIN_BID is positive
    function test_MIN_BID_positive() public view {
        assertGt(hook.MIN_BID(), 0);
    }

    // Test MAX_AUCTION_DURATION is positive
    function test_MAX_AUCTION_DURATION_positive() public view {
        assertGt(hook.MAX_AUCTION_DURATION(), 0);
    }

    // Test LP_REWARD_PERCENTAGE is less than BASIS_POINTS
    function test_LP_REWARD_PERCENTAGE_lessThanBasisPoints() public view {
        assertLt(hook.LP_REWARD_PERCENTAGE(), hook.BASIS_POINTS());
    }

    // Test AVS_REWARD_PERCENTAGE is less than BASIS_POINTS
    function test_AVS_REWARD_PERCENTAGE_lessThanBasisPoints() public view {
        assertLt(hook.AVS_REWARD_PERCENTAGE(), hook.BASIS_POINTS());
    }

    // Test PROTOCOL_FEE_PERCENTAGE is less than BASIS_POINTS
    function test_PROTOCOL_FEE_PERCENTAGE_lessThanBasisPoints() public view {
        assertLt(hook.PROTOCOL_FEE_PERCENTAGE(), hook.BASIS_POINTS());
    }

    // Test GAS_COMPENSATION_PERCENTAGE is less than BASIS_POINTS
    function test_GAS_COMPENSATION_PERCENTAGE_lessThanBasisPoints() public view {
        assertLt(hook.GAS_COMPENSATION_PERCENTAGE(), hook.BASIS_POINTS());
    }

    // Test MIN_BID is reasonable (not too large)
    function test_MIN_BID_reasonable() public view {
        assertLt(hook.MIN_BID(), 1 ether);
    }

    // Test MAX_AUCTION_DURATION is reasonable
    function test_MAX_AUCTION_DURATION_reasonable() public view {
        assertLe(hook.MAX_AUCTION_DURATION(), 60); // Should be less than a minute
    }

    // Test LP_REWARD_PERCENTAGE is majority
    function test_LP_REWARD_PERCENTAGE_majority() public view {
        assertGt(hook.LP_REWARD_PERCENTAGE(), hook.BASIS_POINTS() / 2);
    }

    // Test reward percentages are non-zero
    function test_rewardPercentages_nonZero() public view {
        assertGt(hook.LP_REWARD_PERCENTAGE(), 0);
        assertGt(hook.AVS_REWARD_PERCENTAGE(), 0);
        assertGt(hook.PROTOCOL_FEE_PERCENTAGE(), 0);
        assertGt(hook.GAS_COMPENSATION_PERCENTAGE(), 0);
    }

    // Test BASIS_POINTS is standard value
    function test_BASIS_POINTS_standard() public view {
        assertEq(hook.BASIS_POINTS(), 10000);
    }

    // Test MIN_BID precision
    function test_MIN_BID_precision() public view {
        assertEq(hook.MIN_BID(), 1000000000000000); // 0.001 ETH in wei
    }

    // Test constants are immutable
    function test_constants_immutable() public view {
        // Constants should not change - verify they're the same on multiple calls
        uint256 minBid1 = hook.MIN_BID();
        uint256 minBid2 = hook.MIN_BID();
        assertEq(minBid1, minBid2);
    }

    // Test percentage relationships
    function test_percentageRelationships() public view {
        // LP reward should be largest
        assertGt(hook.LP_REWARD_PERCENTAGE(), hook.AVS_REWARD_PERCENTAGE());
        assertGt(hook.LP_REWARD_PERCENTAGE(), hook.PROTOCOL_FEE_PERCENTAGE());
        assertGt(hook.LP_REWARD_PERCENTAGE(), hook.GAS_COMPENSATION_PERCENTAGE());
        
        // AVS reward should be second largest
        assertGt(hook.AVS_REWARD_PERCENTAGE(), hook.PROTOCOL_FEE_PERCENTAGE());
        assertGt(hook.AVS_REWARD_PERCENTAGE(), hook.GAS_COMPENSATION_PERCENTAGE());
        
        // Protocol fee should be larger than gas compensation
        assertGt(hook.PROTOCOL_FEE_PERCENTAGE(), hook.GAS_COMPENSATION_PERCENTAGE());
    }
}

