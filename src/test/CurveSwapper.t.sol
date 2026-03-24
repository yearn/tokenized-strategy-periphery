// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";

import {MockCurveSwapper} from "./mocks/MockCurveSwapper.sol";

contract CurveSwapperTest is Setup {
    MockCurveSwapper public curveSwapper;

    ERC20 public usdt;
    ERC20 public weth;
    ERC20 public dai;

    // Curve tricrypto2 pool: USDT(0), WBTC(1), WETH(2)
    address public constant TRICRYPTO2 =
        0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;

    // Curve 3pool: DAI(0), USDC(1), USDT(2)
    address public constant THREE_POOL =
        0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    uint256 public minWethAmount = 1e10;
    uint256 public maxWethAmount = 1e20;

    uint256 public minDaiAmount = 1e15;
    uint256 public maxDaiAmount = 1e23;

    function setUp() public override {
        super.setUp();

        usdt = ERC20(tokenAddrs["USDT"]);
        weth = ERC20(tokenAddrs["WETH"]);
        dai = ERC20(tokenAddrs["DAI"]);

        curveSwapper = new MockCurveSwapper();

        // Set up multi-hop routes: WETH <-> DAI via tricrypto2 + 3pool
        _setRouteWethToDai();
        _setRouteDaiToWeth();
    }

    // -----------------------------------------------------------------------
    // Multi-hop swap tests
    // -----------------------------------------------------------------------

    function test_swapFrom_wethToDai(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        airdrop(weth, address(curveSwapper), amount);

        assertEq(weth.balanceOf(address(curveSwapper)), amount);
        assertEq(dai.balanceOf(address(curveSwapper)), 0);
        assertEq(usdt.balanceOf(address(curveSwapper)), 0);

        uint256 amountOut = curveSwapper.swapFrom(
            address(weth),
            address(dai),
            amount,
            0
        );

        assertEq(weth.balanceOf(address(curveSwapper)), 0);
        // No intermediate USDT should remain
        assertEq(usdt.balanceOf(address(curveSwapper)), 0);
        assertGt(dai.balanceOf(address(curveSwapper)), 0);
        assertEq(dai.balanceOf(address(curveSwapper)), amountOut);
    }

    function test_swapFrom_daiToWeth(uint256 amount) public {
        vm.assume(amount >= minDaiAmount && amount <= maxDaiAmount);

        airdrop(dai, address(curveSwapper), amount);

        assertEq(dai.balanceOf(address(curveSwapper)), amount);
        assertEq(weth.balanceOf(address(curveSwapper)), 0);
        assertEq(usdt.balanceOf(address(curveSwapper)), 0);

        uint256 amountOut = curveSwapper.swapFrom(
            address(dai),
            address(weth),
            amount,
            0
        );

        assertEq(dai.balanceOf(address(curveSwapper)), 0);
        // No intermediate USDT should remain
        assertEq(usdt.balanceOf(address(curveSwapper)), 0);
        assertGt(weth.balanceOf(address(curveSwapper)), 0);
        assertEq(weth.balanceOf(address(curveSwapper)), amountOut);
    }

    // -----------------------------------------------------------------------
    // Slippage / revert tests
    // -----------------------------------------------------------------------

    function test_swapFrom_minOutReverts(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        airdrop(weth, address(curveSwapper), amount);

        // Unrealistic minOut — should revert
        uint256 minOut = amount * 1e18;

        vm.expectRevert();
        curveSwapper.swapFrom(address(weth), address(dai), amount, minOut);

        assertEq(weth.balanceOf(address(curveSwapper)), amount);
        assertEq(dai.balanceOf(address(curveSwapper)), 0);
    }

    function test_badRouter_reverts(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        curveSwapper.setRouter(management);
        assertEq(curveSwapper.curveRouter(), management);

        airdrop(weth, address(curveSwapper), amount);

        vm.expectRevert();
        curveSwapper.swapFrom(address(weth), address(dai), amount, 0);

        assertEq(weth.balanceOf(address(curveSwapper)), amount);
        assertEq(dai.balanceOf(address(curveSwapper)), 0);
    }

    function test_noRoute_reverts(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);

        ERC20 usdc = ERC20(tokenAddrs["USDC"]);

        airdrop(usdt, address(curveSwapper), amount);

        // No route set for USDT -> USDC
        vm.expectRevert();
        curveSwapper.swapFrom(address(usdt), address(usdc), amount, 0);

        assertEq(usdt.balanceOf(address(curveSwapper)), amount);
    }

    function test_zeroAmount_noSwap() public {
        uint256 amountOut = curveSwapper.swapFrom(
            address(weth),
            address(dai),
            0,
            0
        );

        assertEq(amountOut, 0);
    }

    function test_belowMinAmount_noSwap(uint256 amount) public {
        vm.assume(amount >= minWethAmount && amount <= maxWethAmount);

        // Set minAmountToSell above our swap amount
        curveSwapper.setMinAmountToSell(amount + 1);

        airdrop(weth, address(curveSwapper), amount);

        uint256 amountOut = curveSwapper.swapFrom(
            address(weth),
            address(dai),
            amount,
            0
        );

        assertEq(amountOut, 0);
        assertEq(weth.balanceOf(address(curveSwapper)), amount);
    }

    function test_setCurveRoute_badRoute_reverts() public {
        address[11] memory route;
        route[0] = address(weth); // Does NOT match _from = dai

        uint256[5][5] memory swapParams;
        address[5] memory pools;

        vm.expectRevert("!route");
        curveSwapper.setCurveRoute(
            address(dai),
            address(weth),
            route,
            swapParams,
            pools
        );
    }

    // -----------------------------------------------------------------------
    // Route helpers
    // -----------------------------------------------------------------------

    function _setRouteWethToDai() internal {
        // Multi-hop: WETH -> USDT (tricrypto2) -> DAI (3pool)
        address[11] memory route;
        route[0] = address(weth);
        route[1] = TRICRYPTO2;
        route[2] = address(usdt); // USDT (intermediate)
        route[3] = THREE_POOL;
        route[4] = address(dai);

        uint256[5][5] memory swapParams;
        // Hop 1: WETH(2) -> USDT(0) in tricrypto2 (crypto pool, 3 coins)
        swapParams[0] = [uint256(2), 0, 1, 2, 3];
        // Hop 2: USDT(2) -> DAI(0) in 3pool (stable pool, 3 coins)
        swapParams[1] = [uint256(2), 0, 1, 1, 3];

        address[5] memory pools;

        curveSwapper.setCurveRoute(
            address(weth),
            address(dai),
            route,
            swapParams,
            pools
        );
    }

    function _setRouteDaiToWeth() internal {
        // Multi-hop: DAI -> USDT (3pool) -> WETH (tricrypto2)
        address[11] memory route;
        route[0] = address(dai);
        route[1] = THREE_POOL;
        route[2] = address(usdt); // USDT (intermediate)
        route[3] = TRICRYPTO2;
        route[4] = address(weth);

        uint256[5][5] memory swapParams;
        // Hop 1: DAI(0) -> USDT(2) in 3pool (stable pool, 3 coins)
        swapParams[0] = [uint256(0), 2, 1, 1, 3];
        // Hop 2: USDT(0) -> WETH(2) in tricrypto2 (crypto pool, 3 coins)
        swapParams[1] = [uint256(0), 2, 1, 2, 3];

        address[5] memory pools;

        curveSwapper.setCurveRoute(
            address(dai),
            address(weth),
            route,
            swapParams,
            pools
        );
    }
}
