// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20, SafeERC20, Setup} from "./Setup.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

/**
 * @title UpgradeableSetup
 * @notice Extended setup for testing upgradeable contracts
 */
contract UpgradeableSetup is Setup {
    // Proxy admin for managing upgrades
    ProxyAdmin public proxyAdmin;

    // Storage slot helpers based on EIP-1967
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function setUp() public virtual override {
        super.setUp();

        // Deploy a proxy admin for managing upgrades
        proxyAdmin = new ProxyAdmin();
    }

    /**
     * @notice Deploy a proxy with an implementation
     * @param _implementation Address of the implementation contract
     * @return proxy Address of the deployed proxy
     */
    function deployProxy(
        address _implementation
    ) public returns (address proxy) {
        return deployProxy(_implementation, "");
    }

    /**
     * @notice Deploy a proxy with an implementation and initialization data
     * @param _implementation Address of the implementation contract
     * @param _data Initialization calldata
     * @return proxy Address of the deployed proxy
     */
    function deployProxy(
        address _implementation,
        bytes memory _data
    ) public returns (address proxy) {
        proxy = address(
            new TransparentUpgradeableProxy(
                _implementation,
                address(proxyAdmin),
                _data
            )
        );
    }

    /**
     * @notice Upgrade a proxy to a new implementation
     * @param _proxy Address of the proxy to upgrade
     * @param _newImplementation Address of the new implementation
     */
    function upgradeProxy(address _proxy, address _newImplementation) public {
        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(payable(_proxy)),
            _newImplementation
        );
    }

    /**
     * @notice Upgrade a proxy and call a function
     * @param _proxy Address of the proxy to upgrade
     * @param _newImplementation Address of the new implementation
     * @param _data Calldata for the function to call
     */
    function upgradeProxyAndCall(
        address _proxy,
        address _newImplementation,
        bytes memory _data
    ) public {
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(_proxy)),
            _newImplementation,
            _data
        );
    }

    /**
     * @notice Get the current implementation of a proxy
     * @param _proxy Address of the proxy
     * @return implementation Address of the current implementation
     */
    function getImplementation(
        address _proxy
    ) public view returns (address implementation) {
        // Get implementation from the proxy admin
        return
            proxyAdmin.getProxyImplementation(
                ITransparentUpgradeableProxy(payable(_proxy))
            );
    }

    /**
     * @notice Read a storage slot at a specific address
     * @param _target Address to read from
     * @param _slot Storage slot to read
     * @return value The value at the storage slot
     */
    function readStorageSlot(
        address _target,
        uint256 _slot
    ) public view returns (bytes32 value) {
        // Use vm.load to read storage from target address
        value = vm.load(_target, bytes32(_slot));
    }

    /**
     * @notice Initialize a strategy with common parameters
     * @param _strategy Address of the strategy proxy
     * @param _asset Address of the asset
     * @param _name Name of the strategy
     */
    function initializeStrategy(
        address _strategy,
        address _asset,
        string memory _name
    ) public {
        IStrategy(_strategy).initialize(
            _asset,
            _name,
            management,
            performanceFeeRecipient,
            keeper
        );
    }

    /**
     * @notice Deploy and initialize an upgradeable strategy
     * @param _implementation Address of the implementation
     * @param _asset Address of the asset
     * @param _name Name of the strategy
     * @return strategy Address of the deployed strategy proxy
     */
    function deployUpgradeableStrategy(
        address _implementation,
        address _asset,
        string memory _name
    ) public returns (address strategy) {
        // Deploy proxy without initialization
        strategy = deployProxy(_implementation);

        // Initialize the strategy
        initializeStrategy(strategy, _asset, _name);
    }

    /**
     * @notice Check that storage layout is preserved after upgrade
     * @param _proxy Address of the proxy
     * @param _slot Storage slot to check
     * @param _expectedValue Expected value at the slot
     */
    function assertStorageSlot(
        address _proxy,
        uint256 _slot,
        bytes32 _expectedValue
    ) public {
        bytes32 actualValue = readStorageSlot(_proxy, _slot);
        assertEq(actualValue, _expectedValue, "Storage slot mismatch");
    }

    /**
     * @notice Verify proxy is properly initialized
     * @param _proxy Address of the proxy
     * @param _expectedImpl Expected implementation address
     */
    function verifyProxy(address _proxy, address _expectedImpl) public {
        address actualImpl = getImplementation(_proxy);
        assertEq(actualImpl, _expectedImpl, "Implementation mismatch");

        // Verify admin is set correctly
        address admin = proxyAdmin.getProxyAdmin(
            ITransparentUpgradeableProxy(payable(_proxy))
        );
        assertEq(admin, address(proxyAdmin), "Admin mismatch");
    }
}
