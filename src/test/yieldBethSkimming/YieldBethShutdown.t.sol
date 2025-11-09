// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import {YieldBethSetup} from "./YieldBethSetup.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";

/**
 * @title YieldBethShutdownTest
 * @notice Tests for Yield Beth Skimming Strategy shutdown scenarios
 * @dev Tests emergency shutdown and recovery procedures
 */
contract YieldBethShutdownTest is YieldBethSetup {
    // ============================================
    // SHUTDOWN TESTS
    // ============================================

    /**
     * @notice Test that strategy can be shutdown by emergency admin
     * @dev Verifies emergency shutdown functionality
     */
    function test_shutdownByEmergencyAdmin() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Shutdown strategy
        vm.prank(emergencyAdmin);
        ITokenizedStrategy(address(strategy)).shutdownStrategy();

        // Check that strategy is shutdown
        bool isShutdown = ITokenizedStrategy(address(strategy)).isShutdown();
        assertTrue(isShutdown, "Strategy should be shutdown");
    }

    /**
     * @notice Test that deposits are blocked after shutdown
     * @dev Verifies deposit restrictions after shutdown
     */
    function test_depositBlockedAfterShutdown() public {
        uint256 amount = 1 ether;

        // Shutdown strategy
        vm.prank(emergencyAdmin);
        ITokenizedStrategy(address(strategy)).shutdownStrategy();

        // Try to deposit after shutdown
        vm.expectRevert();
        mintAndDepositETHIntoStrategy(strategy, user, amount);
    }

    /**
     * @notice Test that withdrawals still work after shutdown (if lockup expired)
     * @dev Verifies withdrawal functionality after shutdown
     */
    function test_withdrawalAfterShutdown() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Shutdown strategy
        vm.prank(emergencyAdmin);
        ITokenizedStrategy(address(strategy)).shutdownStrategy();

        // Withdrawal should still work if lockup expired
        uint256 bethBalanceBefore = bethContract.balanceOf(user);
        vm.prank(user);
        strategy.withdraw(amount / 2, user, user);
        uint256 bethBalanceAfter = bethContract.balanceOf(user);

        // User should receive BETH
        assertGt(bethBalanceAfter, bethBalanceBefore, "User should receive BETH after shutdown");
    }

    /**
     * @notice Test that report can still be called after shutdown
     * @dev Verifies reporting functionality after shutdown
     */
    function test_reportAfterShutdown() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Move forward in time
        skip(30 days);

        // Shutdown strategy
        vm.prank(emergencyAdmin);
        ITokenizedStrategy(address(strategy)).shutdownStrategy();

        // Report should still work
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Should have profit from exchange rate appreciation
        assertGt(profit, 0, "Should have profit even after shutdown");
    }
}

