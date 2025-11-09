// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import {YieldBethSetup} from "./YieldBethSetup.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RocketPoolYieldBethStrategy as Strategy} from "../../strategies/RocketPoolYieldBethStrategy.sol";

/**
 * @title YieldBethFunctionSignatureTest
 * @notice Tests for Yield Beth Skimming Strategy function signatures and access control
 * @dev Verifies function access control and signatures
 */
contract YieldBethFunctionSignatureTest is YieldBethSetup {
    // ============================================
    // FUNCTION SIGNATURE TESTS
    // ============================================

    /**
     * @notice Test that deposit function exists and works
     * @dev Verifies deposit function signature
     */
    function test_depositFunctionSignature() public {
        uint256 amount = 1 ether;

        // Pre-approve the strategy to transfer rETH (needed because deposit transfers rETH to user first)
        vm.prank(user);
        IERC20(asset).approve(address(strategy), type(uint256).max);

        // Call deposit
        vm.deal(user, amount);
        vm.prank(user);
        uint256 shares = Strategy(payable(address(strategy))).deposit{value: amount}(amount, user);

        // Should return shares
        assertGt(shares, 0, "Should return shares");
    }

    /**
     * @notice Test that withdraw function exists and has correct signature
     * @dev Verifies withdraw function signature
     */
    function test_withdrawFunctionSignature() public {
        uint256 amount = 1 ether;

        // Deposit first
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Call withdraw
        vm.prank(user);
        uint256 shares = strategy.withdraw(amount / 2, user, user);

        // Should return shares burned
        assertGt(shares, 0, "Should return shares burned");
    }

    /**
     * @notice Test that redeem function exists and has correct signature
     * @dev Verifies redeem function signature
     */
    function test_redeemFunctionSignature() public {
        uint256 amount = 1 ether;

        // Deposit first
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Get user shares
        uint256 userShares = strategy.balanceOf(user);

        // Call redeem
        vm.prank(user);
        uint256 assets = strategy.redeem(userShares / 2, user, user);

        // Should return assets
        assertGt(assets, 0, "Should return assets");
    }

    // ============================================
    // ACCESS CONTROL TESTS
    // ============================================

    /**
     * @notice Test that only management can update dragon router
     * @dev Verifies access control for setDragonRouter
     */
    function test_setDragonRouterAccessControl() public {
        address newDragonRouter = address(999);

        // Non-management should not be able to set dragon router
        vm.expectRevert();
        vm.prank(user);
        ITokenizedStrategy(address(strategy)).setDragonRouter(newDragonRouter);

        // Management should be able to set dragon router
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setDragonRouter(newDragonRouter);
    }

    /**
     * @notice Test that only management can update enableBurning
     * @dev Verifies access control for setEnableBurning
     */
    function test_setEnableBurningAccessControl() public {
        // Non-management should not be able to set enableBurning
        vm.expectRevert();
        vm.prank(user);
        (bool success, ) = address(strategy).call(abi.encodeWithSignature("setEnableBurning(bool)", false));
        require(!success, "Should revert");

        // Management should be able to set enableBurning
        vm.prank(management);
        (success, ) = address(strategy).call(abi.encodeWithSignature("setEnableBurning(bool)", false));
        require(success, "Should succeed");
    }

    /**
     * @notice Test that only keeper or management can call report
     * @dev Verifies access control for report
     */
    function test_reportAccessControl() public {
        uint256 amount = 1 ether;

        // Deposit first
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // User should not be able to call report
        vm.expectRevert();
        vm.prank(user);
        strategy.report();

        // Keeper should be able to call report
        vm.prank(keeper);
        strategy.report();

        // Management should be able to call report
        vm.prank(management);
        strategy.report();
    }

    /**
     * @notice Test that only emergency admin can shutdown strategy
     * @dev Verifies access control for shutdown
     */
    function test_shutdownAccessControl() public {
        // Non-emergency admin should not be able to shutdown
        vm.expectRevert();
        vm.prank(user);
        ITokenizedStrategy(address(strategy)).shutdownStrategy();

        // Emergency admin should be able to shutdown
        vm.prank(emergencyAdmin);
        ITokenizedStrategy(address(strategy)).shutdownStrategy();
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    /**
     * @notice Test that userDepositTimestamps is accessible
     * @dev Verifies view function accessibility
     */
    function test_userDepositTimestampsView() public {
        uint256 amount = 1 ether;

        // Initially, user should have no deposit timestamp
        uint256 timestamp = Strategy(payable(address(strategy))).userDepositTimestamps(user);
        assertEq(timestamp, 0, "Initial timestamp should be 0");

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // User should have deposit timestamp
        timestamp = Strategy(payable(address(strategy))).userDepositTimestamps(user);
        assertGt(timestamp, 0, "Deposit timestamp should be set");
    }

    /**
     * @notice Test that lockupPeriod is accessible
     * @dev Verifies view function accessibility
     */
    function test_lockupPeriodView() public {
        uint256 period = Strategy(payable(address(strategy))).lockupPeriod();
        assertEq(period, lockupPeriod, "Lockup period should match");
    }

    /**
     * @notice Test that exchange rate functions are accessible
     * @dev Verifies exchange rate view functions
     */
    function test_exchangeRateViews() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Test getCurrentExchangeRate
        uint256 rate = Strategy(payable(address(strategy))).getCurrentExchangeRate();
        assertGt(rate, 0, "Exchange rate should be positive");

        // Test decimalsOfExchangeRate
        uint256 decimals = Strategy(payable(address(strategy))).decimalsOfExchangeRate();
        assertEq(decimals, 18, "Exchange rate decimals should be 18");
    }
}

