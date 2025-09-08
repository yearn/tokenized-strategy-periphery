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
    AuctionFactory public auctionFactory;

    uint256 public wantScaler;
    uint256 public fromScaler;

    function setUp() public override {
        super.setUp();

        auctionFactory = new AuctionFactory();

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
            1e6
        );

        // Setting auction should emit both events (AuctionSet and UseAuctionSet)
        vm.expectEmit(true, false, false, false);
        emit UseAuctionSet(true);
        vm.expectEmit(true, false, false, false);
        emit AuctionSet(newAuction);
        swapper.setAuction(newAuction);

        assertEq(swapper.auction(), newAuction);
        assertTrue(swapper.useAuction()); // Now should be true

        // Should be 0 because no balance yet
        address from = tokenAddrs["USDC"];
        assertEq(swapper.kickable(from), 0);

        // Enable an auction for the token
        auction = Auction(newAuction);
        auction.enable(from);

        // Add some balance
        airdrop(ERC20(from), address(swapper), 1000e6);
        assertEq(swapper.kickable(from), 1000e6);
    }

    function test_setUseAuction() public {
        address from = tokenAddrs["USDC"];

        // Create and set auction
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1e6
        );

        swapper.setAuction(newAuction);
        auction = Auction(newAuction);
        auction.enable(from);

        // Setting auction should now automatically enable useAuction
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

        // Set useAuction back to true
        vm.expectEmit(true, false, false, false);
        emit UseAuctionSet(true);
        swapper.setUseAuction(true);

        assertTrue(swapper.useAuction());
        assertEq(swapper.kickable(from), 1000e6); // Should work again
    }

    function test_setAuction_autoEnablesBehavior() public {
        // Initially should have no auction and useAuction false
        assertEq(swapper.auction(), address(0));
        assertFalse(swapper.useAuction());

        // Create first auction
        address auction1 = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1e6
        );

        // Setting first auction should auto-enable useAuction
        vm.expectEmit(true, false, false, false);
        emit UseAuctionSet(true);
        vm.expectEmit(true, false, false, false);
        emit AuctionSet(auction1);
        swapper.setAuction(auction1);

        assertTrue(swapper.useAuction());
        assertEq(swapper.auction(), auction1);

        skip(1); // Get different salt

        // Create second auction
        address auction2 = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            2e6
        );

        // Setting second auction when useAuction is already true should NOT emit UseAuctionSet
        vm.expectEmit(true, false, false, false);
        emit AuctionSet(auction2);
        // Should NOT emit UseAuctionSet since it's already true
        swapper.setAuction(auction2);

        assertTrue(swapper.useAuction()); // Still true
        assertEq(swapper.auction(), auction2);

        // Disable auctions
        swapper.setUseAuction(false);
        assertFalse(swapper.useAuction());

        // Setting the same auction again should re-enable useAuction
        vm.expectEmit(true, false, false, false);
        emit UseAuctionSet(true);
        vm.expectEmit(true, false, false, false);
        emit AuctionSet(auction2);
        swapper.setAuction(auction2);

        assertTrue(swapper.useAuction());

        // Setting to zero address should not auto-enable
        swapper.setUseAuction(false);
        vm.expectEmit(true, false, false, false);
        emit AuctionSet(address(0));
        // Should NOT emit UseAuctionSet
        swapper.setAuction(address(0));

        assertFalse(swapper.useAuction()); // Should remain false
        assertEq(swapper.auction(), address(0));
    }

    function test_setAuction_wrongReceiver() public {
        // Create auction with wrong receiver
        address wrongAuction = auctionFactory.createNewAuction(
            address(asset),
            address(this), // Wrong receiver (should be swapper)
            address(this),
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
            1e6
        );
        swapper.setAuction(newAuction);
        auction = Auction(newAuction);
        auction.enable(from);

        // Explicitly disable useAuction after setting auction
        swapper.setUseAuction(false);

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

        assertEq(swapper.kickable(from), 0); // Returns 0 when auction is active with available tokens
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
            1e6
        );
        swapper.setAuction(newAuction);
        swapper.setUseAuction(true);
        auction = Auction(newAuction);
        auction.enable(from);

        airdrop(ERC20(from), address(swapper), _amount);

        swapper.kickAuction(from);

        assertEq(swapper.kickable(from), 0); // Returns 0 when auction is active with available tokens
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
            1e6
        );
        swapper.setAuction(newAuction);
        auction = Auction(newAuction);
        auction.enable(from);

        uint256 amount = 1e8;
        airdrop(ERC20(from), address(swapper), amount);

        // Kick the first auction
        swapper.kickAuction(from);
        assertTrue(Auction(auction).isActive(from));

        // Take the entire auction
        console.log("auctionLength", auction.auctionLength());
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

    function test_auctionTrigger() public {
        address from = tokenAddrs["WBTC"];

        // Test with no auction set
        (bool shouldKick, bytes memory data) = swapper.auctionTrigger(from);
        assertFalse(shouldKick);
        assertEq(data, bytes("No auction set"));

        // Setup auction
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1e6
        );
        swapper.setAuction(newAuction);
        auction = Auction(newAuction);
        auction.enable(from);

        // Setting auction automatically enables auctions, so disable them for this test
        swapper.setUseAuction(false);

        // Test with auctions disabled
        (shouldKick, data) = swapper.auctionTrigger(from);
        assertFalse(shouldKick);
        assertEq(data, bytes("Auctions disabled"));

        // Enable auctions
        swapper.setUseAuction(true);

        // Test with no balance
        (shouldKick, data) = swapper.auctionTrigger(from);
        assertFalse(shouldKick);
        assertEq(data, bytes("not enough kickable"));

        // Add sufficient balance for testing
        airdrop(ERC20(from), address(swapper), 1e8);

        // Should kick since we have sufficient balance
        (shouldKick, data) = swapper.auctionTrigger(from);
        assertTrue(shouldKick);
        bytes memory expectedData = abi.encodeCall(swapper.kickAuction, (from));
        assertEq(data, expectedData);

        // Set minAmountToSell to test the threshold
        swapper.setMinAmountToSell(2e8); // Set higher than our balance

        // Should not kick due to insufficient amount
        (shouldKick, data) = swapper.auctionTrigger(from);
        assertFalse(shouldKick);
        assertEq(data, bytes("not enough kickable"));

        // Reset minAmountToSell to 0 and kick the auction
        swapper.setMinAmountToSell(0);
        swapper.kickAuction(from);

        // Should not kick again while active with available tokens (kickable returns 0)
        (shouldKick, data) = swapper.auctionTrigger(from);
        assertFalse(shouldKick);
        assertEq(data, bytes("not enough kickable"));

        // Take the entire auction to make it settleable
        skip(auction.auctionLength() / 2);
        uint256 needed = auction.getAmountNeeded(from, 1e8);
        airdrop(ERC20(address(asset)), address(this), needed);
        ERC20(address(asset)).forceApprove(address(auction), needed);
        auction.take(from, 1e8);

        // Add more balance and should be ready to kick again
        airdrop(ERC20(from), address(swapper), 5e7);
        (shouldKick, data) = swapper.auctionTrigger(from);
        assertTrue(shouldKick);
        expectedData = abi.encodeCall(swapper.kickAuction, (from));
        assertEq(data, expectedData);
    }

    function test_auctionTrigger_minAmountToSell() public {
        address from = tokenAddrs["WBTC"];

        // Setup auction
        address newAuction = auctionFactory.createNewAuction(
            address(asset),
            address(swapper),
            address(this),
            1e6
        );
        swapper.setAuction(newAuction);
        auction = Auction(newAuction);
        auction.enable(from);

        // Start with sufficient balance
        airdrop(ERC20(from), address(swapper), 1e8);

        // Should kick with default minAmountToSell of 0
        (bool shouldKick, bytes memory data) = swapper.auctionTrigger(from);
        assertTrue(shouldKick);
        bytes memory expectedData = abi.encodeCall(swapper.kickAuction, (from));
        assertEq(data, expectedData);

        // Set minAmountToSell higher than our balance
        swapper.setMinAmountToSell(2e8);

        (shouldKick, data) = swapper.auctionTrigger(from);
        assertFalse(shouldKick);
        assertEq(data, bytes("not enough kickable"));

        // Add more to exceed the minimum
        airdrop(ERC20(from), address(swapper), 1e8 + 1); // Now we have 2e8 + 1 (clearly > 2e8)

        (shouldKick, data) = swapper.auctionTrigger(from);
        assertTrue(shouldKick); // Should kick when amount > minAmountToSell
        expectedData = abi.encodeCall(swapper.kickAuction, (from));
        assertEq(data, expectedData);

        // Kick the auction to test that kickable returns 0 during active auction
        swapper.kickAuction(from);

        // Add more tokens
        airdrop(ERC20(from), address(swapper), 1e8);

        // Should not kick because auction is active with available tokens
        (shouldKick, data) = swapper.auctionTrigger(from);
        assertFalse(shouldKick);
        assertEq(data, bytes("not enough kickable"));

        // Verify kickable is 0 during active auction
        assertEq(swapper.kickable(from), 0);
    }
}
