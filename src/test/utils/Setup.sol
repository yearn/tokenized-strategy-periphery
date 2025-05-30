// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {VyperDeployer} from "./VyperDeployer.sol";

import {Roles} from "@yearn-vaults/interfaces/Roles.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";

import {MockStrategy} from "../mocks/MockStrategy.sol";
import {Clonable} from "../../utils/Clonable.sol";

contract Setup is ExtendedTest, Clonable {
    using SafeERC20 for ERC20;

    VyperDeployer public vyperDeployer = new VyperDeployer();

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategy public mockStrategy;

    // Vault contracts to test with.
    IVault public vault;
    IVaultFactory public vaultFactory;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public daddy = address(69);
    address public management = address(1);
    address public vaultManagement = address(2);
    address public performanceFeeRecipient = address(3);
    address public protocolFeeRecipient = address(56);

    mapping(string => address) public tokenAddrs;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;
    uint256 public WAD = 1e18;

    // Fuzz amount
    uint256 public maxFuzzAmount = 1e12;
    uint256 public minFuzzAmount = MAX_BPS;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _setTokenAddrs();

        // Make sure everything works with USDT
        asset = ERC20(tokenAddrs["USDT"]);

        // Set decimals
        decimals = asset.decimals();

        mockStrategy = setUpStrategy();

        vaultFactory = IVaultFactory(mockStrategy.FACTORY());

        // label all the used addresses for traces
        vm.label(user, "user");
        vm.label(daddy, "daddy");
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(mockStrategy), "strategy");
        vm.label(vaultManagement, "vault management");
        vm.label(address(vaultFactory), " vault factory");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpVault() public returns (IVault) {
        if (original == address(0)) {
            original = vyperDeployer.deployContract(
                "lib/yearn-vaults-v3/contracts/",
                "VaultV3"
            );
        }

        IVault _vault = IVault(_clone());

        _vault.initialize(
            address(asset),
            "Test vault",
            "tsVault",
            management,
            10 days
        );

        vm.prank(management);
        // Give the vault manager all the roles
        _vault.set_role(vaultManagement, Roles.ALL);

        vm.prank(vaultManagement);
        _vault.set_deposit_limit(type(uint256).max);

        return _vault;
    }

    function setUpStrategy() public returns (IStrategy) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategy _strategy = IStrategy(
            address(new MockStrategy(address(asset)))
        );

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);
        // Accept management.
        vm.prank(management);
        _strategy.acceptManagement();

        return _strategy;
    }

    function depositIntoStrategy(
        IStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.startPrank(_user);
        asset.forceApprove(address(_strategy), _amount);

        _strategy.deposit(_amount, _user);
        vm.stopPrank();
    }

    function mintAndDepositIntoStrategy(
        IStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    function addStrategyToVault(IVault _vault, IStrategy _strategy) public {
        vm.prank(vaultManagement);
        _vault.add_strategy(address(_strategy));

        vm.prank(vaultManagement);
        _vault.update_max_debt_for_strategy(
            address(_strategy),
            type(uint256).max
        );
    }

    function addDebtToStrategy(
        IVault _vault,
        IStrategy _strategy,
        uint256 _amount
    ) public {
        vm.prank(vaultManagement);
        _vault.update_debt(address(_strategy), _amount);
    }

    function addStrategyAndDebt(
        IVault _vault,
        IStrategy _strategy,
        address _user,
        uint256 _amount
    ) public {
        addStrategyToVault(_vault, _strategy);
        mintAndDepositIntoStrategy(IStrategy(address(_vault)), _user, _amount);
        addDebtToStrategy(_vault, _strategy, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategy _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = vaultFactory.governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        vaultFactory.set_protocol_fee_recipient(protocolFeeRecipient);

        vm.prank(gov);
        vaultFactory.set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        mockStrategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }
}
