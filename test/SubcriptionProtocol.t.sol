// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SubscriptionProtocol.sol";

contract SubscriptionProtocolTest is Test {
    SubscriptionProtocol public protocol;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    uint256 public constant FEE = 0.01 ether;
    string public constant BASE_URI = "ipfs://QmTest/";

    function setUp() public {
        vm.prank(owner);
        protocol = new SubscriptionProtocol(FEE, BASE_URI);

        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    // ================================
    // SUBSCRIBE TESTS
    // ================================

    // Test 1: User can subscribe for 1 period
    function test_UserCanSubscribe() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        assertTrue(protocol.isActive(user1));
    }

    // Test 2: Subscriber receives NFT after subscribing
    function test_SubscriberReceivesNFT() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        assertEq(protocol.balanceOf(user1), 1);
    }

    // Test 3: User can prepay multiple periods
    function test_UserCanPrepayMultiplePeriods() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE * 3}(3);

        assertEq(protocol.balanceOf(user1), 3);

        (,, uint256 totalPeriodsPaid,,) = protocol.getSubscription(user1);
        assertEq(totalPeriodsPaid, 3);
    }

    // Test 4: Subscription data is stored correctly
    function test_SubscriptionDataIsCorrect() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        (bool active, uint256 expiresAt, uint256 totalPeriodsPaid, uint256 subscribedAt, uint256 secondsLeft) =
            protocol.getSubscription(user1);

        assertTrue(active);
        assertEq(totalPeriodsPaid, 1);
        assertEq(subscribedAt, block.timestamp);
        assertEq(expiresAt, block.timestamp + 30 days);
        assertGt(secondsLeft, 0);
    }

    // Test 5: Payment record is stored correctly
    function test_PaymentRecordIsCorrect() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        SubscriptionProtocol.PaymentRecord memory record = protocol.getPaymentRecord(0);

        assertEq(record.subscriber, user1);
        assertEq(record.periodNumber, 1);
        assertEq(record.periodStart, block.timestamp);
        assertEq(record.periodEnd, block.timestamp + 30 days);
    }

    // Test 6: Total revenue increases after subscription
    function test_TotalRevenueIncreasesAfterSubscribe() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        assertEq(protocol.totalRevenue(), FEE);
    }

    // Test 7: Multiple users can subscribe independently
    function test_MultipleUsersCanSubscribe() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.prank(user2);
        protocol.subscribe{value: FEE}(1);

        assertTrue(protocol.isActive(user1));
        assertTrue(protocol.isActive(user2));
    }

    // ================================
    // EXPIRY TESTS
    // ================================

    // Test 8: Subscription expires after period ends
    function test_SubscriptionExpires() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.warp(block.timestamp + 30 days + 1);

        assertFalse(protocol.isActive(user1));
    }

    // Test 9: Time remaining returns 0 after expiry
    function test_TimeRemainingIsZeroAfterExpiry() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.warp(block.timestamp + 30 days + 1);

        assertEq(protocol.timeRemaining(user1), 0);
    }

    // Test 10: Time remaining is correct while active
    function test_TimeRemainingWhileActive() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.warp(block.timestamp + 10 days);

        assertEq(protocol.timeRemaining(user1), 20 days);
    }

    // ================================
    // RENEW TESTS
    // ================================

    // Test 11: User can renew while still active
    function test_UserCanRenewWhileActive() public {
        uint256 start = block.timestamp;

        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.prank(user1);
        protocol.renewSubscription{value: FEE}(1);

        (, uint256 expiresAt,,,) = protocol.getSubscription(user1);

        assertEq(expiresAt, start + 60 days);
    }

    // Test 12: User can renew after expiry
    function test_UserCanRenewAfterExpiry() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(user1);
        protocol.renewSubscription{value: FEE}(1);

        assertTrue(protocol.isActive(user1));
    }

    // Test 13: NFT is minted on renewal
    function test_NFTMintedOnRenewal() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.prank(user1);
        protocol.renewSubscription{value: FEE}(1);

        assertEq(protocol.balanceOf(user1), 2);
    }

    // Test 14: Total periods paid increments on renewal
    function test_TotalPeriodsPaidIncrementsOnRenewal() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.prank(user1);
        protocol.renewSubscription{value: FEE}(1);

        (,, uint256 totalPeriodsPaid,,) = protocol.getSubscription(user1);
        assertEq(totalPeriodsPaid, 2);
    }

    // ================================
    // OWNER TESTS
    // ================================

    // Test 15: Owner can withdraw funds
    function test_OwnerCanWithdraw() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        protocol.withdraw(payable(owner));

        assertEq(owner.balance, balanceBefore + FEE);
    }

    // Test 16: Owner can update subscription fee
    function test_OwnerCanUpdateFee() public {
        uint256 newFee = 0.02 ether;

        vm.prank(owner);
        protocol.setSubscriptionFee(newFee);

        assertEq(protocol.subscriptionFee(), newFee);
    }

    // Test 17: Owner can pause and unpause
    function test_OwnerCanPauseAndUnpause() public {
        vm.prank(owner);
        protocol.pause();
        assertTrue(protocol.paused());

        vm.prank(owner);
        protocol.unpause();
        assertFalse(protocol.paused());
    }

    // Test 18: Owner can toggle soulbound
    function test_OwnerCanToggleSoulbound() public {
        vm.prank(owner);
        protocol.toggleSoulbound();

        assertFalse(protocol.soulbound());
    }

    // ================================
    // SOULBOUND TESTS
    // ================================

    // Test 19: NFT cannot be transferred in soulbound mode
    function test_RevertIf_TransferSoulboundNFT() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.prank(user1);
        vm.expectRevert();
        protocol.transferFrom(user1, user2, 0);
    }

    // Test 20: NFT can be transferred when soulbound is off
    function test_CanTransferWhenSoulboundOff() public {
        vm.prank(owner);
        protocol.toggleSoulbound();

        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.prank(user1);
        protocol.transferFrom(user1, user2, 0);

        assertEq(protocol.ownerOf(0), user2);
    }

    // ================================
    // FAILURE TESTS
    // ================================

    // Test 21: Reverts if wrong ETH amount sent
    function test_RevertIf_WrongETHAmount() public {
        vm.prank(user1);
        vm.expectRevert();
        protocol.subscribe{value: 0.005 ether}(1);
    }

    // Test 22: Reverts if user subscribes while already active
    function test_RevertIf_AlreadyActiveSubscription() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.prank(user1);
        vm.expectRevert();
        protocol.subscribe{value: FEE}(1);
    }

    // Test 23: Reverts if periods = 0
    function test_RevertIf_ZeroPeriods() public {
        vm.prank(user1);
        vm.expectRevert();
        protocol.subscribe{value: 0}(0);
    }

    // Test 24: Reverts if periods exceed max
    function test_RevertIf_ExceedsMaxPeriods() public {
        vm.prank(user1);
        vm.expectRevert();
        protocol.subscribe{value: FEE * 13}(13);
    }

    // Test 25: Reverts if non-subscriber tries to renew
    function test_RevertIf_NonSubscriberRenews() public {
        vm.prank(user1);
        vm.expectRevert();
        protocol.renewSubscription{value: FEE}(1);
    }

    // Test 26: Reverts if non-owner tries to withdraw
    function test_RevertIf_NonOwnerWithdraws() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.prank(user2);
        vm.expectRevert();
        protocol.withdraw(payable(user2));
    }

    // Test 27: Reverts if non-owner tries to pause
    function test_RevertIf_NonOwnerPauses() public {
        vm.prank(user1);
        vm.expectRevert();
        protocol.pause();
    }

    // Test 28: Reverts if subscribing while paused
    function test_RevertIf_SubscribeWhilePaused() public {
        vm.prank(owner);
        protocol.pause();

        vm.prank(user1);
        vm.expectRevert();
        protocol.subscribe{value: FEE}(1);
    }

    // Test 29: Reverts if plain ETH sent to contract
    function test_RevertIf_PlainETHSent() public {
        vm.prank(user1);

        // FIXED: Since .call returns a boolean instead of breaking execution,
        // we check that the call data returns success as false.
        (bool success,) = address(protocol).call{value: 1 ether}("");
        assertFalse(success);
    }

    // Test 30: Reverts if withdraw to zero address
    function test_RevertIf_WithdrawToZeroAddress() public {
        vm.prank(user1);
        protocol.subscribe{value: FEE}(1);

        vm.prank(owner);
        vm.expectRevert();
        protocol.withdraw(payable(address(0)));
    }
}
