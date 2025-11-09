// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { BaseYieldSkimmingStrategy } from "@octant-core/strategies/yieldSkimming/BaseYieldSkimmingStrategy.sol";
// import { BaseYieldSkimmingHealthCheck } from "@octant-core/strategies/periphery/BaseYieldSkimmingHealthCheck.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BETH } from "@beth/BETH.sol";

// // ============================================
// // INTERFACES
// // ============================================

// /// @notice RocketPool deposit pool interface
// /// @dev Used to deposit ETH and receive rETH
// interface IRocketDepositPool {
//     function deposit() external payable;
//     function getMaximumDepositAmount() external view returns (uint256);
// }

// /// @notice RocketPool rETH token interface
// /// @dev Used for exchange rate and burn mechanism
// interface IRocketTokenRETH {
//     /// @notice Get the current exchange rate
//     function getExchangeRate() external view returns (uint256);
//     /// @notice Get the total amount of collateral available
//     function getTotalCollateral() external view returns (uint256);
//     /// @notice Burn rETH to get ETH
//     function burn(uint256 _rethAmount) external returns (uint256);
// }

/**
 * @title YieldBethStrategy
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Yield skimming strategy that accepts ETH deposits, converts to rETH via RocketPool,
 *         enforces per-user lockup periods, and converts rETH back to ETH via burn mechanism
 *         before depositing into BETH contract on withdrawal.
 * @dev Extends BaseYieldSkimmingStrategy to capture yield from rETH appreciation.
 *
 *      STRATEGY FLOW:
 *      1. Deposit: User deposits ETH → Convert to rETH via RocketPool deposit pool
 *      2. Lockup: Track per-user deposit timestamps, enforce lockup period
 *      3. Withdrawal: Check lockup → Burn rETH to ETH → Deposit ETH to BETH → Transfer BETH to user
 *
 *      LOCKUP MECHANISM:
 *      - Each user's deposit timestamp is updated on every deposit
 *      - Withdrawals only allowed after lockupPeriod has elapsed since last deposit
 *      - Lockup period resets on each new deposit
 *
 *      ROCKETPOOL INTEGRATION:
 *      - Deposit: ETH → rETH via RocketDepositPool.deposit()
 *      - Withdrawal: rETH → ETH via RocketTokenRETH.burn()
 *      - Exchange rate tracked via RocketTokenRETH.getExchangeRate()
 *
 *      BETH INTEGRATION:
 *      - On withdrawal, ETH from rETH burn is deposited into BETH contract
 *      - User receives BETH tokens instead of ETH
 *
 * @custom:security Lockup period prevents early withdrawals
 * @custom:security Exchange rate from RocketPool (trusted source)
 */
