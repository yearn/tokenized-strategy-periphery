// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniversalRouter} from "../interfaces/Uniswap/V4/IUniversalRouter.sol";
import {Currency, IHooks, PoolKey, PathKey, IV4Router} from "../interfaces/Uniswap/V4/IV4Router.sol";
import {Commands} from "../libraries/Uniswap/Commands.sol";
import {Actions} from "../libraries/Uniswap/Actions.sol";
import {BaseSwapper} from "./BaseSwapper.sol";
import {ActionConstants} from "../libraries/Uniswap/ActionConstants.sol";

interface IPositionManager {
    struct PoolKeyPM {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    function poolKeys(bytes25 poolId) external view returns (PoolKeyPM memory);
}

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;
}

/**
 * @title UniswapUniversalSwapper
 * @author yearn.fi
 * @dev Swapper using Uniswap's Universal Router for V3 and V4 pools.
 *
 *   Works like UniswapV3Swapper: if from or to is base, single hop.
 *   Otherwise routes through base (from -> base -> to).
 *
 *   For each hop, checks V3 fee first. If set, uses V3. Otherwise uses V4.
 *
 *   V4 uses native ETH instead of WETH. This contract handles wrapping/unwrapping
 *   automatically - always accepting and returning WETH externally.
 *
 *   Usage:
 *   - Set V3 fees via _setUniFees(tokenA, tokenB, fee)
 *   - Set V4 pools via _setV4Pool(tokenA, tokenB, poolId) or manual params
 *   - Execute swaps via _swapFrom()
 */
