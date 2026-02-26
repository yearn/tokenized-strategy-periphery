// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, ERC20, IStrategy} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseConvertor} from "../Bases/convertors/BaseConvertor.sol";
import {MockConvertorOracle} from "./mocks/MockConvertorOracle.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {Auction} from "../Auctions/Auction.sol";

contract BaseConvertorTest is Setup {
    using Math for uint256;

    uint256 internal constant ORACLE_SCALE = 1e36;

    struct PricingCase {
        uint8 assetDecimals;
        uint8 wantDecimals;
        uint256 oraclePrice;
        uint256 assetAmount;
        uint256 wantAmount;
        uint16 startingBps;
        uint16 maxSlippageBps;
    }

    BaseConvertor public convertor;
    IStrategy public convertorStrategy;
    MockConvertorOracle public oracle;

    ERC20 public want;

    function setUp() public override {
        super.setUp();

        want = ERC20(tokenAddrs["USDC"]);

        oracle = new MockConvertorOracle();
        oracle.setPrice(1e36); // 1 asset per 1 want

        convertor = new BaseConvertor(
            address(asset),
            "Base Convertor",
            address(want),
            address(oracle)
        );
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
        assertEq(convertor.oracle(), address(oracle));
        assertEq(convertor.decayRate(), 1);
        assertEq(convertorStrategy.management(), management);
        assertEq(convertorStrategy.keeper(), keeper);

        Auction sellAuction = convertor.sellAssetAuction();
        Auction buyAuction = convertor.buyAssetAuction();
        assertEq(sellAuction.receiver(), address(convertor));
        assertEq(buyAuction.receiver(), address(convertor));
        assertEq(sellAuction.want(), address(want));
        assertEq(buyAuction.want(), address(asset));
        assertEq(sellAuction.stepDecayRate(), 1);
        assertEq(buyAuction.stepDecayRate(), 1);
        assertEq(sellAuction.stepDuration(), 60);
        assertEq(buyAuction.stepDuration(), 60);
        assertTrue(sellAuction.governanceOnlyKick());
        assertTrue(buyAuction.governanceOnlyKick());
    }

    function test_setAuctionStep_passthrough() public {
        Auction sellAuction = convertor.sellAssetAuction();
        Auction buyAuction = convertor.buyAssetAuction();

        vm.startPrank(management);
        convertor.setAuctionStepDecayRate(address(asset), 7);
        convertor.setAuctionStepDecayRate(address(want), 9);
        convertor.setAuctionStepDuration(address(asset), 120);
        convertor.setAuctionStepDuration(address(want), 180);
        vm.stopPrank();

        assertEq(sellAuction.stepDecayRate(), 7);
        assertEq(buyAuction.stepDecayRate(), 9);
        assertEq(sellAuction.stepDuration(), 120);
        assertEq(buyAuction.stepDuration(), 180);
    }

    function test_setDecayRate_appliedForAssetAndWantAuctions() public {
        Auction sellAuction = convertor.sellAssetAuction();
        Auction buyAuction = convertor.buyAssetAuction();

        vm.prank(management);
        convertor.setDecayRate(7);

        assertEq(convertor.decayRate(), 7);

        airdrop(asset, address(convertor), 100 * 10 ** asset.decimals());
        vm.prank(keeper);
        convertor.kickAuction(address(asset));
        assertEq(sellAuction.stepDecayRate(), 7);

        airdrop(want, address(convertor), 100 * 10 ** want.decimals());
        vm.prank(keeper);
        convertor.kickAuction(address(want));
        assertEq(buyAuction.stepDecayRate(), 7);
    }

    function test_enableSweepAuctionToken_passthrough(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        ERC20 otherToken = ERC20(tokenAddrs["DAI"]);
        Auction buyAuction = convertor.buyAssetAuction();

        (, uint64 scalerBefore, ) = buyAuction.auctions(address(otherToken));
        assertEq(scalerBefore, 0);

        vm.prank(management);
        convertor.enableAuctionToken(address(otherToken));

        (, uint64 scalerEnabled, ) = buyAuction.auctions(address(otherToken));
        assertGt(scalerEnabled, 0);

        airdrop(otherToken, address(buyAuction), _amount);
        uint256 strategyBalBefore = otherToken.balanceOf(address(convertor));

        vm.prank(management);
        convertor.sweepAuctionToken(address(otherToken), address(otherToken));

        assertEq(otherToken.balanceOf(address(buyAuction)), 0);
        assertEq(
            otherToken.balanceOf(address(convertor)),
            strategyBalBefore + _amount
        );
    }

    function test_kickAuction_asset(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        airdrop(asset, address(convertor), _amount);

        vm.prank(keeper);
        uint256 kicked = convertor.kickAuction(address(asset));

        assertEq(kicked, _amount);
        assertTrue(convertor.sellAssetAuction().isActive(address(asset)));
    }

    function test_kickAuction_want(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        airdrop(want, address(convertor), _amount);

        vm.prank(keeper);
        uint256 kicked = convertor.kickAuction(address(want));

        assertEq(kicked, _amount);
        assertTrue(convertor.buyAssetAuction().isActive(address(want)));
    }

    function test_kickAuction_pricesFromOracle() public {
        uint256 amount = 100 * 10 ** asset.decimals();

        vm.startPrank(management);
        convertor.setStartingPriceBps(10_000);
        convertor.setMaxSlippageBps(500);
        convertor.setOracle(address(oracle));
        vm.stopPrank();

        oracle.setPrice(2e36); // 2 assets per 1 want

        airdrop(asset, address(convertor), amount);
        vm.prank(keeper);
        convertor.kickAuction(address(asset));

        assertEq(convertor.sellAssetAuction().startingPrice(), 50);
        assertEq(
            convertor.sellAssetAuction().minimumPrice(),
            475_000_000_000_000_000
        );

        airdrop(want, address(convertor), amount);
        vm.prank(keeper);
        convertor.kickAuction(address(want));

        assertEq(convertor.buyAssetAuction().startingPrice(), 200);
        assertEq(
            convertor.buyAssetAuction().minimumPrice(),
            1_900_000_000_000_000_000
        );
    }

    function test_kickAuction_nonAssetDefaultsToBuyAuction(
        uint256 _amount
    ) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        ERC20 otherToken = ERC20(tokenAddrs["DAI"]);
        vm.prank(management);
        convertor.enableAuctionToken(address(otherToken));
        airdrop(otherToken, address(convertor), _amount);

        vm.prank(keeper);
        uint256 kicked = convertor.kickAuction(address(otherToken));

        assertEq(kicked, _amount);
        assertTrue(convertor.buyAssetAuction().isActive(address(otherToken)));
        assertEq(convertor.buyAssetAuction().startingPrice(), 1_000_000);
        assertEq(convertor.buyAssetAuction().minimumPrice(), 0);
        assertEq(convertor.buyAssetAuction().stepDecayRate(), 50);
    }

    function test_kickAuction_pricesFromOracle_decimalMismatch() public {
        ERC20 want18 = ERC20(tokenAddrs["WETH"]);
        MockConvertorOracle oracle18 = new MockConvertorOracle();
        oracle18.setPrice(2_000e24); // 1 WETH => 2,000 USDT

        BaseConvertor convertor18 = new BaseConvertor(
            address(asset),
            "Base Convertor 18d",
            address(want18),
            address(oracle18)
        );
        IStrategy convertor18Strategy = IStrategy(address(convertor18));
        convertor18Strategy.setKeeper(keeper);
        convertor18Strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        convertor18Strategy.setPendingManagement(management);

        vm.prank(management);
        convertor18Strategy.acceptManagement();

        vm.startPrank(management);
        convertor18.setMinAmountToSell(1);
        convertor18.setDoHealthCheck(false);
        convertor18.setStartingPriceBps(10_000);
        convertor18.setMaxSlippageBps(500);
        vm.stopPrank();

        uint256 assetAmount = 2_000_000 * 10 ** asset.decimals();
        airdrop(asset, address(convertor18), assetAmount);

        vm.prank(keeper);
        convertor18.kickAuction(address(asset));

        assertEq(convertor18.sellAssetAuction().startingPrice(), 1_000);
        assertEq(
            convertor18.sellAssetAuction().minimumPrice(),
            475_000_000_000_000
        );

        uint256 wantAmount = 10 * 10 ** want18.decimals();
        airdrop(want18, address(convertor18), wantAmount);

        vm.prank(keeper);
        convertor18.kickAuction(address(want18));

        assertEq(convertor18.buyAssetAuction().startingPrice(), 20_000);
        assertEq(
            convertor18.buyAssetAuction().minimumPrice(),
            1_900_000_000_000_000_000_000
        );
    }

    function test_kickAuction_pricingMath_accountsForDifferentDecimals()
        public
    {
        _assertPricingCase(
            PricingCase({
                assetDecimals: 6,
                wantDecimals: 18,
                oraclePrice: 2_000e24, // 1 want => 2,000 asset
                assetAmount: 2_000_000 * 1e6,
                wantAmount: 10 * 1e18,
                startingBps: 10_250,
                maxSlippageBps: 321
            })
        );

        _assertPricingCase(
            PricingCase({
                assetDecimals: 18,
                wantDecimals: 6,
                oraclePrice: 5e35, // 1 want => 0.5 asset
                assetAmount: 250 * 1e18,
                wantAmount: 1_000_000 * 1e6,
                startingBps: 10_125,
                maxSlippageBps: 777
            })
        );

        _assertPricingCase(
            PricingCase({
                assetDecimals: 8,
                wantDecimals: 12,
                oraclePrice: 3e36, // 1 want => 3 asset
                assetAmount: 75_000 * 1e8,
                wantAmount: 30_000 * 1e12,
                startingBps: 10_333,
                maxSlippageBps: 500
            })
        );
    }

    function test_report_accountsForAuctionBalances(uint256 _amount) public {
        vm.assume(_amount > 1e8 && _amount < maxFuzzAmount);

        uint256 sellSide = _amount / 3;
        uint256 buySide = _amount / 4;
        uint256 looseWant = _amount / 5;

        airdrop(asset, address(convertor.sellAssetAuction()), sellSide);
        airdrop(want, address(convertor.buyAssetAuction()), buySide);
        airdrop(want, address(convertor), looseWant);

        vm.prank(keeper);
        convertorStrategy.report();

        uint256 expected = convertor.balanceOfAsset() +
            convertor.balanceOfAssetInAuction() +
            convertor.balanceOfWantInAuction() +
            convertor.balanceOfWant();

        assertEq(convertorStrategy.totalAssets(), expected);
    }

    function _assertPricingCase(PricingCase memory _case) internal {
        MockToken _asset = new MockToken(
            "Mock Asset",
            "mAST",
            _case.assetDecimals
        );
        MockToken _want = new MockToken(
            "Mock Want",
            "mWANT",
            _case.wantDecimals
        );
        MockConvertorOracle _oracle = new MockConvertorOracle();
        _oracle.setPrice(_case.oraclePrice);

        BaseConvertor _convertor = new BaseConvertor(
            address(_asset),
            "Decimal Pricing Convertor",
            address(_want),
            address(_oracle)
        );
        IStrategy _strategy = IStrategy(address(_convertor));
        _strategy.setKeeper(keeper);
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _strategy.setPendingManagement(management);

        vm.prank(management);
        _strategy.acceptManagement();

        vm.startPrank(management);
        _convertor.setMinAmountToSell(1);
        _convertor.setDoHealthCheck(false);
        _convertor.setStartingPriceBps(_case.startingBps);
        _convertor.setMaxSlippageBps(_case.maxSlippageBps);
        vm.stopPrank();

        (
            uint256 _expectedSellStart,
            uint256 _expectedSellMin
        ) = _expectedSellAuctionPricing(
                _case.assetAmount,
                _case.assetDecimals,
                _case.wantDecimals,
                _case.oraclePrice,
                _case.startingBps,
                _case.maxSlippageBps
            );
        (
            uint256 _expectedBuyStart,
            uint256 _expectedBuyMin
        ) = _expectedBuyAuctionPricing(
                _case.wantAmount,
                _case.assetDecimals,
                _case.wantDecimals,
                _case.oraclePrice,
                _case.startingBps,
                _case.maxSlippageBps
            );

        _asset.mint(address(_convertor), _case.assetAmount);
        vm.prank(keeper);
        _convertor.kickAuction(address(_asset));
        assertEq(
            _convertor.sellAssetAuction().startingPrice(),
            _expectedSellStart
        );
        assertEq(
            _convertor.sellAssetAuction().minimumPrice(),
            _expectedSellMin
        );

        _want.mint(address(_convertor), _case.wantAmount);
        vm.prank(keeper);
        _convertor.kickAuction(address(_want));
        assertEq(
            _convertor.buyAssetAuction().startingPrice(),
            _expectedBuyStart
        );
        assertEq(_convertor.buyAssetAuction().minimumPrice(), _expectedBuyMin);
    }

    function _expectedSellAuctionPricing(
        uint256 _amount,
        uint8 _assetDecimals,
        uint8 _wantDecimals,
        uint256 _oraclePrice,
        uint16 _startingBps,
        uint16 _maxSlippageBps
    ) internal pure returns (uint256 _startingPrice, uint256 _minimumPrice) {
        uint256 _target = _expectedTargetSellPrice(
            _assetDecimals,
            _wantDecimals,
            _oraclePrice
        );
        _startingPrice = _expectedStartingPrice(
            _amount,
            _assetDecimals,
            _target,
            _startingBps
        );
        _minimumPrice = _expectedMinimumPrice(_target, _maxSlippageBps);
    }

    function _expectedBuyAuctionPricing(
        uint256 _amount,
        uint8 _assetDecimals,
        uint8 _wantDecimals,
        uint256 _oraclePrice,
        uint16 _startingBps,
        uint16 _maxSlippageBps
    ) internal pure returns (uint256 _startingPrice, uint256 _minimumPrice) {
        uint256 _target = _expectedTargetBuyPrice(
            _assetDecimals,
            _wantDecimals,
            _oraclePrice
        );
        _startingPrice = _expectedStartingPrice(
            _amount,
            _wantDecimals,
            _target,
            _startingBps
        );
        _minimumPrice = _expectedMinimumPrice(_target, _maxSlippageBps);
    }

    function _expectedTargetSellPrice(
        uint8 _assetDecimals,
        uint8 _wantDecimals,
        uint256 _oraclePrice
    ) internal pure returns (uint256) {
        uint256 oneAsset = 10 ** _assetDecimals;
        uint256 quoteWant = Math.mulDiv(oneAsset, ORACLE_SCALE, _oraclePrice);
        return Math.mulDiv(quoteWant, 1e18, 10 ** _wantDecimals);
    }

    function _expectedTargetBuyPrice(
        uint8 _assetDecimals,
        uint8 _wantDecimals,
        uint256 _oraclePrice
    ) internal pure returns (uint256) {
        uint256 oneWant = 10 ** _wantDecimals;
        uint256 quoteAsset = Math.mulDiv(oneWant, _oraclePrice, ORACLE_SCALE);
        return Math.mulDiv(quoteAsset, 1e18, 10 ** _assetDecimals);
    }

    function _expectedStartingPrice(
        uint256 _amount,
        uint8 _fromDecimals,
        uint256 _targetPrice,
        uint16 _startingBps
    ) internal pure returns (uint256) {
        uint256 unitStartPrice = Math.mulDiv(
            _targetPrice,
            uint256(_startingBps),
            10_000,
            Math.Rounding.Up
        );
        uint256 _startingPrice = Math.mulDiv(
            _amount,
            unitStartPrice,
            (10 ** _fromDecimals) * 1e18,
            Math.Rounding.Up
        );
        return _startingPrice == 0 ? 1 : _startingPrice;
    }

    function _expectedMinimumPrice(
        uint256 _targetPrice,
        uint16 _maxSlippageBps
    ) internal pure returns (uint256) {
        return Math.mulDiv(_targetPrice, 10_000 - _maxSlippageBps, 10_000);
    }
}
