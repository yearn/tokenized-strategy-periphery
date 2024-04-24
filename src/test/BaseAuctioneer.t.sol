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

    event AuctionEnabled(
        bytes32 auctionId,
        address indexed from,
        address indexed to,
        address indexed strategy
    );

    event AuctionDisabled(
        bytes32 auctionId,
        address indexed from,
        address indexed to,
        address indexed strategy
    );

    event AuctionKicked(bytes32 auctionId, uint256 available);

    event AuctionTaken(
        bytes32 auctionId,
        uint256 amountTaken,
        uint256 amountLeft
    );

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

        bytes32 id = auctioneer.enableAuction(from);

        assertEq(auctioneer.kickable(id), 0);
        assertEq(auctioneer.getAmountNeeded(id, 1e18), 0);
        assertEq(auctioneer.price(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auctioneer.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        // Kicking it reverts
        vm.expectRevert("nothing to kick");
        auctioneer.kick(id);

        // Can't re-enable
        vm.expectRevert("already enabled");
        auctioneer.enableAuction(from);
    }

    function test_enableSecondAuction() public {
        address from = tokenAddrs["USDC"];

        bytes32 id = auctioneer.enableAuction(from);

        assertEq(auctioneer.kickable(id), 0);
        assertEq(auctioneer.getAmountNeeded(id, 1e18), 0);
        assertEq(auctioneer.price(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auctioneer.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        address secondFrom = tokenAddrs["WETH"];

        bytes32 expectedId = auctioneer.getAuctionId(secondFrom);

        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit AuctionEnabled(
            expectedId,
            secondFrom,
            address(asset),
            address(auctioneer)
        );
        bytes32 secondId = auctioneer.enableAuction(secondFrom);

        assertEq(expectedId, secondId);
        assertEq(auctioneer.kickable(secondId), 0);
        assertEq(auctioneer.getAmountNeeded(secondId, 1e18), 0);
        assertEq(auctioneer.price(secondId), 0);
        (_from, _to, _kicked, _available) = auctioneer.auctionInfo(secondId);

        assertEq(_from, secondFrom);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);
    }

    function test_disableAuction() public {
        address from = tokenAddrs["USDC"];

        bytes32 id = auctioneer.enableAuction(from);

        assertEq(auctioneer.kickable(id), 0);
        assertEq(auctioneer.getAmountNeeded(id, 1e18), 0);
        assertEq(auctioneer.price(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auctioneer.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit AuctionDisabled(id, from, address(asset), address(auctioneer));
        auctioneer.disableAuction(from);

        (_from, _to, _kicked, _available) = auctioneer.auctionInfo(id);

        assertEq(_from, address(0));
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);
    }

    function test_kickAuction_default(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = auctioneer.enableAuction(from);

        assertEq(auctioneer.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auctioneer.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        airdrop(ERC20(from), address(auctioneer), _amount);

        assertEq(auctioneer.kickable(id), _amount);
        (, , _kicked, _available) = auctioneer.auctionInfo(id);
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit AuctionKicked(id, _amount);
        uint256 available = auctioneer.kick(id);

        assertEq(ERC20(from).balanceOf(address(auctioneer)), _amount);
        assertEq(ERC20(from).balanceOf(address(auctioneer)), available);

        assertEq(auctioneer.kickable(id), 0);
        (, , _kicked, _available) = auctioneer.auctionInfo(id);
        assertEq(_kicked, block.timestamp);
        assertEq(_available, _amount);
        uint256 startingPrice = ((auctioneer.auctionStartingPrice() *
            (WAD / wantScaler)) * 1e18) /
            _amount /
            fromScaler;
        assertEq(auctioneer.price(id), startingPrice);
        assertRelApproxEq(
            auctioneer.getAmountNeeded(id, _amount),
            (startingPrice * fromScaler * _amount) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auctioneer.price(id, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auctioneer.getAmountNeeded(
            id,
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

        assertEq(auctioneer.price(id), expectedPrice);
        assertEq(auctioneer.getAmountNeeded(id, _amount), expectedAmount);

        // Skip full auction
        skip(auctioneer.auctionLength());

        assertEq(auctioneer.price(id), 0);
        assertEq(auctioneer.getAmountNeeded(id, _amount), 0);

        // Can't kick a new one yet
        vm.expectRevert("too soon");
        auctioneer.kick(id);

        assertEq(auctioneer.kickable(id), 0);
    }

    function test_takeAuction_default(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = auctioneer.enableAuction(from);

        airdrop(ERC20(from), address(auctioneer), _amount);

        auctioneer.kick(id);

        assertEq(auctioneer.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auctioneer.auctionInfo(id);
        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, block.timestamp);
        assertEq(_available, _amount);
        assertEq(ERC20(from).balanceOf(address(auctioneer)), _amount);

        skip(auctioneer.auctionLength() / 2);

        uint256 toTake = (_amount * _percent) / MAX_BPS;
        uint256 left = _amount - toTake;
        uint256 needed = auctioneer.getAmountNeeded(id, toTake);

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auctioneer), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit AuctionTaken(id, toTake, left);
        uint256 amountTaken = auctioneer.take(id, toTake);

        assertEq(amountTaken, toTake);

        (, , , _available) = auctioneer.auctionInfo(id);
        assertEq(_available, left);
        assertEq(ERC20(asset).balanceOf(address(this)), 0);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auctioneer)), left);
        assertEq(ERC20(asset).balanceOf(address(auctioneer)), needed);
    }

    function test_kickAuction_custom(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = auctioneer.enableAuction(from);

        assertEq(auctioneer.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auctioneer.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        airdrop(ERC20(from), address(auctioneer), _amount);

        auctioneer.setUseDefault(false);

        assertEq(auctioneer.kickable(id), 0);

        uint256 kickable = _amount / 10;
        auctioneer.setLetKick(kickable);

        assertEq(auctioneer.kickable(id), kickable);
        (, , _kicked, _available) = auctioneer.auctionInfo(id);
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit AuctionKicked(id, kickable);
        uint256 available = auctioneer.kick(id);

        assertEq(ERC20(from).balanceOf(address(auctioneer)), _amount);
        assertEq(kickable, available);

        assertEq(auctioneer.kickable(id), 0);
        (, , _kicked, _available) = auctioneer.auctionInfo(id);
        assertEq(_kicked, block.timestamp);
        assertEq(_available, kickable);
        uint256 startingPrice = ((auctioneer.auctionStartingPrice() *
            (WAD / wantScaler)) * 1e18) /
            kickable /
            fromScaler;
        assertEq(auctioneer.price(id), startingPrice);
        assertRelApproxEq(
            auctioneer.getAmountNeeded(id, kickable),
            (startingPrice * fromScaler * kickable) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auctioneer.price(id, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auctioneer.getAmountNeeded(
            id,
            kickable,
            block.timestamp + 100
        );
        assertLt(
            expectedAmount,
            (startingPrice * fromScaler * kickable) /
                (WAD / wantScaler) /
                wantScaler
        );

        skip(100);

        assertEq(auctioneer.price(id), expectedPrice);
        assertEq(auctioneer.getAmountNeeded(id, kickable), expectedAmount);

        // Skip full auction
        skip(auctioneer.auctionLength());

        assertEq(auctioneer.price(id), 0);
        assertEq(auctioneer.getAmountNeeded(id, kickable), 0);

        // Can't kick a new one yet
        vm.expectRevert("too soon");
        auctioneer.kick(id);

        assertEq(auctioneer.kickable(id), 0);
    }

    function test_takeAuction_custom(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = auctioneer.enableAuction(from);

        airdrop(ERC20(from), address(auctioneer), _amount);

        auctioneer.setUseDefault(false);

        assertEq(auctioneer.kickable(id), 0);

        uint256 kickable = _amount / 10;
        auctioneer.setLetKick(kickable);

        auctioneer.kick(id);

        assertEq(auctioneer.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auctioneer.auctionInfo(id);
        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, block.timestamp);
        assertEq(_available, kickable);
        assertEq(ERC20(from).balanceOf(address(auctioneer)), _amount);

        skip(auctioneer.auctionLength() / 2);

        uint256 toTake = (kickable * _percent) / MAX_BPS;
        uint256 left = _amount - toTake;
        uint256 needed = auctioneer.getAmountNeeded(id, toTake);

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auctioneer), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit PreTake(from, toTake, needed);
        vm.expectEmit(true, true, true, true, address(auctioneer));
        emit PostTake(address(asset), toTake, needed);
        uint256 amountTaken = auctioneer.take(id, toTake);

        assertEq(amountTaken, toTake);

        (, , , _available) = auctioneer.auctionInfo(id);
        assertEq(_available, kickable - toTake);
        assertEq(ERC20(asset).balanceOf(address(this)), 0);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auctioneer)), left);
        assertEq(ERC20(asset).balanceOf(address(auctioneer)), needed);
    }
}
