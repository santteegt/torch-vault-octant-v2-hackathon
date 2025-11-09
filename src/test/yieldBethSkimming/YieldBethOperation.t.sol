// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import {YieldBethSetup} from "./YieldBethSetup.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BETH} from "@beth/BETH.sol";
import {RocketPoolYieldBethStrategy as Strategy} from "../../strategies/RocketPoolYieldBethStrategy.sol";

/**
 * @title YieldBethOperationTest
 * @notice Tests for Yield Beth Skimming Strategy operations
 * @dev Tests deposits, withdrawals, lockup enforcement, and conversion flows
 */
contract YieldBethOperationTest is YieldBethSetup {
    // ============================================
    // DEPOSIT TESTS
    // ============================================

    /**
     * @notice Test ETH deposit and conversion to rETH
     * @dev Verifies that ETH deposits are converted to rETH and user timestamp is updated
     */
    function test_ethDeposit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        vm.assume(_amount < type(uint128).max); // Avoid overflow

        uint256 ethAmount = _amount;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, ethAmount);

        // Check that rETH was received by strategy
        assertGt(asset.balanceOf(address(strategy)), 0, "Strategy should have rETH");

        // Check that user's deposit timestamp was updated
        uint256 depositTimestamp = Strategy(payable(address(strategy))).userDepositTimestamps(user);
        assertEq(depositTimestamp, block.timestamp, "Deposit timestamp should be updated");

        // Check that user received strategy shares
        uint256 userShares = strategy.balanceOf(user);
        assertGt(userShares, 0, "User should have strategy shares");
    }

    /**
     * @notice Test that deposit timestamp is updated on every deposit
     * @dev Verifies that each deposit resets the lockup period
     */
    function test_depositTimestampUpdatedOnEveryDeposit() public {
        uint256 amount = 1 ether;

        // First deposit
        mintAndDepositETHIntoStrategy(strategy, user, amount);
        uint256 firstDepositTime = block.timestamp;
        uint256 firstTimestamp = Strategy(payable(address(strategy))).userDepositTimestamps(user);
        assertEq(firstTimestamp, firstDepositTime, "First deposit timestamp should be set");

        // Move forward in time
        skip(1 days);

        // Second deposit
        mintAndDepositETHIntoStrategy(strategy, user, amount);
        uint256 secondDepositTime = block.timestamp;
        uint256 secondTimestamp = Strategy(payable(address(strategy))).userDepositTimestamps(user);
        assertEq(secondTimestamp, secondDepositTime, "Second deposit timestamp should be updated");
        assertGt(secondTimestamp, firstTimestamp, "Second timestamp should be later");
    }

    // ============================================
    // LOCKUP PERIOD TESTS
    // ============================================

    /**
     * @notice Test that withdrawals are blocked before lockup period expires
     * @dev Verifies lockup period enforcement
     */
    function test_withdrawalBlockedBeforeLockup() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Try to withdraw before lockup period expires
        vm.expectRevert();
        vm.prank(user);
        strategy.withdraw(amount / 2, user, user);
    }

    /**
     * @notice Test that withdrawals are allowed after lockup period expires
     * @dev Verifies lockup period expiration
     */
    function test_withdrawalAllowedAfterLockup() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Withdraw should succeed
        uint256 bethBalanceBefore = bethContract.balanceOf(user);
        vm.prank(user);
        strategy.withdraw(amount / 2, user, user);
        uint256 bethBalanceAfter = bethContract.balanceOf(user);

        // User should receive BETH
        assertGt(bethBalanceAfter, bethBalanceBefore, "User should receive BETH");
    }

    /**
     * @notice Test that availableWithdrawLimit returns 0 before lockup expires
     * @dev Verifies availableWithdrawLimit enforcement
     */
    function test_availableWithdrawLimitBeforeLockup() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Check available withdraw limit
        uint256 available = strategy.availableWithdrawLimit(user);
        assertEq(available, 0, "Available withdraw limit should be 0 before lockup expires");
    }

    /**
     * @notice Test that availableWithdrawLimit returns max after lockup expires
     * @dev Verifies availableWithdrawLimit after lockup
     */
    function test_availableWithdrawLimitAfterLockup() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Check available withdraw limit
        uint256 available = strategy.availableWithdrawLimit(user);
        assertEq(available, type(uint256).max, "Available withdraw limit should be max after lockup expires");
    }

    // ============================================
    // WITHDRAWAL AND CONVERSION TESTS
    // ============================================

    /**
     * @notice Test withdrawal flow: rETH → ETH → BETH
     * @dev Verifies complete withdrawal flow with conversions
     */
    function test_withdrawalFlow() public {
        uint256 depositAmount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, depositAmount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Get initial balances
        uint256 userSharesBefore = strategy.balanceOf(user);
        uint256 strategyRethBefore = asset.balanceOf(address(strategy));
        uint256 userBethBefore = bethContract.balanceOf(user);

        // Withdraw
        uint256 withdrawAmount = depositAmount / 2;
        vm.prank(user);
        strategy.withdraw(withdrawAmount, user, user);

        // Check balances after withdrawal
        uint256 userSharesAfter = strategy.balanceOf(user);
        uint256 strategyRethAfter = asset.balanceOf(address(strategy));
        uint256 userBethAfter = bethContract.balanceOf(user);

        // User shares should decrease
        assertLt(userSharesAfter, userSharesBefore, "User shares should decrease");

        // Strategy rETH should decrease (burned)
        assertLt(strategyRethAfter, strategyRethBefore, "Strategy rETH should decrease");

        // User should receive BETH
        assertGt(userBethAfter, userBethBefore, "User should receive BETH");
    }

    /**
     * @notice Test redeem flow: rETH → ETH → BETH
     * @dev Verifies complete redeem flow with conversions
     */
    function test_redeemFlow() public {
        uint256 depositAmount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, depositAmount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Get initial balances
        uint256 userSharesBefore = strategy.balanceOf(user);
        uint256 strategyRethBefore = asset.balanceOf(address(strategy));
        uint256 userBethBefore = bethContract.balanceOf(user);

        // Redeem half of shares
        uint256 redeemShares = userSharesBefore / 2;
        vm.prank(user);
        strategy.redeem(redeemShares, user, user);

        // Check balances after redemption
        uint256 userSharesAfter = strategy.balanceOf(user);
        uint256 strategyRethAfter = asset.balanceOf(address(strategy));
        uint256 userBethAfter = bethContract.balanceOf(user);

        // User shares should decrease
        assertEq(userSharesAfter, userSharesBefore - redeemShares, "User shares should decrease");

        // Strategy rETH should decrease (burned)
        assertLt(strategyRethAfter, strategyRethBefore, "Strategy rETH should decrease");

        // User should receive BETH
        assertGt(userBethAfter, userBethBefore, "User should receive BETH");
    }

    // ============================================
    // EXCHANGE RATE TESTS
    // ============================================

    /**
     * @notice Test that exchange rate is tracked correctly
     * @dev Verifies exchange rate reporting
     */
    function test_exchangeRateTracking() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Get initial exchange rate
        uint256 initialRate = Strategy(payable(address(strategy))).getCurrentExchangeRate();
        assertGt(initialRate, 0, "Exchange rate should be positive");

        // Move forward in time to simulate rate increase
        skip(30 days);

        // Get new exchange rate
        uint256 newRate = Strategy(payable(address(strategy))).getCurrentExchangeRate();
        assertGe(newRate, initialRate, "Exchange rate should increase over time");
    }

    /**
     * @notice Test profitable report with exchange rate appreciation
     * @dev Verifies that yield is captured and minted to dragon router
     */
    function test_profitableReport() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Move forward in time to simulate yield accrual
        skip(30 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Should have profit from exchange rate appreciation
        assertGt(profit, 0, "Should have profit");
        assertEq(loss, 0, "Should have no loss");

        // Check that profit was minted to dragon router
        uint256 dragonRouterShares = strategy.balanceOf(dragonRouter);
        assertGt(dragonRouterShares, 0, "Dragon router should have shares");
    }

    // ============================================
    // EDGE CASES
    // ============================================

    /**
     * @notice Test withdrawal with zero amount
     * @dev Verifies edge case handling
     */
    function test_withdrawalZeroAmount() public {
        uint256 amount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Withdraw zero amount should revert or handle gracefully
        vm.expectRevert();
        vm.prank(user);
        strategy.withdraw(0, user, user);
    }

    /**
     * @notice Test deposit with zero ETH
     * @dev Verifies zero deposit handling
     */
    function test_depositZeroETH() public {
        vm.expectRevert();
        vm.prank(user);
        Strategy(payable(address(strategy))).deposit{value: 0}(0, user);
    }

    /**
     * @notice Test withdrawal by non-owner
     * @dev Verifies access control
     */
    function test_withdrawalByNonOwner() public {
        uint256 amount = 1 ether;
        address attacker = address(999);

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, amount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Attacker tries to withdraw user's funds
        vm.expectRevert();
        vm.prank(attacker);
        strategy.withdraw(amount / 2, attacker, user);
    }

    /**
     * @notice Test full withdrawal
     * @dev Verifies complete withdrawal of all assets
     */
    function test_fullWithdrawal() public {
        uint256 depositAmount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, depositAmount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // Get initial balances
        uint256 userSharesBefore = strategy.balanceOf(user);
        uint256 strategyRethBefore = asset.balanceOf(address(strategy));
        uint256 userBethBefore = bethContract.balanceOf(user);

        // Withdraw all assets
        uint256 maxWithdraw = strategy.maxWithdraw(user);
        vm.prank(user);
        strategy.withdraw(maxWithdraw, user, user);

        // Check balances after withdrawal
        uint256 userSharesAfter = strategy.balanceOf(user);
        uint256 strategyRethAfter = asset.balanceOf(address(strategy));
        uint256 userBethAfter = bethContract.balanceOf(user);

        // User shares should be zero or minimal
        assertEq(userSharesAfter, 0, "User shares should be zero after full withdrawal");

        // Strategy rETH should be zero or minimal
        assertEq(strategyRethAfter, 0, "Strategy rETH should be zero after full withdrawal");

        // User should receive BETH
        assertGt(userBethAfter, userBethBefore, "User should receive BETH");
    }

    /**
     * @notice Test withdrawal with exchange rate changes
     * @dev Verifies withdrawal works correctly when exchange rate has changed
     */
    function test_withdrawalWithExchangeRateChanges() public {
        uint256 depositAmount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, depositAmount);

        // Move forward past lockup period and simulate exchange rate increase
        skip(lockupPeriod + 1 days);
        
        // Increase exchange rate to simulate yield accrual
        // Use low-level call to set exchange rate
        (bool success, ) = address(rocketTokenRETH).call(abi.encodeWithSignature("setExchangeRate(uint256)", 1.05e18));
        require(success, "setExchangeRate failed");
        skip(1 days);

        // Get initial balances
        uint256 userSharesBefore = strategy.balanceOf(user);
        uint256 userBethBefore = bethContract.balanceOf(user);

        // Withdraw half
        uint256 withdrawAmount = depositAmount / 2;
        vm.prank(user);
        strategy.withdraw(withdrawAmount, user, user);

        // Check balances after withdrawal
        uint256 userSharesAfter = strategy.balanceOf(user);
        uint256 userBethAfter = bethContract.balanceOf(user);

        // User shares should decrease
        assertLt(userSharesAfter, userSharesBefore, "User shares should decrease");

        // User should receive BETH (should be more than withdrawAmount due to exchange rate)
        assertGt(userBethAfter, userBethBefore, "User should receive BETH");
        assertGe(userBethAfter - userBethBefore, withdrawAmount, "BETH received should be at least withdrawAmount");
    }

    /**
     * @notice Test multiple partial withdrawals
     * @dev Verifies multiple withdrawals work correctly
     */
    function test_multiplePartialWithdrawals() public {
        uint256 depositAmount = 1 ether;

        // Deposit ETH
        mintAndDepositETHIntoStrategy(strategy, user, depositAmount);

        // Move forward past lockup period
        skip(lockupPeriod + 1 days);

        // First withdrawal
        uint256 firstWithdraw = depositAmount / 4;
        vm.prank(user);
        strategy.withdraw(firstWithdraw, user, user);
        uint256 bethAfterFirst = bethContract.balanceOf(user);
        assertGt(bethAfterFirst, 0, "User should receive BETH after first withdrawal");

        // Second withdrawal
        uint256 secondWithdraw = depositAmount / 4;
        vm.prank(user);
        strategy.withdraw(secondWithdraw, user, user);
        uint256 bethAfterSecond = bethContract.balanceOf(user);
        assertGt(bethAfterSecond, bethAfterFirst, "User should receive more BETH after second withdrawal");

        // Third withdrawal
        uint256 thirdWithdraw = depositAmount / 4;
        vm.prank(user);
        strategy.withdraw(thirdWithdraw, user, user);
        uint256 bethAfterThird = bethContract.balanceOf(user);
        assertGt(bethAfterThird, bethAfterSecond, "User should receive more BETH after third withdrawal");
    }
}