contract UniswapUniversalSwapper is BaseSwapper {
    using SafeERC20 for ERC20;

    // WETH address - immutable, set in constructor
    // V4 uses native ETH, so we wrap/unwrap as needed
    address public immutable weth;

    // Defaults to WETH on mainnet
    address public base;

    // Universal Router (supports V3, V4) - mainnet
    address public router = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    // V4 PositionManager - mainnet
    address public positionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

    constructor(address _weth) {
        weth = _weth;
        base = _weth;
    }

    /// @notice Accept ETH (needed for V4 swaps that output ETH)
    receive() external payable {}

    /**
     * @dev Convert token address for V4 - WETH becomes ETH (address(0)).
     * @param _token The token address to convert.
     * @return The Currency to use in V4 (Currency.wrap(address(0)) for ETH, Currency.wrap(_token) for others).
     */
    function _toV4Currency(address _token) internal view returns (Currency) {
        return
            _token == weth ? Currency.wrap(address(0)) : Currency.wrap(_token);
    }

    /// @notice V4 pool config
    struct V4PoolConfig {
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    /// @notice V3 fees: tokenA => tokenB => fee (0 means not set, use V4)
    mapping(address => mapping(address => uint24)) public uniFees;

    /// @notice V4 pools: tokenA => tokenB => config
    mapping(address => mapping(address => V4PoolConfig)) public v4Pools;

    /**
     * @dev Set V3 fee for a token pair (both directions).
     */
    function _setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) internal virtual {
        uniFees[_token0][_token1] = _fee;
        uniFees[_token1][_token0] = _fee;
    }

    /**
     * @dev Set V4 pool from poolId. Queries PositionManager for pool config.
     * @param _poolId The bytes32 pool ID (will be truncated to bytes25).
     */
    function _setV4Pool(
        address _token0,
        address _token1,
        bytes32 _poolId
    ) internal virtual {
        bytes25 truncatedId = bytes25(_poolId);
        IPositionManager.PoolKeyPM memory key = IPositionManager(
            positionManager
        ).poolKeys(truncatedId);

        _setV4Pool(_token0, _token1, key.fee, key.tickSpacing, key.hooks);
    }

    /**
     * @dev Set V4 pool manually (alternative to poolId lookup).
     */
    function _setV4Pool(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing,
        address _hooks
    ) internal virtual {
        V4PoolConfig memory config = V4PoolConfig(_fee, _tickSpacing, _hooks);
        v4Pools[_token0][_token1] = config;
        v4Pools[_token1][_token0] = config;
    }

    /**
     * @dev Swap tokens. Single hop if from/to is base, else two hops through base.
     *   For each hop: uses V3 if uniFees is set, otherwise V4.
     *
     *   V4 uses native ETH instead of WETH. Wrapping/unwrapping is handled by
     *   Universal Router commands (WRAP_ETH / UNWRAP_WETH) or by wrapping an
     *   ETH delta after execution when the output should be WETH.
     */
    function _swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual returns (uint256 _amountOut) {
        if (_amountIn == 0 || _amountIn < minAmountToSell) return 0;

        bytes memory commands;
        bytes[] memory inputs;
        if (_from == base || _to == base) {
            (commands, inputs) = _buildSingleHop(
                _from,
                _to,
                _amountIn,
                _minAmountOut
            );
        } else {
            (commands, inputs) = _buildTwoHops(
                _from,
                _to,
                _amountIn,
                _minAmountOut
            );
        }

        uint256 balanceOutBefore = ERC20(_to).balanceOf(address(this));

        ERC20(_from).safeTransfer(router, _amountIn);

        IUniversalRouter(router).execute(commands, inputs, block.timestamp);

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            IWETH(weth).deposit{value: ethBalance}();
        }

        _amountOut = ERC20(_to).balanceOf(address(this)) - balanceOutBefore;
    }

    function _buildSingleHop(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        uint24 fee = uniFees[_from][_to];
        if (fee != 0) {
            commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
            inputs = new bytes[](1);
            inputs[0] = _buildV3ExactIn(
                address(this),
                _amountIn,
                _minAmountOut,
                abi.encodePacked(_from, fee, _to)
            );
            return (commands, inputs);
        }

        address swapRecipient = address(this);
        uint256 swapLocation = 0;

        if (_from == weth) {
            inputs = new bytes[](2);
            commands = abi.encodePacked(
                uint8(Commands.UNWRAP_WETH),
                uint8(Commands.V4_SWAP)
            );
            inputs[0] = abi.encode(ActionConstants.ADDRESS_THIS, _amountIn);
            swapLocation = 1;
        } else if (_to == weth) {
            inputs = new bytes[](2);
            commands = abi.encodePacked(
                uint8(Commands.V4_SWAP),
                uint8(Commands.WRAP_ETH)
            );
            swapRecipient = ActionConstants.ADDRESS_THIS;
            inputs[1] = abi.encode(
                address(this),
                ActionConstants.CONTRACT_BALANCE
            );
        } else {
            inputs = new bytes[](1);
            commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        }
        inputs[swapLocation] = _buildV4ExactInSingle(
            _from,
            _to,
            _amountIn,
            _minAmountOut,
            swapRecipient
        );
    }

    function _buildTwoHops(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        bool baseIsWeth = (base == weth);
        uint24 fee1 = uniFees[_from][base];
        uint24 fee2 = uniFees[base][_to];

        if (fee1 != 0 && fee2 != 0) {
            return
                _buildTwoV3Hops(
                    _from,
                    _to,
                    _amountIn,
                    _minAmountOut,
                    fee1,
                    fee2
                );
        }

        if (fee1 == 0 && fee2 == 0) {
            return _buildTwoV4Hops(_from, _to, _amountIn, _minAmountOut);
        }

        if (fee1 != 0) {
            return
                _buildV3ThenV4(
                    _from,
                    _to,
                    _amountIn,
                    _minAmountOut,
                    baseIsWeth,
                    fee1
                );
        }

        return
            _buildV4ThenV3(
                _from,
                _to,
                _amountIn,
                _minAmountOut,
                baseIsWeth,
                fee2
            );
    }

    function _buildTwoV3Hops(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint24 _fee1,
        uint24 _fee2
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
        inputs = new bytes[](1);
        inputs[0] = _buildV3ExactIn(
            address(this),
            _amountIn,
            _minAmountOut,
            abi.encodePacked(_from, _fee1, base, _fee2, _to)
        );
        return (commands, inputs);
    }

    function _buildTwoV4Hops(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        if (_from == weth) {
            inputs = new bytes[](2);
            commands = abi.encodePacked(
                uint8(Commands.UNWRAP_WETH),
                uint8(Commands.V4_SWAP)
            );
            inputs[0] = abi.encode(ActionConstants.ADDRESS_THIS, _amountIn);
        } else {
            inputs = new bytes[](1);
            commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        }

        inputs[inputs.length - 1] = _buildV4MultiHopInput(
            _from,
            _to,
            _amountIn,
            _minAmountOut
        );
        return (commands, inputs);
    }

    function _buildV3ThenV4(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        bool baseIsWeth,
        uint24 _fee1
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        uint256 length = baseIsWeth ? 3 : 2;
        commands = new bytes(length);
        inputs = new bytes[](length);

        commands[0] = bytes1(uint8(Commands.V3_SWAP_EXACT_IN));
        inputs[0] = _buildV3ExactIn(
            ActionConstants.ADDRESS_THIS,
            _amountIn,
            0,
            abi.encodePacked(_from, _fee1, base)
        );

        if (baseIsWeth) {
            commands[1] = bytes1(uint8(Commands.UNWRAP_WETH));
            inputs[1] = abi.encode(address(2), uint256(0));
        }

        commands[length - 1] = bytes1(uint8(Commands.V4_SWAP));
        inputs[length - 1] = _buildV4ExactInSingle(
            base,
            _to,
            ActionConstants.CONTRACT_BALANCE,
            _minAmountOut,
            address(this)
        );
        return (commands, inputs);
    }

    function _buildV4ThenV3(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        bool baseIsWeth,
        uint24 _fee2
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        uint256 length = baseIsWeth || _from == weth ? 3 : 2;
        commands = new bytes(length);
        inputs = new bytes[](length);

        if (_from == weth) {
            commands[0] = bytes1(uint8(Commands.UNWRAP_WETH));
            inputs[0] = abi.encode(ActionConstants.ADDRESS_THIS, _amountIn);

            commands[1] = bytes1(uint8(Commands.V4_SWAP));
            inputs[1] = _buildV4ExactInSingle(
                _from,
                base,
                _amountIn,
                0,
                ActionConstants.ADDRESS_THIS
            );
        } else if (baseIsWeth) {
            commands[0] = bytes1(uint8(Commands.V4_SWAP));
            inputs[0] = _buildV4ExactInSingle(
                _from,
                base,
                _amountIn,
                0,
                ActionConstants.ADDRESS_THIS
            );

            commands[1] = bytes1(uint8(Commands.WRAP_ETH));
            inputs[1] = abi.encode(
                ActionConstants.ADDRESS_THIS,
                ActionConstants.CONTRACT_BALANCE
            );
        } else {
            commands[0] = bytes1(uint8(Commands.V4_SWAP));
            inputs[0] = _buildV4ExactInSingle(
                _from,
                base,
                _amountIn,
                0,
                ActionConstants.ADDRESS_THIS
            );
        }

        commands[length - 1] = bytes1(uint8(Commands.V3_SWAP_EXACT_IN));
        inputs[length - 1] = _buildV3ExactIn(
            address(this),
            ActionConstants.CONTRACT_BALANCE,
            _minAmountOut,
            abi.encodePacked(base, _fee2, _to)
        );

        return (commands, inputs);
    }

    function _buildV3ExactIn(
        address _recipient,
        uint256 _amountIn,
        uint256 _minAmountOut,
        bytes memory _path
    ) internal pure returns (bytes memory) {
        return abi.encode(_recipient, _amountIn, _minAmountOut, _path, false);
    }

    function _buildV4ExactInSingle(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minAmountOut,
        address _takeRecipient
    ) internal view returns (bytes memory) {
        V4PoolConfig memory config = v4Pools[_tokenIn][_tokenOut];

        Currency v4TokenIn = _toV4Currency(_tokenIn);
        Currency v4TokenOut = _toV4Currency(_tokenOut);

        bool zeroForOne = Currency.unwrap(v4TokenIn) <
            Currency.unwrap(v4TokenOut);

        PoolKey memory poolKey = PoolKey({
            currency0: zeroForOne ? v4TokenIn : v4TokenOut,
            currency1: zeroForOne ? v4TokenOut : v4TokenIn,
            fee: config.fee,
            tickSpacing: config.tickSpacing,
            hooks: IHooks(config.hooks)
        });

        IV4Router.ExactInputSingleParams memory swapParams = IV4Router
            .ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(_amountIn),
                amountOutMinimum: uint128(_minAmountOut),
                hookData: bytes("")
            });

        bytes memory actions = abi.encodePacked(
            // We either transfer in, or it post v3 swap so we need to settle balances.
            uint8(Actions.SETTLE),
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            // WE take all if final swap, or take portion if to set router as recipient.
            uint8(
                _takeRecipient == ActionConstants.ADDRESS_THIS
                    ? Actions.TAKE_PORTION
                    : Actions.TAKE_ALL
            )
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(
            v4TokenIn,
            ActionConstants.CONTRACT_BALANCE,
            false
        );
        params[1] = abi.encode(swapParams);
        params[2] = abi.encode(v4TokenIn, type(uint128).max);
        params[3] = _takeRecipient == ActionConstants.ADDRESS_THIS
            ? abi.encode(v4TokenOut, _takeRecipient, 10_000)
            : abi.encode(v4TokenOut, _minAmountOut);

        return abi.encode(actions, params);
    }

    /**
     * @dev Build V4 input for multi-hop swap (from -> base -> to).
     */
    function _buildV4MultiHopInput(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal view returns (bytes memory) {
        Currency v4From = _toV4Currency(_from);
        Currency v4Base = _toV4Currency(base);
        Currency v4To = _toV4Currency(_to);

        PathKey[] memory path = new PathKey[](2);

        V4PoolConfig memory config = v4Pools[_from][base];
        path[0] = PathKey({
            intermediateCurrency: v4Base,
            fee: config.fee,
            tickSpacing: config.tickSpacing,
            hooks: IHooks(config.hooks),
            hookData: bytes("")
        });

        config = v4Pools[base][_to];
        path[1] = PathKey({
            intermediateCurrency: v4To,
            fee: config.fee,
            tickSpacing: config.tickSpacing,
            hooks: IHooks(config.hooks),
            hookData: bytes("")
        });

        IV4Router.ExactInputParams memory swapParams = IV4Router
            .ExactInputParams({
                currencyIn: v4From,
                path: path,
                amountIn: uint128(_amountIn),
                amountOutMinimum: uint128(_minAmountOut)
            });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SETTLE), // We transfer in so first need to settle balances.
            uint8(Actions.SWAP_EXACT_IN),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(v4From, ActionConstants.CONTRACT_BALANCE, false);
        params[1] = abi.encode(swapParams);
        params[2] = abi.encode(v4From, _amountIn);
        params[3] = abi.encode(v4To, _minAmountOut);

        return abi.encode(actions, params);
    }
}
