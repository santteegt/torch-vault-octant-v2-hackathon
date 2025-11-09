// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { YieldBethStrategy } from "./YieldBethStrategy.sol";

// ============================================
// INTERFACES
// ============================================

/// @notice RocketPool deposit pool interface
/// @dev Used to deposit ETH and receive rETH
interface IRocketDepositPool {
    function deposit() external payable;
    function getMaximumDepositAmount() external view returns (uint256);
}

/// @notice RocketPool rETH token interface
/// @dev Used for exchange rate and burn mechanism
interface IRocketTokenRETH {
    /// @notice Get the current exchange rate
    function getExchangeRate() external view returns (uint256);
    /// @notice Get the total amount of collateral available
    function getTotalCollateral() external view returns (uint256);
    /// @notice Burn rETH to get ETH
    function burn(uint256 _rethAmount) external returns (uint256);
}

/**
 * @title RocketPoolYieldBethStrategy
 * @author Santiago Gonzalez
 * @notice Yield skimming strategy that accepts ETH deposits, converts to rETH via RocketPool,
 *         enforces per-user lockup periods, and converts rETH back to ETH via burn mechanism
 *         before depositing into BETH contract on withdrawal.
 * @dev Extends YieldBethStrategy to capture yield from rETH appreciation.
 *
 *      ROCKETPOOL INTEGRATION:
 *      - Deposit: ETH → rETH via RocketDepositPool.deposit()
 *      - Withdrawal: rETH → ETH via RocketTokenRETH.burn()
 *      - Exchange rate tracked via RocketTokenRETH.getExchangeRate()
 */
contract RocketPoolYieldBethStrategy is YieldBethStrategy {

    /// @notice Address of RocketPool deposit pool contract
    /// @dev Used to convert ETH to rETH
    address public immutable ROCKET_DEPOSIT_POOL_ADDRESS;

    /// @notice Address of Yield ETH token contract
    /// @dev Used for exchange rate and burn mechanism
    address public immutable RETH_ADDRESS;

    // ============================================
    // ERRORS
    // ============================================

    /// @notice Thrown when RETH burn fails
    error RETHBurnFailed();

    /**
     * @notice Initializes the Yield Beth Strategy
     * @param _yieldEthDepositPoolAddress Address of RocketPool deposit pool contract
     * @param _asset Address of rETH token (the strategy's underlying asset)
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield (dragon router)
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     * @param _lockupPeriod Minimum time in seconds users must wait before withdrawing
     * @param _bethContract Address of BETH contract
     */
    constructor(
        address _yieldEthDepositPoolAddress,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress,
        uint256 _lockupPeriod,
        address _bethContract
    ) YieldBethStrategy(_asset, _name, _management, _keeper, _emergencyAdmin, _donationAddress, _enableBurning, _tokenizedStrategyAddress, _lockupPeriod, _bethContract) {
        ROCKET_DEPOSIT_POOL_ADDRESS = _yieldEthDepositPoolAddress;
        RETH_ADDRESS = _asset;
    }

    function _stakeETH(uint256 _amount) internal override returns (uint256 rethReceived) {
        IERC20 reth = IERC20(RETH_ADDRESS);
        uint256 currentBalance = reth.balanceOf(address(this));
        // Convert ETH to rETH via RocketPool deposit pool
        IRocketDepositPool(ROCKET_DEPOSIT_POOL_ADDRESS).deposit{value: _amount}();

        // Get the rETH received (should be less than ETH due to exchange rate)
        rethReceived = reth.balanceOf(address(this)) - currentBalance;
    }

    function _unstakeETH(uint256 _amount) internal override returns (uint256 ethReceived) {
        ethReceived = IRocketTokenRETH(RETH_ADDRESS).burn(_amount);
        if (ethReceived == 0) revert RETHBurnFailed();
    }

    /**
     * @notice Returns current rETH → ETH exchange rate
     * @dev Queries RocketPool protocol for current rate
     * @return rate Amount of ETH per 1 rETH (18 decimal precision)
     */
    function _getCurrentExchangeRate() internal view override returns (uint256) {
        return IRocketTokenRETH(RETH_ADDRESS).getExchangeRate();
    }

    /**
     * @notice Returns exchange rate precision (18 decimals)
     * @dev RocketPool uses 18 decimal precision for exchange rate
     * @return decimals Always returns 18
     */
    function decimalsOfExchangeRate() public pure override returns (uint256) {
        return 18;
    }
}