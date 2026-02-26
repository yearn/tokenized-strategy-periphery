// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {GPv2Order} from "../libraries/GPv2Order.sol";
import {BaseSwapper} from "./BaseSwapper.sol";

interface ICowSettlement {
    function domainSeparator() external view returns (bytes32);
}

/**
 * @title CowSwapper
 * @author yearn.fi
 * @dev Helper contract that can be inherited by strategies to create and sign
 *      GPv2 orders through ERC-1271.
 *
 *      This helper follows the same swapper pattern used in other swappers by
 *      exposing internal `_cowSwapFrom` methods with `_from`, `_to`, `_amountIn`
 *      and `_minAmountOut` arguments.
 *
 *      Orders are not executed through this contract. They are signed by this
 *      contract and then settled through CoW Protocol's settlement flow.
 */
contract CowSwapper is BaseSwapper {
    using GPv2Order for GPv2Order.Data;
    using SafeERC20 for ERC20;

    event CowOrderDurationSet(uint32 indexed cowOrderDuration);
    event CowAppDataSet(bytes32 indexed cowAppData);
    event CowSettlementSet(address indexed cowSettlement);
    event CowVaultRelayerSet(address indexed cowVaultRelayer);
    event CowSwapRequested(
        bytes32 indexed orderHash,
        address indexed from,
        address indexed to,
        uint256 amountIn,
        uint256 minAmountOut,
        uint32 validTo
    );
    event CowOrderCancelled(address indexed from, bytes32 indexed orderHash);

    /// @notice CoW Protocol settlement contract.
    address public cowSettlement = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

    /// @notice Relayer approved to transfer sold tokens.
    address public cowVaultRelayer = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    /// @notice Default order duration used by `_cowSwapFrom`.
    uint32 public cowOrderDuration = 30 minutes;

    /// @notice App data used on created CoW orders.
    bytes32 public cowAppData;

    struct CowOrder {
        address sellToken;
        address buyToken;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
    }

    /// @notice Track whether an order hash is still valid for signing.
    mapping(bytes32 => bool) public isCowOrderActive;

    /// @notice Full order params keyed by order hash for validation and UX.
    mapping(bytes32 => CowOrder) public cowOrders;

    /// @notice One active order per sell token. New orders replace old ones.
    mapping(address => bytes32) public activeOrder;

    /**
     * @dev Set the default order duration used by `_cowSwapFrom`.
     */
    function _setCowOrderDuration(uint32 _cowOrderDuration) internal virtual {
        require(_cowOrderDuration != 0, "duration");

        cowOrderDuration = _cowOrderDuration;
        emit CowOrderDurationSet(_cowOrderDuration);
    }

    /**
     * @dev Set appData used for newly created CoW orders.
     */
    function _setCowAppData(bytes32 _cowAppData) internal virtual {
        cowAppData = _cowAppData;
        emit CowAppDataSet(_cowAppData);
    }

    /**
     * @dev Set CoW settlement contract. Useful for non-mainnet deployments.
     */
    function _setCowSettlement(address _cowSettlement) internal virtual {
        require(_cowSettlement != address(0), "ZERO ADDRESS");

        cowSettlement = _cowSettlement;
        emit CowSettlementSet(_cowSettlement);
    }

    /**
     * @dev Set relayer approved to pull sold tokens.
     */
    function _setCowVaultRelayer(address _cowVaultRelayer) internal virtual {
        require(_cowVaultRelayer != address(0), "ZERO ADDRESS");

        cowVaultRelayer = _cowVaultRelayer;
        emit CowVaultRelayerSet(_cowVaultRelayer);
    }

    /**
     * @dev Create a new CoW sell order with default validity window.
     *
     * @param _from The token being sold.
     * @param _to The token being bought.
     * @param _amountIn The max amount of `_from` to sell.
     * @param _minAmountOut The minimum amount of `_to` expected.
     * @return _orderHash The order hash signed by this contract.
     */
    function _cowSwapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual returns (bytes32 _orderHash) {
        return
            _cowSwapFrom(
                _from,
                _to,
                _amountIn,
                _minAmountOut,
                uint32(block.timestamp + cowOrderDuration)
            );
    }

    /**
     * @dev Create a new CoW sell order with custom validity.
     *
     * @param _from The token being sold.
     * @param _to The token being bought.
     * @param _amountIn The max amount of `_from` to sell.
     * @param _minAmountOut The minimum amount of `_to` expected.
     * @param _validTo Order validity timestamp.
     * @return _orderHash The order hash signed by this contract.
     */
    function _cowSwapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint32 _validTo
    ) internal virtual returns (bytes32 _orderHash) {
        if (_amountIn >= minAmountToSell) {
            require(_validTo > block.timestamp, "expired");
            _orderHash = _createCowOrder(
                _from,
                _to,
                _amountIn,
                _minAmountOut,
                _validTo
            );
        }
    }

    /**
     * @dev Cancel the active order for `_from`, if any.
     * @return _orderHash The cancelled hash, or zero if nothing was active.
     */
    function _cancelCowSwap(
        address _from
    ) internal virtual returns (bytes32 _orderHash) {
        _orderHash = activeOrder[_from];
        if (_orderHash == bytes32(0)) return _orderHash;

        delete activeOrder[_from];
        delete isCowOrderActive[_orderHash];
        delete cowOrders[_orderHash];

        emit CowOrderCancelled(_from, _orderHash);
    }

    function _createCowOrder(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint32 _validTo
    ) internal virtual returns (bytes32 _orderHash) {
        require(_from != address(0) && _to != address(0), "ZERO ADDRESS");
        require(_from != _to, "same token");

        _checkCowAllowance(cowVaultRelayer, _from, _amountIn);

        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: ERC20(_from),
            buyToken: ERC20(_to),
            receiver: address(this),
            sellAmount: _amountIn,
            buyAmount: _minAmountOut,
            validTo: _validTo,
            appData: cowAppData,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: true,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        _orderHash = order.hash(
            ICowSettlement(cowSettlement).domainSeparator()
        );

        // Keep order state simple: one active order per sell token.
        _cancelCowSwap(_from);

        isCowOrderActive[_orderHash] = true;
        activeOrder[_from] = _orderHash;
        cowOrders[_orderHash] = CowOrder({
            sellToken: _from,
            buyToken: _to,
            sellAmount: _amountIn,
            buyAmount: _minAmountOut,
            validTo: _validTo
        });

        emit CowSwapRequested(
            _orderHash,
            _from,
            _to,
            _amountIn,
            _minAmountOut,
            _validTo
        );
    }

    /// @dev Validates a COW order signature.
    function isValidSignature(
        bytes32 _hash,
        bytes calldata _signature
    ) external view virtual returns (bytes4) {
        require(isCowOrderActive[_hash], "order not active");

        GPv2Order.Data memory order = abi.decode(_signature, (GPv2Order.Data));
        CowOrder memory storedOrder = cowOrders[_hash];

        require(
            _hash ==
                order.hash(ICowSettlement(cowSettlement).domainSeparator()),
            "bad order"
        );
        require(order.receiver == address(this), "bad receiver");
        require(order.feeAmount == 0, "fee");
        require(order.kind == GPv2Order.KIND_SELL, "kind");
        require(order.partiallyFillable, "partial fill");
        require(order.validTo >= block.timestamp, "expired");
        require(order.appData == cowAppData, "app data");
        require(
            order.sellTokenBalance == GPv2Order.BALANCE_ERC20,
            "bad sell token balance"
        );
        require(
            order.buyTokenBalance == GPv2Order.BALANCE_ERC20,
            "bad buy token balance"
        );
        require(
            activeOrder[storedOrder.sellToken] == _hash,
            "order no longer active"
        );
        require(address(order.sellToken) == storedOrder.sellToken, "bad sell");
        require(address(order.buyToken) == storedOrder.buyToken, "bad buy");
        require(order.sellAmount == storedOrder.sellAmount, "bad amount in");
        require(order.buyAmount == storedOrder.buyAmount, "bad amount out");
        require(order.validTo == storedOrder.validTo, "bad validTo");

        return this.isValidSignature.selector;
    }

    /**
     * @dev Internal safe function to make sure CoW relayer has allowance.
     */
    function _checkCowAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal virtual {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).forceApprove(_contract, 0);
            ERC20(_token).forceApprove(_contract, _amount);
        }
    }
}
