// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { RocketPoolYieldBethStrategy } from "./RocketPoolYieldBethStrategy.sol";
import { IStrategyInterface } from "../interfaces/IStrategyInterface.sol";
import { YieldSkimmingTokenizedStrategy } from "@octant-core/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";

/**
 * @title YieldBethStrategyFactory
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Factory contract for deploying Yield Beth Skimming Strategy instances
 * @dev Deploys new strategy instances with specified parameters including lockup period
 *
 *      FACTORY PATTERN:
 *      - Deploys YieldBethStrategy instances with lockupPeriod parameter
 *      - Tracks deployments by asset address
 *      - Manages factory-level configuration (management, keeper, etc.)
 *
 *      DEPLOYMENT:
 *      - Each strategy is deployed with unique lockupPeriod
 *      - All strategies share factory-level roles (management, keeper, etc.)
 *      - TokenizedStrategy implementation is deployed once and reused
 */
contract YieldBethStrategyFactory {
    /// @notice Emitted when a new strategy is deployed
    /// @param strategy Address of the newly deployed strategy
    /// @param asset Address of the underlying asset (rETH)
    event NewStrategy(address indexed strategy, address indexed asset);

    /// @notice Address with emergency admin role for deployed strategies
    address public immutable emergencyAdmin;

    /// @notice Address of TokenizedStrategy implementation contract
    /// @dev Deployed once and reused for all strategies
    address public immutable tokenizedStrategyAddress;

    /// @notice Address with management role for deployed strategies
    address public management;

    /// @notice Address that receives donated/minted yield (dragon router)
    address public donationAddress;

    /// @notice Address with keeper role for deployed strategies
    address public keeper;

    /// @notice Whether loss-protection burning from donation address is enabled
    bool public enableBurning = true;

    /// @notice Mapping of asset addresses to deployed strategy addresses
    /// @dev asset => strategy
    mapping(address => address) public deployments;

    /**
     * @notice Initializes the factory with role addresses
     * @param _management Address with management role for strategies
     * @param _donationAddress Address that receives donated/minted yield (dragon router)
     * @param _keeper Address with keeper role for strategies
     * @param _emergencyAdmin Address with emergency admin role for strategies
     */
    constructor(address _management, address _donationAddress, address _keeper, address _emergencyAdmin) {
        management = _management;
        donationAddress = _donationAddress;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;

        // Deploy the standard TokenizedStrategy implementation
        tokenizedStrategyAddress = address(new YieldSkimmingTokenizedStrategy());
    }

    /**
     * @notice Deploys a new RocketPool Yield Beth Strategy
     * @dev Creates a new strategy instance with specified parameters
     * @param _asset Address of rETH token (the strategy's underlying asset)
     * @param _name Name for the strategy
     * @param _lockupPeriod Minimum time in seconds users must wait before withdrawing
     * @param _rocketDepositPool Address of RocketPool deposit pool contract
     * @param _rocketTokenRETH Address of RocketPool rETH token contract
     * @param _bethContract Address of BETH contract
     * @return strategy Address of the newly deployed strategy
     */
    function newRocketPoolStrategy(
        address _yieldEthDepositPoolAddress,
        address _asset,
        string calldata _name,
        uint256 _lockupPeriod,
        address _rocketDepositPool,
        address _rocketTokenRETH,
        address _bethContract
    ) external virtual returns (address strategy) {
        // Deploy new Yield Beth strategy
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new RocketPoolYieldBethStrategy(
                    _yieldEthDepositPoolAddress,
                    _asset,
                    _name,
                    management,
                    keeper,
                    emergencyAdmin,
                    donationAddress,
                    enableBurning,
                    tokenizedStrategyAddress,
                    _lockupPeriod,
                    _bethContract
                )
            )
        );

        strategy = address(_newStrategy);

        emit NewStrategy(strategy, _asset);

        deployments[_asset] = strategy;
    }

    /**
     * @notice Updates factory-level addresses
     * @dev Only callable by management
     * @param _management New management address
     * @param _donationAddress New donation address (dragon router)
     * @param _keeper New keeper address
     */
    function setAddresses(address _management, address _donationAddress, address _keeper) external {
        require(msg.sender == management, "!management");
        management = _management;
        donationAddress = _donationAddress;
        keeper = _keeper;
    }

    /**
     * @notice Updates enableBurning flag for future deployments
     * @dev Only callable by management
     * @param _enableBurning New enableBurning value
     */
    function setEnableBurning(bool _enableBurning) external {
        require(msg.sender == management, "!management");
        enableBurning = _enableBurning;
    }

    /**
     * @notice Checks if an address is a deployed strategy from this factory
     * @param _strategy Address to check
     * @return isDeployed True if the address is a deployed strategy
     */
    function isDeployedStrategy(address _strategy) external view returns (bool isDeployed) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}

