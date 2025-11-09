// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {RocketPoolYieldBethStrategy as Strategy} from "../../strategies/RocketPoolYieldBethStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {YieldBethStrategyFactory as StrategyFactory} from "../../strategies/YieldBethStrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";
import {BETH} from "@beth/BETH.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {YieldSkimmingTokenizedStrategy} from "@octant-core/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";

/**
 * @title YieldBethSetup
 * @notice Base test setup for Yield Beth Skimming Strategy tests
 * @dev Provides common setup, mocks, and helper functions for testing
 */
contract YieldBethSetup is Test, IEvents {
    // ============================================
    // CONTRACT INSTANCES
    // ============================================

    /// @notice rETH token (the strategy's underlying asset)
    ERC20 public asset;

    /// @notice Strategy instance
    IStrategyInterface public strategy;

    /// @notice Factory instance
    StrategyFactory public strategyFactory;

    // ============================================
    // ROLE ADDRESSES
    // ============================================

    /// @notice User address for testing
    address public user = address(10);

    /// @notice Keeper address
    address public keeper = address(4);

    /// @notice Management address
    address public management = address(1);

    /// @notice Dragon router address (donation address)
    address public dragonRouter = address(3);

    /// @notice Emergency admin address
    address public emergencyAdmin = address(5);

    // ============================================
    // MOCK CONTRACTS
    // ============================================

    /// @notice Mock RocketPool deposit pool
    MockRocketDepositPool public rocketDepositPool;

    /// @notice Mock RocketPool rETH token
    MockRocketTokenRETH public rocketTokenRETH;

    /// @notice BETH contract instance
    BETH public bethContract;

    // ============================================
    // CONFIGURATION
    // ============================================

    /// @notice Lockup period for testing (7 days)
    uint256 public lockupPeriod = 7 days;

    /// @notice Enable burning flag
    bool public enableBurning = true;

    /// @notice TokenizedStrategy implementation address
    address public tokenizedStrategyAddress;

    /// @notice Asset decimals
    uint256 public decimals;

    /// @notice Maximum fuzz amount
    uint256 public maxFuzzAmount;

    /// @notice Minimum fuzz amount
    uint256 public minFuzzAmount = 10_000;

    /// @notice Default profit max unlock time (10 days)
    uint256 public profitMaxUnlockTime = 10 days;

    // ============================================
    // SETUP
    // ============================================

    function setUp() public virtual {
        // Deploy BETH contract
        bethContract = new BETH();

        // Deploy rETH token (mock) - use MockRocketTokenRETH as the asset
        rocketTokenRETH = new MockRocketTokenRETH();
        asset = ERC20(address(rocketTokenRETH));

        // Deploy mock RocketPool deposit pool
        rocketDepositPool = new MockRocketDepositPool();
        rocketDepositPool.setRethToken(address(rocketTokenRETH));

        // Fund the mock rETH contract with ETH for burn operations
        vm.deal(address(rocketTokenRETH), 1000 ether);

        // Deploy YieldSkimmingTokenizedStrategy implementation
        tokenizedStrategyAddress = address(new YieldSkimmingTokenizedStrategy());

        // Deploy factory
        strategyFactory = new StrategyFactory(management, dragonRouter, keeper, emergencyAdmin);

        // Deploy strategy
        strategy = IStrategyInterface(setUpStrategy());

        // Set decimals
        decimals = asset.decimals();

        // Set max fuzz amount to 1,000,000 of the asset
        maxFuzzAmount = 1_000_000 * 10 ** decimals;

        // Label all addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(dragonRouter, "dragonRouter");
        vm.label(address(rocketDepositPool), "rocketDepositPool");
        vm.label(address(rocketTokenRETH), "rocketTokenRETH");
        vm.label(address(bethContract), "bethContract");
    }

    /**
     * @notice Sets up and returns a new strategy instance
     * @return Strategy address
     */
    function setUpStrategy() public returns (address) {
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                new Strategy(
                    address(rocketDepositPool), // _yieldEthDepositPoolAddress
                    address(asset), // _asset (rETH token)
                    "Yield Beth Strategy", // _name
                    management, // _management
                    keeper, // _keeper
                    emergencyAdmin, // _emergencyAdmin
                    dragonRouter, // _donationAddress
                    enableBurning, // _enableBurning
                    tokenizedStrategyAddress, // _tokenizedStrategyAddress
                    lockupPeriod, // _lockupPeriod
                    address(bethContract) // _bethContract
                )
            )
        );

        return address(_strategy);
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Deposits ETH into strategy via deposit function
     * @param _strategy Strategy address
     * @param _user User address
     * @param _amount Amount of ETH to deposit (in wei)
     */
    function depositETHIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.deal(_user, _amount);
        
        // Pre-approve the strategy to transfer rETH (needed because deposit transfers rETH to user first)
        // We need to estimate the rETH amount that will be received
        // For simplicity, we'll approve a large amount
        vm.prank(_user);
        ERC20(address(asset)).approve(address(_strategy), type(uint256).max);
        
        vm.prank(_user);
        Strategy(payable(address(_strategy))).deposit{value: _amount}(_amount, _user);
    }

    /**
     * @notice Mints and deposits ETH into strategy
     * @param _strategy Strategy address
     * @param _user User address
     * @param _amount Amount of ETH to deposit (in wei)
     */
    function mintAndDepositETHIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.deal(_user, _amount);
        depositETHIntoStrategy(_strategy, _user, _amount);
    }

    /**
     * @notice Airdrops tokens to an address
     * @param _asset Token to airdrop
     * @param _to Recipient address
     * @param _amount Amount to airdrop
     */
    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    /**
     * @notice Sets dragon router address
     * @param _newDragonRouter New dragon router address
     */
    function setDragonRouter(address _newDragonRouter) public {
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setDragonRouter(_newDragonRouter);

        // Fast forward to bypass cooldown
        skip(7 days);

        // Anyone can finalize after cooldown
        ITokenizedStrategy(address(strategy)).finalizeDragonRouterChange();
    }

    /**
     * @notice Sets enableBurning flag
     * @param _enableBurning New enableBurning value
     */
    function setEnableBurning(bool _enableBurning) public {
        vm.prank(management);
        (bool success, ) = address(strategy).call(abi.encodeWithSignature("setEnableBurning(bool)", _enableBurning));
        require(success, "setEnableBurning failed");
    }
}

