// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {IMockAuctionSwapper, MockAuctionSwapper} from "./mocks/MockAuctionSwapper.sol";
import {Auction, AuctionFactory} from "../Auctions/AuctionFactory.sol";

contract AuctionSwapperTest is Setup {
    using SafeERC20 for ERC20;

    event AuctionSet(address indexed auction);
    event UseAuctionSet(bool indexed useAuction);

    IMockAuctionSwapper public swapper;

    Auction public auction;
    AuctionFactory public auctionFactory =
        AuctionFactory(0xCfA510188884F199fcC6e750764FAAbE6e56ec40);

    uint256 public wantScaler;
    uint256 public fromScaler;

    function setUp() public override {
        super.setUp();

        swapper = IMockAuctionSwapper(
            address(new MockAuctionSwapper(address(asset)))
        );

        vm.label(address(auctionFactory), "Auction Factory ");
        vm.label(address(swapper), "Auction Swapper");
    }

    function test_setAuction() public {
        assertEq(swapper.auction(), address(0));
        assertFalse(swapper.useAuction());

        // Create a new auction for testing
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );

        // Setting auction should emit event
        vm.expectEmit(true, false, false, false);
        emit AuctionSet(newAuction);
        swapper.setAuction(newAuction);

        assertEq(swapper.auction(), newAuction);
        assertFalse(swapper.useAuction());
        
        // Auction is set but useAuction is false, so kickable should be 0
        address from = tokenAddrs["USDC"];
        assertEq(swapper.kickable(from), 0);
        
        // Enable an auction for the token
        auction = Auction(newAuction);
        auction.enable(from);
        
        // Still 0 because useAuction is false
        assertEq(swapper.kickable(from), 0);
    }

    function test_setUseAuction() public {
        address from = tokenAddrs["USDC"];
        
        // Create and set auction
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );
        
        swapper.setAuction(newAuction);
        auction = Auction(newAuction);
        auction.enable(from);
        
        assertFalse(swapper.useAuction());
        assertEq(swapper.kickable(from), 0);
        
        // Set useAuction to true should emit event
        vm.expectEmit(true, false, false, false);
        emit UseAuctionSet(true);
        swapper.setUseAuction(true);
        
        assertTrue(swapper.useAuction());
        assertEq(swapper.kickable(from), 0); // Still 0 because no balance
        
        // Add some balance
        airdrop(ERC20(from), address(swapper), 1000e6);
        assertEq(swapper.kickable(from), 1000e6);
        
        // Set useAuction to false
        vm.expectEmit(true, false, false, false);
        emit UseAuctionSet(false);
        swapper.setUseAuction(false);
        
        assertFalse(swapper.useAuction());
        assertEq(swapper.kickable(from), 0); // Back to 0
    }

    function test_setAuction_wrongReceiver() public {
        // Create auction with wrong receiver
        address wrongAuction = auctionFactory.createNewAuction(
            address(asset),
            address(this), // Wrong receiver (should be swapper)
            address(this),
            1 days,
            1e6
        );
        
        vm.expectRevert("wrong receiver");
        swapper.setAuction(wrongAuction);
    }

    function test_kickAuction_withUseAuction_false() public {
        address from = tokenAddrs["WBTC"];
        
        // Setup auction
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );
        swapper.setAuction(newAuction);
        auction = Auction(newAuction);
        auction.enable(from);
        
        // Add funds but don't enable useAuction
        airdrop(ERC20(from), address(swapper), 1e8);
        
        vm.expectRevert("useAuction is false");
        swapper.kickAuction(from);
    }
    
    function test_kickAuction_default(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        // Setup auction properly
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );
        swapper.setAuction(newAuction);
        swapper.setUseAuction(true);
        auction = Auction(newAuction);
        auction.enable(from);

        assertEq(swapper.kickable(from), 0);
        assertEq(auction.kickable(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, fromScaler);
        assertEq(_initialAvailable, 0);

        airdrop(ERC20(from), address(swapper), _amount);

        assertEq(swapper.kickable(from), _amount);
        assertEq(auction.kickable(from), 0);
        (_kicked, , _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, 0);
        assertEq(_initialAvailable, 0);

        swapper.kickAuction(from);

        assertEq(ERC20(from).balanceOf(address(swapper)), 0);
        assertEq(ERC20(from).balanceOf(address(auction)), _amount);

        assertEq(swapper.kickable(from), _amount); // Now includes auction balance
        assertEq(auction.kickable(from), 0);
        (_kicked, , _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_initialAvailable, _amount);
        uint256 startingPrice = ((auction.startingPrice() *
            (WAD / wantScaler)) * 1e18) /
            _amount /
            fromScaler;
        assertEq(auction.price(from), startingPrice);
        assertRelApproxEq(
            auction.getAmountNeeded(from, _amount),
            (startingPrice * fromScaler * _amount) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auction.price(from, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auction.getAmountNeeded(
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

        assertEq(auction.price(from), expectedPrice);
        assertEq(auction.getAmountNeeded(from, _amount), expectedAmount);

        // Skip full auction
        skip(auction.auctionLength());

        assertEq(auction.price(from), 0);
        assertEq(auction.getAmountNeeded(from, _amount), 0);
    }

    function test_takeAuction_default(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        // Setup auction properly
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );
        swapper.setAuction(newAuction);
        swapper.setUseAuction(true);
        auction = Auction(newAuction);
        auction.enable(from);

        airdrop(ERC20(from), address(swapper), _amount);

        swapper.kickAuction(from);

        assertEq(swapper.kickable(from), _amount); // Now includes auction balance
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_scaler, fromScaler);
        assertEq(_initialAvailable, _amount);
        assertEq(ERC20(from).balanceOf(address(swapper)), 0);
        assertEq(ERC20(from).balanceOf(address(auction)), _amount);

        skip(auction.auctionLength() / 2);

        uint256 toTake = (_amount * _percent) / MAX_BPS;
        uint256 left = _amount - toTake;
        uint256 needed = auction.getAmountNeeded(from, toTake);
        uint256 beforeAsset = ERC20(asset).balanceOf(address(this));

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).forceApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        uint256 amountTaken = auction.take(from, toTake);

        assertEq(amountTaken, toTake);

        (_kicked, , _initialAvailable) = auction.auctions(from);
        assertEq(_initialAvailable, _amount);
        assertEq(auction.available(from), left);
        assertEq(ERC20(asset).balanceOf(address(this)), beforeAsset);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auction)), left);
        assertEq(ERC20(asset).balanceOf(address(swapper)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
        assertEq(ERC20(from).balanceOf(address(swapper)), 0);
    }

    function test_kickAuction_custom(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        // Setup auction properly
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );
        swapper.setAuction(newAuction);
        swapper.setUseAuction(true);
        auction = Auction(newAuction);
        auction.enable(from);

        assertEq(swapper.kickable(from), 0);
        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, 0);
        assertEq(_scaler, fromScaler);
        assertEq(_initialAvailable, 0);

        airdrop(ERC20(from), address(swapper), _amount);

        swapper.setUseDefault(false);

        assertEq(swapper.kickable(from), 0);

        uint256 kickable = _amount / 10;
        swapper.setLetKick(kickable);

        assertEq(swapper.kickable(from), kickable);
        (_kicked, , _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, 0);
        assertEq(_initialAvailable, 0);

        swapper.kickAuction(from);

        assertEq(ERC20(from).balanceOf(address(swapper)), _amount - kickable);
        assertEq(ERC20(from).balanceOf(address(auction)), kickable);

        (_kicked, , _initialAvailable) = auction.auctions(from);
        assertEq(_kicked, block.timestamp);
        assertEq(_initialAvailable, kickable);
        uint256 startingPrice = ((auction.startingPrice() *
            (WAD / wantScaler)) * 1e18) /
            kickable /
            fromScaler;
        assertEq(auction.price(from), startingPrice);
        assertRelApproxEq(
            auction.getAmountNeeded(from, kickable),
            (startingPrice * fromScaler * kickable) /
                (WAD / wantScaler) /
                wantScaler,
            MAX_BPS
        );

        uint256 expectedPrice = auction.price(from, block.timestamp + 100);
        assertLt(expectedPrice, startingPrice);
        uint256 expectedAmount = auction.getAmountNeeded(
            from,
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

        assertEq(auction.price(from), expectedPrice);
        assertEq(auction.getAmountNeeded(from, kickable), expectedAmount);

        // Skip full auction
        skip(auction.auctionLength());

        assertEq(auction.price(from), 0);
        assertEq(auction.getAmountNeeded(from, kickable), 0);
    }

    function test_takeAuction_custom(uint256 _amount, uint16 _percent) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);
        _percent = uint16(bound(uint256(_percent), 1_000, MAX_BPS));

        address from = tokenAddrs["WBTC"];

        fromScaler = WAD / 10 ** ERC20(from).decimals();
        wantScaler = WAD / 10 ** ERC20(asset).decimals();

        // Setup auction properly
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );
        swapper.setAuction(newAuction);
        swapper.setUseAuction(true);
        auction = Auction(newAuction);
        auction.enable(from);

        airdrop(ERC20(from), address(swapper), _amount);

        swapper.setUseDefault(false);

        assertEq(swapper.kickable(from), 0);

        uint256 kickable = _amount / 10;
        swapper.setLetKick(kickable);

        swapper.kickAuction(from);

        (uint64 _kicked, uint64 _scaler, uint128 _initialAvailable) = auction
            .auctions(from);

        assertEq(_kicked, block.timestamp);
        assertEq(_scaler, fromScaler);
        assertEq(_initialAvailable, kickable);
        assertEq(ERC20(from).balanceOf(address(swapper)), _amount - kickable);
        assertEq(ERC20(from).balanceOf(address(auction)), kickable);

        skip(auction.auctionLength() / 2);

        uint256 toTake = (kickable * _percent) / MAX_BPS;
        uint256 left = kickable - toTake;
        uint256 needed = auction.getAmountNeeded(from, toTake);
        uint256 beforeAsset = ERC20(asset).balanceOf(address(this));

        airdrop(ERC20(asset), address(this), needed);

        ERC20(asset).forceApprove(address(auction), needed);

        uint256 before = ERC20(from).balanceOf(address(this));

        uint256 amountTaken = auction.take(from, toTake);

        assertEq(amountTaken, toTake);

        (_kicked, , _initialAvailable) = auction.auctions(from);
        assertEq(_initialAvailable, kickable);
        assertEq(auction.available(from), left);
        assertEq(ERC20(asset).balanceOf(address(this)), beforeAsset);
        assertEq(ERC20(from).balanceOf(address(this)), before + toTake);
        assertEq(ERC20(from).balanceOf(address(auction)), left);
        assertEq(ERC20(asset).balanceOf(address(swapper)), needed);
        assertEq(ERC20(asset).balanceOf(address(auction)), 0);
    }
    
    function test_kickAuction_activeAuction_withAvailable() public {
        address from = tokenAddrs["WBTC"];
        
        // Setup auction
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );
        swapper.setAuction(newAuction);
        swapper.setUseAuction(true);
        auction = Auction(newAuction);
        auction.enable(from);
        
        airdrop(ERC20(from), address(swapper), 1e8);
        
        // Kick the first auction
        uint256 kicked = swapper.kickAuction(from);
        assertTrue(kicked > 0);
        assertTrue(Auction(auction).isActive(from));
        assertTrue(Auction(auction).available(from) > 0);
        
        // Add more tokens
        airdrop(ERC20(from), address(swapper), 1e8);
        
        // Trying to kick again should return 0 since auction is active and has available tokens
        uint256 kicked2 = swapper.kickAuction(from);
        assertEq(kicked2, 0);
    }
    
    function test_kickAuction_activeAuction_noAvailable() public {
        address from = tokenAddrs["WBTC"];
        
        // Setup auction
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );
        swapper.setAuction(newAuction);
        swapper.setUseAuction(true);
        auction = Auction(newAuction);
        auction.enable(from);
        
        uint256 amount = 1e8;
        airdrop(ERC20(from), address(swapper), amount);
        
        // Kick the first auction
        swapper.kickAuction(from);
        assertTrue(Auction(auction).isActive(from));
        
        // Take the entire auction
        skip(auction.auctionLength() / 2);
        uint256 needed = auction.getAmountNeeded(from, amount);
        airdrop(ERC20(asset), address(this), needed);
        ERC20(asset).forceApprove(address(auction), needed);
        auction.take(from, amount);
        
        // Now available should be 0
        assertEq(Auction(auction).available(from), 0);
        
        // Add more tokens and try to kick again - should settle and start new auction
        airdrop(ERC20(from), address(swapper), amount);
        uint256 kicked = swapper.kickAuction(from);
        assertTrue(kicked > 0);
        assertEq(ERC20(from).balanceOf(address(auction)), amount);
    }
    
    function test_kickAuction_noBalance() public {
        address from = tokenAddrs["WBTC"];
        
        // Setup auction
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1 days,
            1e6
        );
        swapper.setAuction(newAuction);
        swapper.setUseAuction(true);
        auction = Auction(newAuction);
        auction.enable(from);
        
        // No balance - should revert with "nothing to kick"
        vm.expectRevert("nothing to kick");
        swapper.kickAuction(from);
    }
}
