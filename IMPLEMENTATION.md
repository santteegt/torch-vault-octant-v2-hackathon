# YieldBethStrategy and RocketPoolYieldBethStrategy Implementation Documentation

## Overview

This document details the implementation of the `YieldBethStrategy` base contract and the `RocketPoolYieldBethStrategy` contract, which together provide a yield skimming strategy that accepts ETH deposits, converts them to yield-bearing tokens (rETH), enforces per-user lockup periods, and converts the yield tokens back to ETH before depositing into the BETH contract on withdrawal.

## Architecture

### Inheritance Hierarchy

```
BaseYieldSkimmingStrategy
    ↓
YieldBethStrategy
    ↓
RocketPoolYieldBethStrategy
```

### Key Components

1. **YieldBethStrategy**: Base contract that handles ETH deposits, lockup periods, and BETH conversion
2. **RocketPoolYieldBethStrategy**: Concrete implementation that integrates with RocketPool protocol
3. **BETH Contract**: Receives ETH deposits and mints BETH tokens (1:1 with ETH)

## YieldBethStrategy Base Contract

### Purpose

`YieldBethStrategy` is an abstract base contract that provides the core functionality for yield skimming strategies that:
- Accept ETH deposits
- Convert ETH to yield-bearing tokens (e.g., rETH)
- Enforce per-user lockup periods
- Convert yield tokens back to ETH on withdrawal
- Deposit ETH into BETH contract to burn it

### Key Features

#### 1. Lockup Mechanism

Each user's deposit timestamp is tracked and updated on every deposit. Users must wait for the `lockupPeriod` to expire before they can withdraw their assets.

```solidity
mapping(address => uint256) public userDepositTimestamps;
uint256 public immutable lockupPeriod;
```

- **Lockup Reset**: Each new deposit resets the user's lockup period
- **Enforcement**: Withdrawals are blocked until `block.timestamp >= depositTimestamp + lockupPeriod`

#### 2. Deposit Flow

The deposit process follows these steps:

1. User sends ETH via `deposit(uint256 assets, address receiver)` with `msg.value`
2. ETH is converted to yield token (rETH) via `_stakeETH(amount)`
3. User's deposit timestamp is updated to `block.timestamp`
4. Yield token is approved for TokenizedStrategy
5. TokenizedStrategy's `deposit()` is called via delegatecall to handle share accounting

```solidity
function deposit(uint256 assets, address receiver) public payable nonReentrant returns (uint256 shares) {
    if (msg.value == 0 || assets != msg.value) {
        revert ETHDepositFailed();
    }

    uint256 yieldEthReceived = _stakeETH(assets);
    userDepositTimestamps[receiver] = block.timestamp;
    asset.approve(address(this), yieldEthReceived);
    
    bytes memory result = _delegateCall(
        abi.encodeWithSignature("deposit(uint256,address)", yieldEthReceived, receiver)
    );
    shares = abi.decode(result, (uint256));
}
```

#### 3. Withdrawal Flow

The withdrawal process follows these steps:

1. Lockup period is checked
2. TokenizedStrategy's `withdraw()` is called via delegatecall to handle share accounting
3. rETH is transferred to the strategy contract (via `receiverOverride = address(this)`)
4. Actual rETH balance transferred is calculated
5. rETH is burned to ETH via `_unstakeETH(rethTransferred)`
6. ETH is deposited into BETH contract
7. BETH tokens are transferred to the user

