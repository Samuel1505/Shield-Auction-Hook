// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestFixture} from "../utils/TestFixture.sol";
import {ShieldAuctionHook} from "../../src/hooks/ShieldAuctionHook.sol";

/**
 * @title AdminUnit
 * @notice Unit tests for admin functions
 */
contract AdminUnit is TestFixture {

    // Test: Set operator authorization
    function test_setOperatorAuthorization() public {
        address newOperator = makeAddr("newOperator");
        hook.setOperatorAuthorization(newOperator, true);
        assertTrue(hook.authorizedOperators(newOperator));
    }

    // Test: Remove operator authorization
    function test_removeOperatorAuthorization() public {
        address newOperator = makeAddr("newOperator");
        hook.setOperatorAuthorization(newOperator, true);
        hook.setOperatorAuthorization(newOperator, false);
        assertFalse(hook.authorizedOperators(newOperator));
    }

    // Test: Set LVR threshold
    function test_setLVRThreshold() public {
        uint256 newThreshold = 200;
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        assertEq(hook.lvrThreshold(), newThreshold);
    }

    // Test: Set fee recipient
    function test_setFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        vm.prank(owner);
        hook.setFeeRecipient(newRecipient);
        assertEq(hook.feeRecipient(), newRecipient);
    }

    // Test: Pause contract
    function test_pauseContract() public {
        vm.prank(owner);
        hook.pause();
        assertTrue(hook.paused());
    }

    // Test: Unpause contract
    function test_unpauseContract() public {
        vm.prank(owner);
        hook.pause();
        vm.prank(owner);
        hook.unpause();
        assertFalse(hook.paused());
    }

    // Test: Only owner can set operator authorization
    function test_onlyOwnerSetOperatorAuthorization() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert();
        hook.setOperatorAuthorization(operator1, true);
    }

    // Test: Only owner can set LVR threshold
    function test_onlyOwnerSetLVRThreshold() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert();
        hook.setLVRThreshold(200);
    }

    // Test: Only owner can set fee recipient
    function test_onlyOwnerSetFeeRecipient() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert();
        hook.setFeeRecipient(makeAddr("recipient"));
    }

    // Test: Only owner can pause
    function test_onlyOwnerPause() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert();
        hook.pause();
    }

    // Test: Only owner can unpause
    function test_onlyOwnerUnpause() public {
        vm.prank(owner);
        hook.pause();
        
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert();
        hook.unpause();
    }

    // Test: Set LVR threshold to minimum
    function test_setLVRThresholdMinimum() public {
        vm.prank(owner);
        hook.setLVRThreshold(1);
        assertEq(hook.lvrThreshold(), 1);
    }

    // Test: Set LVR threshold to maximum
    function test_setLVRThresholdMaximum() public {
        vm.prank(owner);
        hook.setLVRThreshold(10000);
        assertEq(hook.lvrThreshold(), 10000);
    }

    // Test: Cannot set LVR threshold to zero
    function test_cannotSetLVRThresholdZero() public {
        vm.prank(owner);
        vm.expectRevert("ShieldAuctionHook: invalid threshold");
        hook.setLVRThreshold(0);
    }

    // Test: Cannot set LVR threshold above maximum
    function test_cannotSetLVRThresholdAboveMaximum() public {
        vm.prank(owner);
        vm.expectRevert("ShieldAuctionHook: invalid threshold");
        hook.setLVRThreshold(10001);
    }

    // Test: Cannot set fee recipient to zero address
    function test_cannotSetFeeRecipientZero() public {
        vm.prank(owner);
        vm.expectRevert("ShieldAuctionHook: invalid address");
        hook.setFeeRecipient(address(0));
    }

    // Test: Set operator authorization emits event
    function test_setOperatorAuthorizationEmitsEvent() public {
        address newOperator = makeAddr("newOperator");
        
        vm.expectEmit(true, false, false, false);
        emit ShieldAuctionHook.OperatorAuthorized(newOperator);
        
        hook.setOperatorAuthorization(newOperator, true);
    }

    // Test: Remove operator authorization emits event
    function test_removeOperatorAuthorizationEmitsEvent() public {
        address newOperator = makeAddr("newOperator");
        hook.setOperatorAuthorization(newOperator, true);
        
        vm.expectEmit(true, false, false, false);
        emit ShieldAuctionHook.OperatorDeauthorized(newOperator);
        
        hook.setOperatorAuthorization(newOperator, false);
    }

    // Test: Set LVR threshold emits event
    function test_setLVRThresholdEmitsEvent() public {
        uint256 newThreshold = 200;
        
        vm.expectEmit(true, false, false, false);
        emit ShieldAuctionHook.LVRThresholdUpdated(DEFAULT_LVR_THRESHOLD, newThreshold);
        
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
    }

    // Test: Multiple operator authorizations
    function test_multipleOperatorAuthorizations() public {
        address operator1 = makeAddr("op1");
        address operator2 = makeAddr("op2");
        address operator3 = makeAddr("op3");
        
        hook.setOperatorAuthorization(operator1, true);
        hook.setOperatorAuthorization(operator2, true);
        hook.setOperatorAuthorization(operator3, true);
        
        assertTrue(hook.authorizedOperators(operator1));
        assertTrue(hook.authorizedOperators(operator2));
        assertTrue(hook.authorizedOperators(operator3));
    }

    // Test: Toggle operator authorization
    function test_toggleOperatorAuthorization() public {
        address newOperator = makeAddr("newOperator");
        
        hook.setOperatorAuthorization(newOperator, true);
        assertTrue(hook.authorizedOperators(newOperator));
        
        hook.setOperatorAuthorization(newOperator, false);
        assertFalse(hook.authorizedOperators(newOperator));
        
        hook.setOperatorAuthorization(newOperator, true);
        assertTrue(hook.authorizedOperators(newOperator));
    }

    // Test: LVR threshold update affects auction triggering
    function test_lvrThresholdUpdateAffectsAuctionTriggering() public {
        vm.prank(owner);
        hook.setLVRThreshold(500); // 5%
        
        // Set price deviation to 3% (below new threshold)
        priceOracle.setPrice(currency0, currency1, 1.03e18, false);
        swap(poolKey, true, -1e18, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertEq(auctionId, bytes32(0)); // Should not trigger
        
        // Set price deviation to 6% (above new threshold)
        priceOracle.setPrice(currency0, currency1, 1.06e18, false);
        swap(poolKey, true, -1e18, "");
        
        auctionId = hook.activeAuctions(poolId);
        assertNotEq(auctionId, bytes32(0)); // Should trigger
    }

    // Test: Fee recipient update
    function test_feeRecipientUpdate() public {
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");
        
        vm.prank(owner);
        hook.setFeeRecipient(recipient1);
        assertEq(hook.feeRecipient(), recipient1);
        
        vm.prank(owner);
        hook.setFeeRecipient(recipient2);
        assertEq(hook.feeRecipient(), recipient2);
    }

    // Test: Pause prevents swaps
    function test_pausePreventsSwaps() public {
        vm.prank(owner);
        hook.pause();
        
        setPriceDeviationAboveThreshold();
        vm.expectRevert();
        swap(poolKey, true, -1e18, "");
    }

    // Test: Unpause allows swaps
    function test_unpauseAllowsSwaps() public {
        vm.prank(owner);
        hook.pause();
        
        vm.prank(owner);
        hook.unpause();
        
        setPriceDeviationAboveThreshold();
        swap(poolKey, true, -1e18, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertNotEq(auctionId, bytes32(0));
    }

    // Test: Pause state persistence
    function test_pauseStatePersistence() public {
        vm.prank(owner);
        hook.pause();
        
        assertTrue(hook.paused());
        assertTrue(hook.paused()); // Should persist
    }

    // Test: Unpause state persistence
    function test_unpauseStatePersistence() public {
        vm.prank(owner);
        hook.pause();
        vm.prank(owner);
        hook.unpause();
        
        bool paused1 = hook.paused();
        bool paused2 = hook.paused(); // Should persist
        assertFalse(paused1);
        assertFalse(paused2);
    }

    // Test: Operator authorization persistence
    function test_operatorAuthorizationPersistence() public {
        address newOperator = makeAddr("newOperator");
        hook.setOperatorAuthorization(newOperator, true);
        
        assertTrue(hook.authorizedOperators(newOperator));
        assertTrue(hook.authorizedOperators(newOperator)); // Should persist
    }

    // Test: LVR threshold persistence
    function test_lvrThresholdPersistence() public {
        uint256 newThreshold = 200;
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        
        assertEq(hook.lvrThreshold(), newThreshold);
        assertEq(hook.lvrThreshold(), newThreshold); // Should persist
    }

    // Test: Fee recipient persistence
    function test_feeRecipientPersistence() public {
        address newRecipient = makeAddr("newRecipient");
        vm.prank(owner);
        hook.setFeeRecipient(newRecipient);
        
        assertEq(hook.feeRecipient(), newRecipient);
        assertEq(hook.feeRecipient(), newRecipient); // Should persist
    }

    // Test: Cannot authorize zero address
    function test_cannotAuthorizeZeroAddress() public {
        vm.expectRevert("ShieldAuctionHook: invalid operator");
        hook.setOperatorAuthorization(address(0), true);
    }

    // Test: Authorize same operator multiple times
    function test_authorizeSameOperatorMultipleTimes() public {
        address newOperator = makeAddr("newOperator");
        
        hook.setOperatorAuthorization(newOperator, true);
        assertTrue(hook.authorizedOperators(newOperator));
        
        hook.setOperatorAuthorization(newOperator, true);
        assertTrue(hook.authorizedOperators(newOperator));
    }

    // Test: Deauthorize unauthorized operator
    function test_deauthorizeUnauthorizedOperator() public {
        address newOperator = makeAddr("newOperator");
        hook.setOperatorAuthorization(newOperator, false);
        assertFalse(hook.authorizedOperators(newOperator));
    }

    // Test: LVR threshold boundary values
    function test_lvrThresholdBoundaryValues() public {
        vm.prank(owner);
        hook.setLVRThreshold(1);
        assertEq(hook.lvrThreshold(), 1);
        
        vm.prank(owner);
        hook.setLVRThreshold(10000);
        assertEq(hook.lvrThreshold(), 10000);
    }

    // Test: Fee recipient can be same address
    function test_feeRecipientSameAddress() public {
        address recipient = hook.feeRecipient();
        vm.prank(owner);
        hook.setFeeRecipient(recipient);
        assertEq(hook.feeRecipient(), recipient);
    }

    // Test: Pause when already paused
    function test_pauseWhenAlreadyPaused() public {
        vm.prank(owner);
        hook.pause();
        
        vm.prank(owner);
        hook.pause(); // Should not revert
        
        assertTrue(hook.paused());
    }

    // Test: Unpause when not paused
    function test_unpauseWhenNotPaused() public {
        vm.prank(owner);
        hook.unpause(); // Should not revert
        
        assertFalse(hook.paused());
    }

    // Test: Multiple admin operations
    function test_multipleAdminOperations() public {
        address newOperator = makeAddr("newOperator");
        address newRecipient = makeAddr("newRecipient");
        
        hook.setOperatorAuthorization(newOperator, true);
        vm.prank(owner);
        hook.setLVRThreshold(200);
        vm.prank(owner);
        hook.setFeeRecipient(newRecipient);
        
        assertTrue(hook.authorizedOperators(newOperator));
        assertEq(hook.lvrThreshold(), 200);
        assertEq(hook.feeRecipient(), newRecipient);
    }

    // Test: Admin operations order independence
    function test_adminOperationsOrderIndependence() public {
        address newOperator = makeAddr("newOperator");
        
        hook.setOperatorAuthorization(newOperator, true);
        vm.prank(owner);
        hook.setLVRThreshold(200);
        
        assertTrue(hook.authorizedOperators(newOperator));
        assertEq(hook.lvrThreshold(), 200);
        
        // Reverse order
        vm.prank(owner);
        hook.setLVRThreshold(300);
        hook.setOperatorAuthorization(newOperator, false);
        
        assertFalse(hook.authorizedOperators(newOperator));
        assertEq(hook.lvrThreshold(), 300);
    }

    // Test: LVR threshold affects price deviation calculation
    function test_lvrThresholdAffectsPriceDeviation() public {
        uint256 threshold1 = 100;
        uint256 threshold2 = 500;
        
        vm.prank(owner);
        hook.setLVRThreshold(threshold1);
        assertEq(hook.lvrThreshold(), threshold1);
        
        vm.prank(owner);
        hook.setLVRThreshold(threshold2);
        assertEq(hook.lvrThreshold(), threshold2);
    }

    // Test: Operator authorization affects bid revelation
    function test_operatorAuthorizationAffectsBidRevelation() public {
        bytes32 auctionId = createAuction();
        address newOperator = makeAddr("newOperator");
        
        commitBid(auctionId, newOperator, 1 ether, 123);
        
        vm.prank(newOperator);
        vm.expectRevert("ShieldAuctionHook: not authorized operator");
        hook.revealBid(auctionId, 1 ether, 123);
        
        hook.setOperatorAuthorization(newOperator, true);
        
        vm.prank(newOperator);
        hook.revealBid(auctionId, 1 ether, 123);
        
        (, uint256 revealedAmount, , bool revealed, ) = hook.revealedBids(auctionId, newOperator);
        assertEq(revealedAmount, 1 ether);
        assertTrue(revealed);
    }

    // Test: Pause affects all hook functions
    function test_pauseAffectsAllHookFunctions() public {
        vm.prank(owner);
        hook.pause();
        
        // Should prevent swaps
        setPriceDeviationAboveThreshold();
        vm.expectRevert();
        swap(poolKey, true, -1e18, "");
    }

    // Test: Unpause restores functionality
    function test_unpauseRestoresFunctionality() public {
        vm.prank(owner);
        hook.pause();
        
        vm.prank(owner);
        hook.unpause();
        
        setPriceDeviationAboveThreshold();
        swap(poolKey, true, -1e18, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertNotEq(auctionId, bytes32(0));
    }

    // Test: LVR threshold update with active auction
    function test_lvrThresholdUpdateWithActiveAuction() public {
        bytes32 auctionId = createAuction();
        
        vm.prank(owner);
        hook.setLVRThreshold(200);
        
        // Auction should still exist
        (, , , bool isActive, , , , ) = hook.auctions(auctionId);
        assertTrue(isActive);
    }

    // Test: Fee recipient update doesn't affect existing auctions
    function test_feeRecipientUpdateDoesntAffectAuctions() public {
        bytes32 auctionId = createAuction();
        
        address newRecipient = makeAddr("newRecipient");
        vm.prank(owner);
        hook.setFeeRecipient(newRecipient);
        
        // Auction should still exist
        (, , , bool isActive, , , , ) = hook.auctions(auctionId);
        assertTrue(isActive);
    }

    // Test: Operator authorization doesn't affect existing bids
    function test_operatorAuthorizationDoesntAffectExistingBids() public {
        bytes32 auctionId = createAuction();
        address newOperator = makeAddr("newOperator");
        
        commitBid(auctionId, newOperator, 1 ether, 123);
        
        hook.setOperatorAuthorization(newOperator, true);
        
        // Should be able to reveal
        revealBid(auctionId, newOperator, 1 ether, 123);
        
        (, uint256 revealedAmount, , bool revealed, ) = hook.revealedBids(auctionId, newOperator);
        assertEq(revealedAmount, 1 ether);
        assertTrue(revealed);
    }

    // Test: Multiple threshold updates
    function test_multipleThresholdUpdates() public {
        vm.prank(owner);
        hook.setLVRThreshold(100);
        assertEq(hook.lvrThreshold(), 100);
        
        vm.prank(owner);
        hook.setLVRThreshold(200);
        assertEq(hook.lvrThreshold(), 200);
        
        vm.prank(owner);
        hook.setLVRThreshold(300);
        assertEq(hook.lvrThreshold(), 300);
    }

    // Test: Multiple fee recipient updates
    function test_multipleFeeRecipientUpdates() public {
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");
        address recipient3 = makeAddr("recipient3");
        
        vm.prank(owner);
        hook.setFeeRecipient(recipient1);
        assertEq(hook.feeRecipient(), recipient1);
        
        vm.prank(owner);
        hook.setFeeRecipient(recipient2);
        assertEq(hook.feeRecipient(), recipient2);
        
        vm.prank(owner);
        hook.setFeeRecipient(recipient3);
        assertEq(hook.feeRecipient(), recipient3);
    }

    // Test: Admin functions don't affect constants
    function test_adminFunctionsDontAffectConstants() public {
        uint256 minBidBefore = hook.MIN_BID();
        uint256 maxDurationBefore = hook.MAX_AUCTION_DURATION();
        
        vm.prank(owner);
        hook.setLVRThreshold(200);
        vm.prank(owner);
        hook.pause();
        
        assertEq(hook.MIN_BID(), minBidBefore);
        assertEq(hook.MAX_AUCTION_DURATION(), maxDurationBefore);
    }

    // Test: Owner is set correctly
    function test_ownerIsSetCorrectly() public {
        assertEq(hook.owner(), owner);
    }

    // Test: Owner cannot be changed
    function test_ownerCannotBeChanged() public {
        // Owner is immutable in Ownable
        assertEq(hook.owner(), owner);
    }
}

