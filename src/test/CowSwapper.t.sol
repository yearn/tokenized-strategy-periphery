// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, ERC20} from "./utils/Setup.sol";

import {GPv2Order} from "../libraries/GPv2Order.sol";
import {IMockCowSwapper, MockCowSwapper} from "./mocks/MockCowSwapper.sol";

contract MockCowSettlement {
    bytes32 internal immutable DOMAIN_SEPARATOR;

    constructor(bytes32 _domainSeparator) {
        DOMAIN_SEPARATOR = _domainSeparator;
    }

    function domainSeparator() external view returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }
}

contract CowSwapperTest is Setup {
    IMockCowSwapper public cowSwapper;
    MockCowSettlement public cowSettlement;

    ERC20 public sellToken;
    ERC20 public buyToken;

    address public relayer = address(123_456_789);

    function setUp() public override {
        super.setUp();

        sellToken = ERC20(tokenAddrs["USDC"]);
        buyToken = ERC20(tokenAddrs["DAI"]);

        cowSwapper = IMockCowSwapper(
            address(new MockCowSwapper(address(asset)))
        );

        cowSwapper.setKeeper(keeper);
        cowSwapper.setPerformanceFeeRecipient(performanceFeeRecipient);
        cowSwapper.setPendingManagement(management);

        vm.prank(management);
        cowSwapper.acceptManagement();

        cowSettlement = new MockCowSettlement(keccak256("MOCK_COW_DOMAIN"));

        vm.startPrank(management);
        cowSwapper.setCowSettlement(address(cowSettlement));
        cowSwapper.setCowVaultRelayer(relayer);
        cowSwapper.setCowOrderDuration(1 hours);
        cowSwapper.setCowAppData(bytes32("TEST_APP_DATA"));
        cowSwapper.setMinAmountToSell(1);
        vm.stopPrank();
    }

    function test_requestCowSwap_setsOrderState(uint256 _amountIn) public {
        vm.assume(_amountIn >= minFuzzAmount && _amountIn <= maxFuzzAmount);
        airdrop(sellToken, address(cowSwapper), _amountIn);

        vm.prank(keeper);
        bytes32 orderHash = cowSwapper.requestCowSwap(
            address(sellToken),
            address(buyToken),
            _amountIn,
            _amountIn
        );

        assertTrue(orderHash != bytes32(0));
        assertEq(cowSwapper.activeOrder(address(sellToken)), orderHash);
        assertTrue(cowSwapper.isCowOrderActive(orderHash));
        assertGe(sellToken.allowance(address(cowSwapper), relayer), _amountIn);

        (
            address storedSellToken,
            address storedBuyToken,
            uint256 storedSellAmount,
            uint256 storedBuyAmount,
            uint32 validTo
        ) = cowSwapper.cowOrders(orderHash);

        assertEq(storedSellToken, address(sellToken));
        assertEq(storedBuyToken, address(buyToken));
        assertEq(storedSellAmount, _amountIn);
        assertEq(storedBuyAmount, _amountIn);
        assertEq(validTo, uint32(block.timestamp + 1 hours));
    }

    function test_isValidSignature_validOrder(uint256 _amountIn) public {
        vm.assume(_amountIn >= minFuzzAmount && _amountIn <= maxFuzzAmount);
        bytes32 orderHash = _createOrder(_amountIn, _amountIn / 2);

        GPv2Order.Data memory order = _getOrder(orderHash);

        bytes4 magic = cowSwapper.isValidSignature(
            orderHash,
            abi.encode(order)
        );
        assertEq(magic, bytes4(keccak256("isValidSignature(bytes32,bytes)")));
    }

    function test_isValidSignature_canceledOrderReverts(
        uint256 _amountIn
    ) public {
        vm.assume(_amountIn >= minFuzzAmount && _amountIn <= maxFuzzAmount);
        bytes32 orderHash = _createOrder(_amountIn, _amountIn / 2);
        GPv2Order.Data memory order = _getOrder(orderHash);

        vm.prank(management);
        cowSwapper.cancelCowSwap(address(sellToken));

        vm.expectRevert("order not active");
        cowSwapper.isValidSignature(orderHash, abi.encode(order));
    }

    function test_requestCowSwap_replacesPreviousOrder(
        uint256 _amountIn
    ) public {
        vm.assume(_amountIn >= minFuzzAmount && _amountIn <= maxFuzzAmount);
        airdrop(sellToken, address(cowSwapper), _amountIn + (_amountIn / 2));

        vm.prank(keeper);
        bytes32 orderHash0 = cowSwapper.requestCowSwap(
            address(sellToken),
            address(buyToken),
            _amountIn,
            _amountIn / 2
        );

        vm.prank(keeper);
        bytes32 orderHash1 = cowSwapper.requestCowSwap(
            address(sellToken),
            address(asset),
            _amountIn / 2,
            _amountIn / 2
        );

        assertTrue(orderHash0 != orderHash1);
        assertEq(cowSwapper.activeOrder(address(sellToken)), orderHash1);
        assertFalse(cowSwapper.isCowOrderActive(orderHash0));
        assertTrue(cowSwapper.isCowOrderActive(orderHash1));
    }

    function _createOrder(
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal returns (bytes32) {
        airdrop(sellToken, address(cowSwapper), _amountIn);

        vm.prank(keeper);
        return
            cowSwapper.requestCowSwap(
                address(sellToken),
                address(buyToken),
                _amountIn,
                _minAmountOut
            );
    }

    function _getOrder(
        bytes32 _orderHash
    ) internal view returns (GPv2Order.Data memory _order) {
        (
            address storedSellToken,
            address storedBuyToken,
            uint256 storedSellAmount,
            uint256 storedBuyAmount,
            uint32 storedValidTo
        ) = cowSwapper.cowOrders(_orderHash);

        _order = GPv2Order.Data({
            sellToken: ERC20(storedSellToken),
            buyToken: ERC20(storedBuyToken),
            receiver: address(cowSwapper),
            sellAmount: storedSellAmount,
            buyAmount: storedBuyAmount,
            validTo: storedValidTo,
            appData: cowSwapper.cowAppData(),
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: true,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }
}