// ============================================
// MOCK CONTRACTS
// ============================================

/**
 * @title MockRocketDepositPool
 * @notice Mock RocketPool deposit pool for testing
 * @dev Simulates ETH → rETH conversion
 */
contract MockRocketDepositPool {
    /// @notice Mock rETH token address
    address public rethToken;

    constructor() {
        // Will be set by test setup
    }

    /**
     * @notice Sets the rETH token address
     * @param _rethToken rETH token address
     */
    function setRethToken(address _rethToken) external {
        rethToken = _rethToken;
    }

    /**
     * @notice Deposits ETH and mints rETH
     * @dev Simulates RocketPool deposit - mints rETH at 1:1 ratio for simplicity
     */
    function deposit() external payable {
        require(msg.value > 0, "Zero deposit");
        // Mint rETH to caller at 1:1 ratio (simplified for testing)
        // In reality, exchange rate would apply
        MockRocketTokenRETH(payable(rethToken)).mint(msg.sender, msg.value);
    }
}

/**
 * @title MockRocketTokenRETH
 * @notice Mock RocketPool rETH token for testing
 * @dev Simulates rETH token with exchange rate and burn mechanism
 */
contract MockRocketTokenRETH {
    /// @notice Current exchange rate (rETH → ETH)
    /// @dev Starts at 1.0 and increases over time
    uint256 public exchangeRate = 1e18; // 1.0 with 18 decimals

    /// @notice Rate increase per second (simulating staking rewards)
    uint256 public rateIncreasePerSecond = 1e12; // 0.000001 per second

    /// @notice Last update timestamp
    uint256 public lastUpdateTime;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string public name = "Rocket Pool ETH";
    string public symbol = "rETH";
    uint8 public decimals = 18;

    constructor() {
        lastUpdateTime = block.timestamp;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero");
        require(to != address(0), "Transfer to zero");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "Insufficient balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "Mint to zero");
        _totalSupply += amount;
        _balances[to] += amount;
    }

    function _burn(address from, uint256 amount) internal {
        require(from != address(0), "Burn from zero");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "Insufficient balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            _totalSupply -= amount;
        }
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from zero");
        require(spender != address(0), "Approve to zero");
        _allowances[owner][spender] = amount;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @notice Returns current exchange rate
     * @return Current exchange rate (18 decimals)
     */
    function getExchangeRate() external view returns (uint256) {
        // Update rate based on time elapsed
        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        return exchangeRate + (rateIncreasePerSecond * timeElapsed);
    }

    /**
     * @notice Burns rETH and returns ETH
     * @param _rethAmount Amount of rETH to burn
     * @return ethAmount Amount of ETH returned
     */
    function burn(uint256 _rethAmount) external returns (uint256) {
        require(_rethAmount > 0, "Zero burn");
        require(_balances[msg.sender] >= _rethAmount, "Insufficient balance");

        // Get current exchange rate
        uint256 currentRate = this.getExchangeRate();

        // Calculate ETH amount (rETH * exchange rate)
        uint256 ethAmount = (_rethAmount * currentRate) / 1e18;

        // Burn rETH
        _burn(msg.sender, _rethAmount);

        // Transfer ETH to caller (contract must have ETH balance)
        // In tests, we'll need to fund the contract with ETH
        require(address(this).balance >= ethAmount, "Insufficient ETH in contract");
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        return ethAmount;
    }

    /**
     * @notice Receives ETH (for testing - to fund the contract)
     */
    receive() external payable {}

    /**
     * @notice Mints rETH (for testing)
     * @param _to Recipient address
     * @param _amount Amount to mint
     */
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    /**
     * @notice Updates exchange rate (for testing)
     * @param _newRate New exchange rate
     */
    function setExchangeRate(uint256 _newRate) external {
        exchangeRate = _newRate;
        lastUpdateTime = block.timestamp;
    }
}