abstract contract YieldBethStrategy is BaseYieldSkimmingStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Minimum lockup period in seconds before users can withdraw
    /// @dev Set during construction, applies to all users
    uint256 public immutable lockupPeriod;

    // /// @notice Address of Yield ETH deposit pool contract
    // /// @dev Used to convert ETH to rETH
    // address public immutable YIELD_ETH_DEPOSIT_POOL_ADDRESS;

    // /// @notice Address of Yield ETH token contract
    // /// @dev Used for exchange rate and burn mechanism
    // address public immutable YIELD_ETH_TOKEN_ADDRESS;

    /// @notice Address of BETH contract
    /// @dev Used to deposit ETH and receive BETH tokens on withdrawal
    address public immutable bethContract;

    /// @notice Mapping of user addresses to their last deposit timestamp
    /// @dev Updated on every deposit, used to enforce lockup period
    mapping(address => uint256) public userDepositTimestamps;

    // ============================================
    // ERRORS
    // ============================================

    /// @notice Thrown when withdrawal attempted before lockup period expires
    error LockupPeriodNotExpired();
    /// @notice Thrown when ETH deposit fails
    error ETHDepositFailed();
    /// @notice Thrown when Yield ETH burn fails
    error YieldETHBurnFailed();
    /// @notice Thrown when BETH deposit fails
    error BETHDepositFailed();

    // ============================================
    // EVENTS
    // ============================================

    /// @notice Emitted when assets are withdrawn and burned / converted into BETH
    /// @param owner Address of the owner who withdrew the assets
    /// @param assets Amount of assets withdrawn & burned
    /// @param shares Amount of shares burned
    event WithdrawalToBETH(address indexed owner, uint256 assets, uint256 shares);

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initializes the Yield Beth Strategy
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
    )
        BaseYieldSkimmingStrategy(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        lockupPeriod = _lockupPeriod;
        // YIELD_ETH_DEPOSIT_POOL_ADDRESS = _rocketDepositPool;
        // YIELD_ETH_TOKEN_ADDRESS = _rocketTokenRETH;
        bethContract = _bethContract;

        // // Approve rETH for burning (unlimited approval)
        // IERC20(_asset).forceApprove(_rocketTokenRETH, type(uint256).max);
    }

    // ============================================
    // CUSTOM DEPOSIT FUNCTION
    // ============================================

    function _stakeETH(uint256 _amount) internal virtual returns (uint256);

    /**
     * @notice Accepts ETH deposits, converts to rETH, and deposits into strategy
     * @dev Custom deposit function that handles ETH → rETH conversion
     *      Updates user's deposit timestamp on every deposit
     *      Then calls TokenizedStrategy's deposit with rETH
     * @param assets Amount of assets to deposit (or type(uint256).max for full balance)
     * @param receiver Address to receive the minted shares
     * @return shares Amount of shares minted to receiver
     * @custom:security Reentrancy protected
     */
    function deposit(uint256 assets, address receiver) public payable nonReentrant returns (uint256 shares) {
        if (msg.value == 0 || assets != msg.value) {
            revert ETHDepositFailed();
        }

        // // Convert ETH to rETH via RocketPool deposit pool
        // IRocketDepositPool(rocketDepositPool).deposit{value: msg.value}();

        // // Get the rETH received (should be less than ETH due to exchange rate)
        // uint256 rethReceived = IERC20(asset).balanceOf(address(this));

        uint256 yieldEthReceived = _stakeETH(assets);

        // Update user's deposit timestamp (resets lockup period)
        // Use _receiver as the user, not msg.sender (in case of deposit for another)
        userDepositTimestamps[receiver] = block.timestamp;

        // // Approve rETH for TokenizedStrategy deposit
        // IERC20(asset).forceApprove(address(this), rethReceived);

        // Call TokenizedStrategy's deposit with rETH via delegatecall
        // This will call _deployFunds which is a no-op for yield skimming
        bytes memory result = _delegateCall(
            abi.encodeWithSignature("deposit(uint256,address)", yieldEthReceived, receiver)
        );
        shares = abi.decode(result, (uint256));
    }

    receive() external payable {
        deposit(msg.value, msg.sender);
    }

    // // ============================================
    // // REQUIRED OVERRIDES
    // // ============================================

    // // Note: We cannot override _deployFunds, _freeFunds, or _harvestAndReport
    // // because BaseYieldSkimmingStrategy doesn't mark them as virtual.
    // // Instead, we handle conversions in withdraw/redeem functions.

    // /**
    //  * @notice Helper function to convert rETH to BETH
    //  * @dev Burns rETH to ETH, deposits ETH to BETH
    //  * @param _shares Amount of shares to convert
    //  * @return bethAmount Amount of BETH received
    //  */
    // function _convertRETHToBETH(uint256 _shares) internal returns (uint256 bethAmount) {
    //     bytes memory totalSupplyResult = _delegateCall(abi.encodeWithSignature("totalSupply()"));
    //     uint256 totalSupply = abi.decode(totalSupplyResult, (uint256));
    //     uint256 rethBalance = IERC20(asset).balanceOf(address(this));
        
    //     // Calculate proportional rETH to burn based on shares
    //     // Note: We use totalSupply + _shares to account for shares that will be burned
    //     uint256 rethToBurn = totalSupply > 0 ? (_shares * rethBalance) / (totalSupply + _shares) : 0;

    //     if (rethToBurn > 0) {
    //         // Burn rETH to get ETH
    //         uint256 ethReceived = IRocketTokenRETH(rocketTokenRETH).burn(rethToBurn);
    //         if (ethReceived == 0) revert RETHBurnFailed();
            
    //         // Deposit ETH into BETH contract
    //         BETH(payable(bethContract)).deposit{value: ethReceived}();
            
    //         // Get BETH balance (should equal ethReceived since BETH is 1:1 with ETH)
    //         bethAmount = IERC20(bethContract).balanceOf(address(this));
    //     }
    // }

    // ============================================
    // CUSTOM WITHDRAW FUNCTION
    // ============================================

    /**
     * @notice Unstakes ETH from the Yield ETH contract
     * @dev Custom unstake function that handles YieldETH → ETH conversion
     * @param _amount Amount of YieldETH to unstake
     * @return ethAmount Amount of ETH received
     */
    function _unstakeETH(uint256 _amount) internal virtual returns (uint256);

    /**
     * @notice Override withdraw to handle lockup check and BETH conversion
     * @dev Checks lockup period, calculates shares, burns rETH to ETH, deposits ETH to BETH,
     *      calls parent to handle share accounting, and transfers BETH to receiver
     * @param _assets Amount of assets to withdraw
     * @param _receiver Address to receive assets
     * @param _owner Address owning the shares
     * @return shares Amount of shares burned
     */
    function _withdraw(uint256 _assets, address _receiver, address _owner) internal returns (uint256 shares) {
        // Check lockup period
        uint256 depositTimestamp = userDepositTimestamps[_owner];
        if (depositTimestamp == 0 || block.timestamp < depositTimestamp + lockupPeriod) {
            revert LockupPeriodNotExpired();
        }

        // // Calculate shares that will be burned
        // bytes memory totalAssetsResult = _delegateCall(abi.encodeWithSignature("totalAssets()"));
        // uint256 totalAssets = abi.decode(totalAssetsResult, (uint256));
        // bytes memory totalSupplyResult = _delegateCall(abi.encodeWithSignature("totalSupply()"));
        // uint256 totalSupply = abi.decode(totalSupplyResult, (uint256));
        
        // if (totalSupply == 0) {
        //     shares = 0;
        // } else {
        //     shares = (_assets * totalSupply + totalAssets - 1) / totalAssets; // Round up
        // }

        // Call TokenizedStrategy's withdraw via delegatecall to handle share accounting
        // The parent will transfer rETH to receiver, but we need to convert it to BETH
        // We'll handle the conversion after the parent call
        address receiverOverride = address(this);
        bytes memory result = _delegateCall(
            // abi.encodeWithSignature("withdraw(uint256,address,address)", _assets, _receiver, _owner)
            abi.encodeWithSignature("withdraw(uint256,address,address)", _assets, receiverOverride, _owner)
        );
        shares = abi.decode(result, (uint256));

        // Now convert the rETH that was transferred to BETH
        // Get the rETH balance that was transferred to receiver
        // uint256 rethTransferred = IERC20(asset).balanceOf(_receiver);
        // if (rethTransferred > 0) {
        if (shares > 0) {
            // // Transfer rETH back from receiver to strategy
            // // Note: This requires the receiver to approve the strategy
            // // In practice, we might need a different approach or require pre-approval
            // // For now, we'll assume the receiver has approved the strategy
            // IERC20(asset).safeTransferFrom(_receiver, address(this), rethTransferred);
            
            // Burn rETH to get ETH
            // uint256 ethReceived = IRocketTokenRETH(rocketTokenRETH).burn(rethTransferred);
            // if (ethReceived == 0) revert RETHBurnFailed();
            uint256 ethReceived = _unstakeETH(_assets);

            BETH beth = BETH(payable(bethContract));
            uint256 currentBethBalance = beth.balanceOf(address(this));
            // Deposit ETH into BETH contract
            beth.deposit{value: ethReceived}();
            
            // Transfer BETH to receiver
            uint256 bethAmount = beth.balanceOf(address(this)) - currentBethBalance;
            if (bethAmount > 0) {
                IERC20(bethContract).transfer(_receiver, bethAmount);
            }
            emit WithdrawalToBETH(_owner, _assets, shares);
        }
    }

    /**
     * @notice Withdraws assets by burning owner's shares (no loss tolerance)
     * @dev Convenience wrapper that defaults to maxLoss = 0 (no loss accepted)
     *      Calls the overloaded withdraw with maxLoss = 0
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive the withdrawn assets
     * @param owner Address whose shares will be burned
     * @return shares Amount of shares burned from owner
     */
    function withdraw(uint256 assets, address receiver, address owner) external virtual returns (uint256 shares) {
        return withdraw(assets, receiver, owner, 0);
    }

    /**
     * @notice Withdraws assets by burning owner's shares with loss tolerance
     * @dev ERC4626-extended withdraw with loss parameter and reentrancy protection
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive the withdrawn assets
     * @param owner Address whose shares are burned
     * @return shares Amount of shares burned from owner
     * @param maxLoss Maximum acceptable loss in basis points (0-10000, where 10000 = 100%)
     * @custom:security Reentrancy protected
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public nonReentrant returns (uint256 shares) {
        // TODO: IF dragon router is the receiver, make normal withdraw,
        // otherwise, convert to BETH and withdraw
        bytes memory result = _delegateCall(
            abi.encodeWithSignature("dragonRouter()")
        );
        address dragonRouter = abi.decode(result, (address));
        if (owner == dragonRouter) {
            result = _delegateCall(
                abi.encodeWithSignature("withdraw(uint256,address,address,uint256)", assets, receiver, owner, maxLoss)
            );
            shares = abi.decode(result, (uint256));
        } else {
            result = _delegateCall(
                abi.encodeWithSignature("maxWithdraw(address)", owner)
            );
            uint256 maxWithdraw = abi.decode(result, (uint256));
            require(assets <= maxWithdraw, "ERC4626: withdraw more than max");
            // Check for rounding error or 0 value.
            result = _delegateCall(
                abi.encodeWithSignature("previewWithdraw(uint256)", assets)
            );
            shares = abi.decode(result, (uint256));
            require(shares != 0, "ZERO_SHARES");

            // call _withdraw to convert YieldEth to ETH and then burn it by depositing into BETH
            _withdraw(assets, receiver, owner);
        }
    }

    /**
     * @notice Override redeem to handle lockup check and BETH conversion
     * @dev Checks lockup period, burns rETH to ETH, deposits ETH to BETH,
     *      then calls parent to handle share accounting, and transfers BETH to receiver
     * @param _shares Amount of shares to redeem
     * @param _receiver Address to receive assets
     * @param _owner Address owning the shares
     * @return assets Amount of assets withdrawn
     */
    function _redeem(uint256 _shares, address _receiver, address _owner) public returns (uint256 assets) {
        // Check lockup period
        uint256 depositTimestamp = userDepositTimestamps[_owner];
        if (depositTimestamp == 0 || block.timestamp < depositTimestamp + lockupPeriod) {
            revert LockupPeriodNotExpired();
        }

        // Call TokenizedStrategy's redeem via delegatecall to handle share accounting
        // The parent will transfer rETH to receiver, but we need to convert it to BETH
        // We'll handle the conversion after the parent call
        address receiverOverride = address(this);
        bytes memory result = _delegateCall(
            abi.encodeWithSignature("redeem(uint256,address,address)", _shares, receiverOverride, _owner)
        );
        assets = abi.decode(result, (uint256));

        // Now convert the rETH that was transferred to BETH
        // Get the rETH balance that was transferred to receiver
        // uint256 rethTransferred = IERC20(asset).balanceOf(_receiver);
        
        // if (rethTransferred > 0) {
        if (assets > 0) {
            // Transfer rETH back from receiver to strategy
            // Note: This requires the receiver to approve the strategy
            // In practice, we might need a different approach or require pre-approval
            // For now, we'll assume the receiver has approved the strategy
            // IERC20(asset).safeTransferFrom(_receiver, address(this), rethTransferred);   
            
            // // Burn rETH to get ETH
            // uint256 ethReceived = IRocketTokenRETH(rocketTokenRETH).burn(rethTransferred);
            // if (ethReceived == 0) revert RETHBurnFailed();
            uint256 ethReceived = _unstakeETH(assets);
            
            BETH beth = BETH(payable(bethContract));
            uint256 currentBethBalance = beth.balanceOf(address(this));
            // Deposit ETH into BETH contract
            beth.deposit{value: ethReceived}();
            
            // Transfer BETH to receiver
            uint256 bethAmount = beth.balanceOf(address(this)) - currentBethBalance;
            if (bethAmount > 0) {
                IERC20(bethContract).transfer(_receiver, bethAmount);
            }
            emit WithdrawalToBETH(_owner, assets, _shares);
        }   
    }

    /**
     * @notice Redeems shares for assets (accepts any loss)
     * @dev Convenience wrapper that defaults to maxLoss = MAX_BPS (100%, accepts any loss)
     *      Calls the overloaded redeem with maxLoss = MAX_BPS
     * @param shares Amount of shares to burn
     * @param receiver Address to receive the withdrawn assets
     * @param owner Address whose shares are burned
     * @return assets Actual amount of assets withdrawn (may be less than expected if loss occurs)
     */
    function redeem(uint256 shares, address receiver, address owner) external virtual returns (uint256) {
        // We default to not limiting a potential loss.
        uint256 maxBps = 10_000; // 100% loss tolerance
        return redeem(shares, receiver, owner, maxBps);
    }

    /**
     * @notice Redeems exactly specified shares for assets with loss tolerance
     * @dev ERC4626-extended redeem with loss parameter and reentrancy protection
     * @param shares Amount of shares to burn
     * @param receiver Address to receive the withdrawn assets
     * @param owner Address whose shares are burned
     * @param maxLoss Maximum acceptable loss in basis points (0-10000, where 10000 = 100%)
     * @return assets Actual amount of assets withdrawn
     * @custom:security Reentrancy protected
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public nonReentrant returns (uint256) {
        // TODO: IF dragon router is the receiver, make normal redeem,
        // otherwise, convert to BETH and withdraw
        bytes memory result = _delegateCall(
            abi.encodeWithSignature("dragonRouter()")
        );
        address dragonRouter = abi.decode(result, (address));
        if (owner == dragonRouter) {
            result = _delegateCall(
                abi.encodeWithSignature("redeem(uint256,address,address,uint256)", shares, receiver, owner, maxLoss)
            );
            uint256 assets = abi.decode(result, (uint256));
            return assets;
        } else {
            result = _delegateCall(
                abi.encodeWithSignature("maxRedeem(address)", owner)
            );
            uint256 maxRedeem = abi.decode(result, (uint256));
            require(shares <= maxRedeem, "ERC4626: redeem more than max");

            result = _delegateCall(
                abi.encodeWithSignature("previewRedeem(uint256)", shares)
            );
            uint256 assets = abi.decode(result, (uint256));
            require(assets != 0, "ZERO_ASSETS");

            // call _redeem to convert YieldEth to ETH and then burn it by depositing into BETH
            return _redeem(shares, receiver, owner);
        }
    }

    /**
     * @notice Returns maximum withdrawable amount considering lockup period
     * @dev Overrides base implementation to enforce per-user lockup period
     * @param _owner Address of the user attempting to withdraw
     * @return Maximum amount of assets that can be withdrawn (0 if lockup not expired)
     */
    function availableWithdrawLimit(address _owner) public view override returns (uint256) {
        // Check if user has deposited
        uint256 depositTimestamp = userDepositTimestamps[_owner];
        if (depositTimestamp == 0) {
            // User has never deposited, can't withdraw
            return 0;
        }

        // Check if lockup period has expired
        if (block.timestamp < depositTimestamp + lockupPeriod) {
            // Lockup period not expired
            return 0;
        }

        // Lockup period expired, user can withdraw
        // Return maximum (parent will handle actual balance checks)
        return type(uint256).max;
    }

    // Note: _harvestAndReport is already implemented in BaseYieldSkimmingStrategy
    // and calls IERC4626(address(this)).totalAssets(), which should work correctly
    // since the strategy is an ERC4626 vault. We don't need to override it.
}

