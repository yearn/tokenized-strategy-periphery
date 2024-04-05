// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {ITaker} from "../interfaces/ITaker.sol";
import {Auction, AuctionFactory} from "../Auctions/AuctionFactory.sol";

contract AuctionTest is Setup, ITaker {
    using SafeERC20 for ERC20;

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

    event Callback(
        bytes32 _auctionId,
        address _sender,
        uint256 _amountTaken,
        uint256 _amountNeeded,
        bytes _data
    );

    Auction public auction;
    AuctionFactory public auctionFactory;

    uint256 public wantScaler;
    uint256 public fromScaler;

    bool public callbackHit;

    function setUp() public override {
        super.setUp();

        auctionFactory = new AuctionFactory();
    }

    function test_setup() public {
        assertEq(auctionFactory.DEFAULT_AUCTION_COOLDOWN(), 5 days);
        assertEq(auctionFactory.DEFAULT_AUCTION_LENGTH(), 1 days);
        assertEq(auctionFactory.DEFAULT_STARTING_PRICE(), 1e6);
    }

    function test_defaults() public {
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        vm.expectRevert("initialized");
        auction.initialize(address(asset), address(0), management, 1, 10, 8);

        assertEq(auction.want(), address(asset));
        assertEq(auction.hook(), address(0));
        assertEq(auction.governance(), address(this));
        assertEq(
            auction.auctionLength(),
            auctionFactory.DEFAULT_AUCTION_LENGTH()
        );
        assertEq(
            auction.auctionCooldown(),
            auctionFactory.DEFAULT_AUCTION_COOLDOWN()
        );
        assertEq(
            auction.startingPrice(),
            auctionFactory.DEFAULT_STARTING_PRICE()
        );
    }

    function test_enableAuction() public {
        address from = tokenAddrs["USDC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        bytes32 expectedId = auction.getAuctionId(from);

        vm.expectRevert("!governance");
        vm.prank(management);
        auction.enable(from);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionEnabled(expectedId, from, address(asset), address(auction));

        bytes32 id = auction.enable(from);
        assertEq(id, expectedId);

        assertEq(auction.numberOfEnabledAuctions(), 1);
        assertEq(auction.enabledAuctions(0), expectedId);
        assertEq(auction.kickable(id), 0);
        assertEq(auction.getAmountNeeded(id, 1e18), 0);
        assertEq(auction.price(id), 0);

        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        (Auction.TokenInfo memory _token, , address _receiver, , ) = auction
            .auctions(id);
        assertEq(_token.tokenAddress, from);
        assertEq(_receiver, address(this));

        // Kicking it reverts
        vm.expectRevert("nothing to kick");
        auction.kick(id);

        // Can't re-enable
        vm.expectRevert("already enabled");
        auction.enable(from);

        vm.expectRevert("already enabled");
        auction.enable(from, management);
    }

    function test_disableAuction() public {
        address from = tokenAddrs["USDC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        vm.expectRevert("not enabled");
        auction.disable(from);

        bytes32 id = auction.enable(from);

        assertEq(auction.numberOfEnabledAuctions(), 1);

        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        vm.expectRevert("!governance");
        vm.prank(management);
        auction.disable(from);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionDisabled(id, from, address(asset), address(auction));
        auction.disable(from);

        assertEq(auction.numberOfEnabledAuctions(), 0);

        (_from, _to, _kicked, _available) = auction.auctionInfo(id);

        assertEq(_from, address(0));
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        (Auction.TokenInfo memory _token, , address _receiver, , ) = auction
            .auctions(id);
        assertEq(_token.tokenAddress, address(0));
        assertEq(_token.scaler, 0);
        assertEq(_receiver, address(0));
    }

    function test_kickAuction(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = auction.enable(from);

        assertEq(auction.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);

        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        airdrop(ERC20(from), address(auction), _amount);

        assertEq(auction.kickable(id), _amount);
        (, , _kicked, _available) = auction.auctionInfo(id);
        assertEq(_kicked, 0);
        assertEq(_available, 0);

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionKicked(id, _amount);
        uint256 available = auction.kick(id);

        assertEq(auction.kickable(id), 0);
        (, , _kicked, _available) = auction.auctionInfo(id);
        assertEq(_kicked, block.timestamp);
        assertEq(_available, _amount);
        uint256 startingPrice = ((auction.startingPrice() *
            (WAD / wantScaler)) * 1e18) /
            _amount /
            fromScaler;
        assertEq(auction.price(id), startingPrice);
        assertRelApproxEq(
            auction.getAmountNeeded(id, _amount),
            (startingPrice * fromScaler * _amount) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auction.price(id, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auction.getAmountNeeded(
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

        assertEq(auction.price(id), expectedPrice);
        assertEq(auction.getAmountNeeded(id, _amount), expectedAmount);

        // Skip full auction
        skip(auction.auctionLength());

        assertEq(auction.price(id), 0);
        assertEq(auction.getAmountNeeded(id, _amount), 0);

        // Can't kick a new one yet
        vm.expectRevert("too soon");
        auction.kick(id);

        assertEq(auction.kickable(id), 0);
    }

    function test_takeAuction_all(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = auction.enable(from, address(mockStrategy));

        airdrop(ERC20(from), address(auction), _amount);

        uint256 available = auction.kick(id);

        assertEq(auction.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);
        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, block.timestamp);
        assertEq(_available, _amount);

        skip(auction.auctionLength() / 2);

        uint256 needed = auction.getAmountNeeded(id, _amount);

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionTaken(id, _amount, 0);
        uint256 amountTaken = auction.take(id);

        assertEq(amountTaken, _amount);

        (, , , _available) = auction.auctionInfo(id);
        assertEq(_available, 0);

        assertEq(ERC20(asset).balanceOf(address(this)), 0);
        assertEq(ERC20(from).balanceOf(address(this)), before + _amount);
        assertEq(ERC20(from).balanceOf(address(auction)), 0);
        assertEq(ERC20(asset).balanceOf(address(mockStrategy)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
    }

    function test_takeAuction_part(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = auction.enable(from, address(mockStrategy));

        airdrop(ERC20(from), address(auction), _amount);

        auction.kick(id);

        assertEq(auction.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);
        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, block.timestamp);
        assertEq(_available, _amount);

        skip(auction.auctionLength() / 2);

        uint256 toTake = (_amount * _percent) / MAX_BPS;
        uint256 left = _amount - toTake;
        uint256 needed = auction.getAmountNeeded(id, toTake);

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        vm.expectEmit(true, true, true, true, address(auction));
        emit AuctionTaken(id, toTake, left);
        uint256 amountTaken = auction.take(id, toTake);

        assertEq(amountTaken, toTake);

        (, , , _available) = auction.auctionInfo(id);
        assertEq(_available, left);
        assertEq(ERC20(asset).balanceOf(address(this)), 0);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auction)), left);
        assertEq(ERC20(asset).balanceOf(address(mockStrategy)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
    }

    function test_takeAuction_callback(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];
        auction = Auction(auctionFactory.createNewAuction(address(asset)));

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        bytes32 id = auction.enable(from, address(mockStrategy));

        airdrop(ERC20(from), address(auction), _amount);

        auction.kick(id);

        assertEq(auction.kickable(id), 0);
        (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        ) = auction.auctionInfo(id);
        assertEq(_from, from);
        assertEq(_to, address(asset));
        assertEq(_kicked, block.timestamp);
        assertEq(_available, _amount);

        skip(auction.auctionLength() / 2);

        uint256 toTake = _amount / 2;
        uint256 left = _amount - toTake;
        uint256 needed = auction.getAmountNeeded(id, toTake);

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).safeApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        callbackHit = false;
        bytes memory _data = new bytes(69);

        vm.expectEmit(true, true, true, true, address(this));
        emit Callback(id, address(this), toTake, needed, _data);
        uint256 amountTaken = auction.take(id, toTake, address(this), _data);

        assertTrue(callbackHit);
        assertEq(amountTaken, toTake);

        (, , , _available) = auction.auctionInfo(id);
        assertEq(_available, left);
        assertEq(ERC20(asset).balanceOf(address(this)), 0);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auction)), left);
        assertEq(ERC20(asset).balanceOf(address(mockStrategy)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
    }

    // Taker call back function
    function auctionTakeCallback(
        bytes32 _auctionId,
        address _sender,
        uint256 _amountTaken,
        uint256 _amountNeeded,
        bytes memory _data
    ) external {
        callbackHit = true;
        emit Callback(_auctionId, _sender, _amountTaken, _amountNeeded, _data);
    }
}
