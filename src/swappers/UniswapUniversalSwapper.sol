// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniversalRouter} from "../interfaces/Uniswap/IUniversalRouter.sol";
import {Currency, IHooks, PoolKey, PathKey, IV4Router} from "../interfaces/Uniswap/IV4Router.sol";
import {Commands} from "../interfaces/Uniswap/Commands.sol";
import {Actions} from "../interfaces/Uniswap/Actions.sol";
import {BaseSwapper} from "./BaseSwapper.sol";
import {ActionConstants} from "../interfaces/Uniswap/ActionConstants.sol";

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

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

    enum UsingWeth {
        None,
        Input,
        Output
    }

    // WETH address - immutable, set in constructor
    // V4 uses native ETH, so we wrap/unwrap as needed
    address public immutable weth;

    // Defaults to WETH on mainnet
    address public base;

    // Universal Router (supports V3, V4) - mainnet
    address public router = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    // V4 PositionManager - mainnet
    address public positionManager = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;

    // Permit2 - used for V4 settlement
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    constructor(address _weth) {
        weth = _weth;
        base = _weth;
    }

    /// @notice Accept ETH (needed for V4 swaps that output ETH)
    receive() external payable {}

    /**
     * @dev Convert token address for V4 - WETH becomes ETH (address(0)).
     * @param _token The token address to convert.
     * @return The address to use in V4 (address(0) for ETH, original for others).
     */
    function _toV4Currency(address _token) internal view returns (address) {
        return _token == weth ? address(0) : _token;
    }

    /// @notice V4 pool config
    struct V4PoolConfig {
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapContext {
        bool isSingleHop;
        bool hop1IsV3;
        bool needsPostWrap;
        uint256 ethToSend;
        uint256 balanceOutBefore;
        uint256 ethBalanceBefore;
        bytes commands;
        bytes[] inputs;
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
        IPositionManager.PoolKeyPM memory key = IPositionManager(positionManager)
            .poolKeys(truncatedId);

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

        SwapContext memory ctx;
        ctx.isSingleHop = (_from == base || _to == base);
        ctx.hop1IsV3 = ctx.isSingleHop ? uniFees[_from][_to] != 0 : uniFees[_from][base] != 0;
        bool hop2IsV3 = ctx.isSingleHop ? ctx.hop1IsV3 : uniFees[base][_to] != 0;

        if (ctx.isSingleHop) {
            (ctx.commands, ctx.inputs) = _buildSingleHop(_from, _to, _amountIn, _minAmountOut);
        } else {
            (ctx.commands, ctx.inputs) = _buildTwoHops(_from, _to, _amountIn, _minAmountOut, ctx.hop1IsV3, hop2IsV3);
        }

        ctx.balanceOutBefore = ERC20(_to).balanceOf(address(this));
        ctx.ethBalanceBefore = address(this).balance;

        bool usesRouterUnwrap = ctx.isSingleHop && !ctx.hop1IsV3 && _from == weth;

        // Fund router or Permit2 based on first hop
        if (ctx.hop1IsV3) {
            ERC20(_from).safeTransfer(router, _amountIn);
        } else {
            if (_from == weth) {
                if (usesRouterUnwrap) {
                    // Router will UNWRAP_WETH; keep WETH in router.
                    ERC20(_from).safeTransfer(router, _amountIn);
                } else {
                    // V4 paths that expect native ETH; unwrap locally and send as value.
                    IWETH(weth).withdraw(_amountIn);
                    ctx.ethToSend = _amountIn;
                }
            } else {
                _approvePermit2(_from, _amountIn);
            }
        }

        IUniversalRouter(router).execute{value: ctx.ethToSend}(ctx.commands, ctx.inputs, block.timestamp);

        if (ctx.needsPostWrap) {
            uint256 ethDelta = address(this).balance - ctx.ethBalanceBefore;
            if (ethDelta > 0) {
                IWETH(weth).deposit{value: ethDelta}();
            }
        }

        _amountOut = ERC20(_to).balanceOf(address(this)) - ctx.balanceOutBefore;
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).forceApprove(_contract, _amount);
        }
    }

    function _approvePermit2(
        address _token,
        uint256 _amount
    ) internal {
        // First approve the token for Permit2
        if (ERC20(_token).allowance(address(this), PERMIT2) < _amount) {
            ERC20(_token).forceApprove(PERMIT2, type(uint256).max);
        }
        // Then approve the router on Permit2
        // Permit2.approve(token, spender, amount, expiration)
        IPermit2(PERMIT2).approve(_token, router, uint160(_amount), uint48(block.timestamp + 3600));
    }

    function _buildSingleHop(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        inputs = new bytes[](2);

        if (uniFees[_from][_to] != 0) {
            commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
            inputs = new bytes[](1);
            inputs[0] = _buildV3ExactIn(
                address(this),
                _amountIn,
                _minAmountOut,
                abi.encodePacked(_from, uniFees[_from][_to], _to)
            );
            return (commands, inputs);
        }

        address swapRecipient = address(this);
        uint256 swapLocation = 0;

        if (_from == weth) {
            commands = abi.encodePacked(uint8(Commands.UNWRAP_WETH), uint8(Commands.V4_SWAP));
            inputs[0] = abi.encode(ActionConstants.ADDRESS_THIS, _amountIn);
            swapLocation = 1;
        } else if (_to == weth) {
            commands = abi.encodePacked(uint8(Commands.V4_SWAP), uint8(Commands.WRAP_ETH));
            swapRecipient = ActionConstants.ADDRESS_THIS;
            inputs[1] = abi.encode(address(this), ActionConstants.CONTRACT_BALANCE);
        } else {
            commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        }
        inputs[swapLocation] = _buildV4ExactInSingle(_from, _to, _amountIn, _minAmountOut, swapRecipient);
    }

    function _buildTwoHops(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        bool hop1IsV3,
        bool hop2IsV3
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        bool baseIsWeth = (base == weth);

        if (hop1IsV3 && hop2IsV3) {
            return _buildTwoV3Hops(_from, _to, _amountIn, _minAmountOut);
        }

        if (!hop1IsV3 && !hop2IsV3) {
            return _buildTwoV4Hops(_from, _to, _amountIn, _minAmountOut);
        }

        if (hop1IsV3) {
            return _buildV3ThenV4(_from, _to, _amountIn, _minAmountOut, baseIsWeth);
        }

        return _buildV4ThenV3(_from, _to, _amountIn, _minAmountOut, baseIsWeth);
    }

    function _buildTwoV3Hops(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
        inputs = new bytes[](1);
        inputs[0] = _buildV3ExactIn(
            address(this),
            _amountIn,
            _minAmountOut,
            abi.encodePacked(_from, uniFees[_from][base], base, uniFees[base][_to], _to)
        );
        return (commands, inputs);
    }

    function _buildTwoV4Hops(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        inputs = new bytes[](1);
        inputs[0] = _buildV4MultiHopInput(_from, _to, _amountIn, _minAmountOut);
        return (commands, inputs);
    }

    function _buildV3ThenV4(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        bool baseIsWeth
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        if (baseIsWeth) {
            commands = new bytes(3);
            inputs = new bytes[](3);

            commands[0] = bytes1(uint8(Commands.V3_SWAP_EXACT_IN));
            inputs[0] = _buildV3ExactIn(
                address(2),
                _amountIn,
                0,
                abi.encodePacked(_from, uniFees[_from][base], base)
            );

            commands[1] = bytes1(uint8(Commands.UNWRAP_WETH));
            inputs[1] = abi.encode(address(2), uint256(0));

            commands[2] = bytes1(uint8(Commands.V4_SWAP));
            inputs[2] = _buildV4ExactInSingle(base, _to, 0, _minAmountOut, address(this));
            return (commands, inputs);
        }

        commands = new bytes(2);
        inputs = new bytes[](2);

        commands[0] = bytes1(uint8(Commands.V3_SWAP_EXACT_IN));
        inputs[0] = _buildV3ExactIn(
            address(2),
            _amountIn,
            0,
            abi.encodePacked(_from, uniFees[_from][base], base)
        );

        commands[1] = bytes1(uint8(Commands.V4_SWAP));
        inputs[1] = _buildV4ExactInSingle(base, _to, 0, _minAmountOut, address(this));
        return (commands, inputs);
    }

    function _buildV4ThenV3(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut,
        bool baseIsWeth
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        if (baseIsWeth) {
            commands = new bytes(3);
            inputs = new bytes[](3);

            commands[0] = bytes1(uint8(Commands.V4_SWAP));
            inputs[0] = _buildV4ExactInSingle(_from, base, _amountIn, 0, address(2));

            commands[1] = bytes1(uint8(Commands.WRAP_ETH));
            inputs[1] = abi.encode(address(2), uint256(0));

            commands[2] = bytes1(uint8(Commands.V3_SWAP_EXACT_IN));
            inputs[2] = _buildV3ExactIn(
                address(this),
                0,
                _minAmountOut,
                abi.encodePacked(base, uniFees[base][_to], _to)
            );
            return (commands, inputs);
        }

        commands = new bytes(2);
        inputs = new bytes[](2);

        commands[0] = bytes1(uint8(Commands.V4_SWAP));
        inputs[0] = _buildV4ExactInSingle(_from, base, _amountIn, 0, address(2));

        commands[1] = bytes1(uint8(Commands.V3_SWAP_EXACT_IN));
        inputs[1] = _buildV3ExactIn(
            address(this),
            0,
            _minAmountOut,
            abi.encodePacked(base, uniFees[base][_to], _to)
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

        address v4TokenIn = _toV4Currency(_tokenIn);
        address v4TokenOut = _toV4Currency(_tokenOut);

        (Currency currency0, Currency currency1) = v4TokenIn < v4TokenOut
            ? (Currency.wrap(v4TokenIn), Currency.wrap(v4TokenOut))
            : (Currency.wrap(v4TokenOut), Currency.wrap(v4TokenIn));

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: config.fee,
            tickSpacing: config.tickSpacing,
            hooks: IHooks(config.hooks)
        });

        IV4Router.ExactInputSingleParams memory swapParams = IV4Router.ExactInputSingleParams({
            poolKey: poolKey,
            zeroForOne: v4TokenIn < v4TokenOut,
            amountIn: uint128(_amountIn),
            amountOutMinimum: uint128(_minAmountOut),
            hookData: bytes("")
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(_takeRecipient == address(2) ? Actions.TAKE_PORTION : Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams);
        params[1] = abi.encode(
            Currency.wrap(v4TokenIn),
            type(uint128).max
        );
        params[2] = _takeRecipient == address(2)
            ? abi.encode(Currency.wrap(v4TokenOut), _takeRecipient, 10_000)
            : abi.encode(Currency.wrap(v4TokenOut), _minAmountOut);

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
        address v4From = _toV4Currency(_from);
        address v4Base = _toV4Currency(base);
        address v4To = _toV4Currency(_to);

        PathKey[] memory path = new PathKey[](2);

        V4PoolConfig memory config1 = v4Pools[_from][base];
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(v4Base),
            fee: config1.fee,
            tickSpacing: config1.tickSpacing,
            hooks: IHooks(config1.hooks),
            hookData: bytes("")
        });

        V4PoolConfig memory config2 = v4Pools[base][_to];
        path[1] = PathKey({
            intermediateCurrency: Currency.wrap(v4To),
            fee: config2.fee,
            tickSpacing: config2.tickSpacing,
            hooks: IHooks(config2.hooks),
            hookData: bytes("")
        });

        IV4Router.ExactInputParams memory swapParams = IV4Router.ExactInputParams({
            currencyIn: Currency.wrap(v4From),
            path: path,
            amountIn: uint128(_amountIn),
            amountOutMinimum: uint128(_minAmountOut)
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(swapParams);
        params[1] = abi.encode(Currency.wrap(v4From), _amountIn);
        params[2] = abi.encode(Currency.wrap(v4To), _minAmountOut);

        return abi.encode(actions, params);
    }
}