```solidity
function _withdraw(uint256 _assets, address _receiver, address _owner) internal returns (uint256 shares) {
    // Check lockup period
    uint256 depositTimestamp = userDepositTimestamps[_owner];
    if (depositTimestamp == 0 || block.timestamp < depositTimestamp + lockupPeriod) {
        revert LockupPeriodNotExpired();
    }

    // Get rETH balance before withdraw
    address receiverOverride = address(this);
    uint256 rethBalanceBefore = IERC20(asset).balanceOf(receiverOverride);
    
    // Call TokenizedStrategy's withdraw via delegatecall
    bytes memory result = _delegateCall(
        abi.encodeWithSignature("withdraw(uint256,address,address)", _assets, receiverOverride, _owner)
    );
    shares = abi.decode(result, (uint256));

    if (shares > 0) {
        // Get actual rETH balance transferred
        uint256 rethTransferred = IERC20(asset).balanceOf(receiverOverride) - rethBalanceBefore;
        
        // Burn rETH to get ETH
        uint256 ethReceived = _unstakeETH(rethTransferred);

        // Deposit ETH into BETH contract
        BETH beth = BETH(payable(bethContract));
        uint256 currentBethBalance = beth.balanceOf(address(this));
        beth.deposit{value: ethReceived}();
        
        // Transfer BETH to receiver
        uint256 bethAmount = beth.balanceOf(address(this)) - currentBethBalance;
        if (bethAmount > 0) {
            IERC20(bethContract).transfer(_receiver, bethAmount);
        }
        emit WithdrawalToBETH(_owner, _assets, shares);
    }
}
```

#### 4. BETH Integration

BETH (Burned ETH) is a 1:1 token that represents ETH that has been burned. When users withdraw:
- rETH is burned to get ETH
- ETH is deposited into BETH contract
- User receives BETH tokens instead of ETH
- This provides proof-of-burn for the deposited ETH

#### 5. Dragon Router Special Handling

The strategy has special handling for the dragon router (donation address):
- If the owner is the dragon router, normal withdraw/redeem is used (no BETH conversion)
- Otherwise, BETH conversion is applied

### Abstract Functions

Derived contracts must implement:

```solidity
function _stakeETH(uint256 _amount) internal virtual returns (uint256);
function _unstakeETH(uint256 _amount) internal virtual returns (uint256);
function _getCurrentExchangeRate() internal view virtual returns (uint256);
function decimalsOfExchangeRate() public view virtual returns (uint256);
```

### State Variables

- `lockupPeriod`: Minimum time in seconds users must wait before withdrawing
- `bethContract`: Address of BETH contract
- `userDepositTimestamps`: Mapping of user addresses to their last deposit timestamp

### Events

- `WithdrawalToBETH(address indexed owner, uint256 assets, uint256 shares)`: Emitted when assets are withdrawn and converted to BETH

## RocketPoolYieldBethStrategy Contract

### Purpose

`RocketPoolYieldBethStrategy` is a concrete implementation of `YieldBethStrategy` that integrates with the RocketPool protocol to convert ETH to rETH and back.

### RocketPool Integration

#### 1. ETH → rETH Conversion (`_stakeETH`)

ETH is deposited into RocketPool's deposit pool, which mints rETH tokens:

```solidity
function _stakeETH(uint256 _amount) internal override returns (uint256 rethReceived) {
    IERC20 reth = IERC20(RETH_ADDRESS);
    uint256 currentBalance = reth.balanceOf(address(this));
    
    // Convert ETH to rETH via RocketPool deposit pool
    IRocketDepositPool(ROCKET_DEPOSIT_POOL_ADDRESS).deposit{value: _amount}();

    // Get the rETH received
    rethReceived = reth.balanceOf(address(this)) - currentBalance;
}
```

#### 2. rETH → ETH Conversion (`_unstakeETH`)

rETH is burned to get ETH back:

```solidity
function _unstakeETH(uint256 _amount) internal override returns (uint256 ethReceived) {
    ethReceived = IRocketTokenRETH(RETH_ADDRESS).burn(_amount);
    if (ethReceived == 0) revert RETHBurnFailed();
}
```

#### 3. Exchange Rate Tracking

The strategy tracks the rETH/ETH exchange rate:

```solidity
function _getCurrentExchangeRate() internal view override returns (uint256) {
    return IRocketTokenRETH(RETH_ADDRESS).getExchangeRate();
}

function decimalsOfExchangeRate() public pure override returns (uint256) {
    return 18;
}
```

### Constructor Parameters

