// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {IMockAuctioneer, MockAuctioneer} from "./mocks/MockAuctioneer.sol";

contract BaseAuctioneerTest is Setup {
    using SafeERC20 for ERC20;

    event PreTake(address token, uint256 amountToTake, uint256 amountToPay);
    event PostTake(address token, uint256 amountTaken, uint256 amountPayed);

    event DeployedNewAuction(address indexed auction, address indexed want);

    event AuctionEnabled(address indexed from, address indexed to);

    event AuctionDisabled(address indexed from, address indexed to);

    event AuctionKicked(address indexed from, uint256 available);

    IMockAuctioneer public auctioneer;

    uint256 public wantScaler;
    uint256 public fromScaler;

    function setUp() public override {
        super.setUp();

        auctioneer = IMockAuctioneer(
            address(new MockAuctioneer(address(asset)))
        );

        vm.label(address(auctioneer), "Auctioneer");
    }

    function test_enableAuction() public {
        address from = tokenAddrs["USDC"];

        auctioneer.enable(from);

        assertEq(auctioneer.kickable(from), 0);
        assertEq(auctioneer.getAmountNeeded(from, 1e18), 0);
        assertEq(auctioneer.price(from), 0);

        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auctioneer
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e12);
        assertEq(_initialAvailable, 0);
        assertEq(auctioneer.available(from), 0);

        // Kicking it reverts
        vm.expectRevert("nothing to kick");
        auctioneer.kick(from);

        // Can't re-enable
        vm.expectRevert("already enabled");
        auctioneer.enable(from);
    }

    function test_enableSecondAuction() public {
        address from = tokenAddrs["USDC"];

        auctioneer.enable(from);

        assertEq(auctioneer.kickable(from), 0);
        assertEq(auctioneer.getAmountNeeded(from, 1e18), 0);
        assertEq(auctioneer.price(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auctioneer
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e12);
        assertEq(_initialAvailable, 0);
        assertEq(auctioneer.available(from), 0);

        address secondFrom = tokenAddrs["WETH"];

        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit AuctionEnabled(secondFrom, address(asset));
        auctioneer.enable(secondFrom);

        assertEq(auctioneer.kickable(secondFrom), 0);
        assertEq(auctioneer.getAmountNeeded(secondFrom, 1e18), 0);
        assertEq(auctioneer.price(secondFrom), 0);
        (_kicked, _scaler, _initialAvailable) = auctioneer.auctions(secondFrom);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1);
        assertEq(_initialAvailable, 0);
        assertEq(auctioneer.available(secondFrom), 0);
    }

    function test_disableAuction() public {
        address from = tokenAddrs["USDC"];

        auctioneer.enable(from);

        assertEq(auctioneer.kickable(from), 0);
        assertEq(auctioneer.getAmountNeeded(from, 1e18), 0);
        assertEq(auctioneer.price(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auctioneer
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e12);
        assertEq(_initialAvailable, 0);
        assertEq(auctioneer.available(from), 0);

        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit AuctionDisabled(from, address(asset));
        auctioneer.disable(from);

        (_kicked, _scaler, _initialAvailable) = auctioneer.auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 0);
        assertEq(_initialAvailable, 0);
        assertEq(auctioneer.available(from), 0);
    }

    function test_kickAuction_default(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        auctioneer.enable(from);

        assertEq(auctioneer.kickable(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auctioneer
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, 1e10);
        assertEq(_initialAvailable, 0);
        assertEq(auctioneer.available(from), 0);

        airdrop(ERC20(from), address(auctioneer), _amount);

        assertEq(auctioneer.kickable(from), _amount);
        (_kicked, , _initialAvailable) = auctioneer.auctions(from);
        assertEq(_kicked, 0);
        assertEq(_initialAvailable, 0);

        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit AuctionKicked(from, _amount);
        uint256 available = auctioneer.kick(from);

        assertEq(ERC20(from).balanceOf(address(auctioneer)), _amount);
        assertEq(ERC20(from).balanceOf(address(auctioneer)), available);

        assertEq(auctioneer.kickable(from), 0);
        (_kicked, , _initialAvailable) = auctioneer.auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_initialAvailable, _amount);
        uint256 startingPrice = ((auctioneer.startingPrice() *
            (WAD / wantScaler)) * 1e18) /
            _amount /
            fromScaler;
        assertEq(auctioneer.price(from), startingPrice);
        assertRelApproxEq(
            auctioneer.getAmountNeeded(from, _amount),
            (startingPrice * fromScaler * _amount) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auctioneer.price(from, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auctioneer.getAmountNeeded(
            from,
            _amount,
            block.timestamp + 100
        );
        assertLt(
            expectedAmount,
            (startingPrice * fromScaler * _amount) /
                (WAD / wantScaler) /
                wantScaler
        );

        skip(100);

        assertEq(auctioneer.price(from), expectedPrice);
        assertEq(auctioneer.getAmountNeeded(from, _amount), expectedAmount);

        // Skip full auction
        skip(auctioneer.auctionLength());

        assertEq(auctioneer.price(from), 0);
        assertEq(auctioneer.getAmountNeeded(from, _amount), 0);
    }

    function test_takeAuction_default(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        auctioneer.enable(from);

        airdrop(ERC20(from), address(auctioneer), _amount);

        auctioneer.kick(from);

        assertEq(auctioneer.kickable(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auctioneer
            .auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_scaler, 1e10);
        assertEq(_initialAvailable, _amount);
        assertEq(ERC20(from).balanceOf(address(auctioneer)), _amount);

        skip(auctioneer.auctionLength() / 2);

        uint256 toTake = (_amount * _percent) / MAX_BPS;
        uint256 left = _amount - toTake;
        uint256 needed = auctioneer.getAmountNeeded(from, toTake);
        uint256 beforeAsset = ERC20(asset).balanceOf(address(this));

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auctioneer), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        uint256 amountTaken = auctioneer.take(from, toTake);

        assertEq(amountTaken, toTake);

        (, , _initialAvailable) = auctioneer.auctions(from);
        assertEq(_initialAvailable, _amount);
        assertEq(auctioneer.available(from), left);
        assertEq(ERC20(asset).balanceOf(address(this)), beforeAsset);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auctioneer)), left);
        assertEq(ERC20(asset).balanceOf(address(auctioneer)), needed);
    }
}
