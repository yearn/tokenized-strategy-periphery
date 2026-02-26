// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, ERC20, IStrategy} from "./utils/Setup.sol";

import {MockStrategy} from "./mocks/MockStrategy.sol";
import {BaseConvertor4626} from "../Bases/convertors/BaseConvertor4626.sol";
import {IBaseConvertor4626} from "../Bases/convertors/IBaseConvertor4626.sol";
import {MockConvertorOracle} from "./mocks/MockConvertorOracle.sol";
import {Auction} from "../Auctions/Auction.sol";

contract BaseConvertor4626Test is Setup {
    BaseConvertor4626 public convertor;
    IBaseConvertor4626 public convertorInterface;
    IStrategy public convertorStrategy;
    IStrategy public targetVault;
    MockConvertorOracle public oracle;

    ERC20 public want;

    function setUp() public override {
        super.setUp();

        want = ERC20(tokenAddrs["USDC"]);

        targetVault = IStrategy(address(new MockStrategy(address(want))));

        oracle = new MockConvertorOracle();
        oracle.setPrice(1e36); // 1 asset per 1 want

        convertor = new BaseConvertor4626(
            address(asset),
            "Base Convertor 4626",
            address(want),
            address(targetVault),
            address(oracle)
        );
        convertorInterface = IBaseConvertor4626(address(convertor));
        convertorStrategy = IStrategy(address(convertor));

        convertorStrategy.setKeeper(keeper);
        convertorStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        convertorStrategy.setPendingManagement(management);

        vm.prank(management);
        convertorStrategy.acceptManagement();

        vm.startPrank(management);
        convertor.setMinAmountToSell(1);
        convertor.setDoHealthCheck(false);
        vm.stopPrank();
    }

    function test_setup() public {
        assertEq(convertorStrategy.asset(), address(asset));
        assertEq(address(convertor.want()), address(want));
        assertEq(address(convertor.vault()), address(targetVault));
        assertEq(convertor.oracle(), address(oracle));

        Auction sellAuction = convertor.sellAssetAuction();
        Auction buyAuction = convertor.buyAssetAuction();
        assertEq(sellAuction.want(), address(want));
        assertEq(buyAuction.want(), address(asset));
        assertEq(sellAuction.stepDecayRate(), 1);
        assertEq(buyAuction.stepDecayRate(), 1);
        assertEq(sellAuction.stepDuration(), 60);
        assertEq(buyAuction.stepDuration(), 60);
        assertTrue(sellAuction.governanceOnlyKick());
        assertTrue(buyAuction.governanceOnlyKick());
    }

    function test_deployLooseWant(uint256 _amount) public {
        vm.assume(_amount > 1e8 && _amount < maxFuzzAmount);

        airdrop(want, address(convertor), _amount);

        vm.prank(keeper);
        uint256 deployed = convertor.deployLooseWant();

        assertEq(deployed, _amount);
        assertEq(convertor.balanceOfWant(), 0);
        assertGt(convertor.balanceOfVault(), 0);
    }

    function test_tendTrigger_depositsLooseWant(uint256 _amount) public {
        vm.assume(_amount > 1e8 && _amount < maxFuzzAmount);

        (bool shouldTend, ) = convertorStrategy.tendTrigger();
        assertFalse(shouldTend);

        airdrop(want, address(convertor), _amount);

        (shouldTend, ) = convertorStrategy.tendTrigger();
        assertTrue(shouldTend);

        vm.prank(keeper);
        convertorStrategy.tend();

        assertEq(convertor.balanceOfWant(), 0);
        assertGt(convertor.balanceOfVault(), 0);

        (shouldTend, ) = convertorStrategy.tendTrigger();
        assertFalse(shouldTend);
    }

    function test_freeWantFromVault_keeperOnly(uint256 _amount) public {
        vm.assume(_amount > 1e8 && _amount < maxFuzzAmount);

        airdrop(want, address(convertor), _amount);

        vm.prank(keeper);
        convertor.deployLooseWant();

        uint256 toFree = _amount / 2;
        vm.prank(user);
        vm.expectRevert();
        convertorInterface.freeWantFromVault(toFree);

        vm.prank(keeper);
        convertorInterface.freeWantFromVault(toFree);

        assertGt(convertor.balanceOfWant(), 0);
    }

    function test_kickWantAuction_afterFreeWantFromVault(
        uint256 _amount
    ) public {
        vm.assume(_amount > 1e8 && _amount < maxFuzzAmount);

        airdrop(want, address(convertor), _amount);

        vm.prank(keeper);
        convertor.deployLooseWant();

        assertEq(convertor.balanceOfWant(), 0);
        assertGt(convertor.balanceOfVault(), 0);

        vm.prank(keeper);
        convertorInterface.freeWantFromVault(type(uint256).max);
        assertGt(convertor.balanceOfWant(), 0);

        vm.prank(keeper);
        uint256 kicked = convertor.kickAuction(address(want));

        assertGt(kicked, 0);
        assertTrue(convertor.buyAssetAuction().isActive(address(want)));
    }

    function test_freeWant_freesAndKicksWantAuction(uint256 _amount) public {
        vm.assume(_amount > 1e8 && _amount < maxFuzzAmount);

        airdrop(want, address(convertor), _amount);

        vm.prank(keeper);
        convertor.deployLooseWant();

        assertEq(convertor.balanceOfWant(), 0);
        assertGt(convertor.balanceOfVault(), 0);

        vm.prank(keeper);
        convertorInterface.freeWant(type(uint256).max);

        assertTrue(convertor.buyAssetAuction().isActive(address(want)));
    }

    function test_report_accountsVaultAndAuctionBalances(
        uint256 _amount
    ) public {
        vm.assume(_amount > 1e8 && _amount < maxFuzzAmount);

        uint256 vaultWant = _amount / 3;
        uint256 sellSide = _amount / 4;
        uint256 buySide = _amount / 5;

        airdrop(want, address(convertor), vaultWant);
        vm.prank(keeper);
        convertor.deployLooseWant();

        airdrop(asset, address(convertor.sellAssetAuction()), sellSide);
        airdrop(want, address(convertor.buyAssetAuction()), buySide);

        vm.prank(keeper);
        convertorStrategy.report();

        uint256 expected = convertor.balanceOfAsset() +
            convertor.balanceOfAssetInAuction() +
            convertor.balanceOfWantInAuction() +
            convertor.balanceOfWant() +
            convertor.valueOfVault();

        assertEq(convertorStrategy.totalAssets(), expected);
    }
}