```solidity
constructor(
    address _yieldEthDepositPoolAddress,  // RocketPool deposit pool address
    address _asset,                       // rETH token address
    string memory _name,                  // Strategy name
    address _management,                  // Management address
    address _keeper,                      // Keeper address
    address _emergencyAdmin,              // Emergency admin address
    address _donationAddress,             // Dragon router address
    bool _enableBurning,                 // Enable burning flag
    address _tokenizedStrategyAddress,   // TokenizedStrategy implementation
    uint256 _lockupPeriod,               // Lockup period in seconds
    address _bethContract                 // BETH contract address
)
```

### Immutable State Variables

- `ROCKET_DEPOSIT_POOL_ADDRESS`: Address of RocketPool deposit pool contract
- `RETH_ADDRESS`: Address of rETH token contract

### Errors

- `RETHBurnFailed()`: Thrown when rETH burn returns 0 ETH

## Complete Flow Example

### Deposit Flow

1. User calls `deposit(1 ether, user)` with `msg.value = 1 ether`
2. `_stakeETH(1 ether)` is called:
   - ETH is sent to RocketPool deposit pool
   - rETH is minted to strategy (e.g., 0.99 rETH at current exchange rate)
3. User's deposit timestamp is set to `block.timestamp`
4. rETH is approved for TokenizedStrategy
5. TokenizedStrategy's `deposit()` is called, minting shares to user
6. User receives strategy shares

### Withdrawal Flow

1. User calls `withdraw(0.5 ether, user, user)` after lockup period expires
2. Lockup period is checked (must be expired)
3. TokenizedStrategy's `withdraw()` is called:
   - Shares are burned
   - rETH is transferred to strategy contract (e.g., 0.495 rETH)
4. Actual rETH balance transferred is calculated
5. `_unstakeETH(0.495 rETH)` is called:
   - rETH is burned via RocketPool
   - ETH is returned (e.g., 0.5 ether at current exchange rate)
6. ETH is deposited into BETH contract
7. BETH tokens are minted (1:1 with ETH)
8. BETH tokens are transferred to user
9. `WithdrawalToBETH` event is emitted

## Security Considerations

### Reentrancy Protection

All state-changing functions are protected with `nonReentrant` modifier from OpenZeppelin's `ReentrancyGuard`.

### Lockup Period Enforcement

- Lockup period is enforced at the `_withdraw` and `_redeem` level
- Each deposit resets the lockup period
- `availableWithdrawLimit` returns 0 if lockup hasn't expired

### Access Control

- Management: Can update dragon router and enableBurning
- Keeper: Can call `report()` to harvest yield
- Emergency Admin: Can shutdown the strategy
- Users: Can deposit and withdraw (after lockup)

### Exchange Rate Manipulation

- Exchange rate is queried directly from RocketPool protocol
- Rate cannot be manipulated by users
- Rate increases over time as staking rewards accrue

## Testing

The implementation includes comprehensive unit tests covering:

1. **Deposit Tests**:
   - ETH deposit and conversion to rETH
   - Deposit timestamp updates
   - Multiple deposits resetting lockup

2. **Lockup Tests**:
   - Withdrawal blocked before lockup expires
   - Withdrawal allowed after lockup expires
   - `availableWithdrawLimit` enforcement

3. **Withdrawal Tests**:
   - Complete withdrawal flow (rETH → ETH → BETH)
   - Partial withdrawals
   - Full withdrawals
   - Withdrawals with exchange rate changes
   - Multiple partial withdrawals

4. **Exchange Rate Tests**:
   - Exchange rate tracking
   - Profitable reports with yield accrual

5. **Edge Cases**:
   - Zero amount deposits/withdrawals
   - Non-owner withdrawal attempts
   - Shutdown scenarios

## Key Differences from Base Strategy

1. **RocketPool Integration**: Uses RocketPool's deposit pool and rETH token
2. **Exchange Rate**: Tracks rETH/ETH exchange rate (18 decimals)
3. **Burn Mechanism**: Uses RocketPool's `burn()` function to convert rETH to ETH
4. **No Rebasing**: rETH is non-rebasing, yield is captured via exchange rate appreciation

## Future Enhancements

Potential improvements:
1. Support for other yield sources (Lido stETH, etc.)
2. Configurable lockup periods per user
3. Partial lockup releases
4. Emergency withdrawal mechanisms
5. Gas optimization for multiple withdrawals

