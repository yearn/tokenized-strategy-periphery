// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IFluidDexT1} from "../interfaces/Fluid/IFluidDexV2Router.sol";
import {BaseSwapper} from "./BaseSwapper.sol";

/**
 * @title FluidSwapper
 * @author Yearn.finance
 * @dev Lightweight swapper mixin for Fluid DEX exact-input swaps.
 *
 *      Fluid DEX pools are set per token pair and swaps are executed directly
 *      against the configured DEX contract.
 */
contract FluidSwapper is BaseSwapper {
    using SafeERC20 for ERC20;

    // Defaults to WETH on mainnet.
    address public base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    struct FluidDexConfig {
        address dex;
        bool swap0to1;
    }

    /// @notice Token pair => Fluid DEX config used for swaps.
    mapping(address => mapping(address => FluidDexConfig)) public fluidDexes;

    /**
     * @dev Set Fluid DEX for a token pair. Stored both directions.
     *
     * This variant auto-detects the pool direction from `_dex.constantsView()`
     * and sets the correct `swap0to1` value for `_token0` -> `_token1`.
     *
     * @param _token0 First token in pair.
     * @param _token1 Second token in pair.
     * @param _dex Fluid DEX pool contract.
     */
    function _setFluidDex(
        address _token0,
        address _token1,
        address _dex
    ) internal virtual {
        require(
            _token0 != address(0) &&
                _token1 != address(0) &&
                _dex != address(0),
            "bad token"
        );
        require(_token0 != _token1, "same token");

        IFluidDexT1.ConstantViews memory _constants = IFluidDexT1(_dex)
            .constantsView();

        if (_constants.token0 == _token0 && _constants.token1 == _token1) {
            _setFluidDex(_token0, _token1, _dex, true);
        } else if (
            _constants.token0 == _token1 && _constants.token1 == _token0
        ) {
            _setFluidDex(_token0, _token1, _dex, false);
        } else {
            revert("dex mismatch");
        }
    }

    /**
     * @dev Set Fluid DEX for a token pair with explicit swap direction.
     * @param _from Token sold when using the provided `_swap0to1`.
     * @param _to Token bought when using the provided `_swap0to1`.
     * @param _dex Fluid DEX pool contract.
     * @param _swap0to1 Value to pass as `swap0to1` for `_from` -> `_to`.
     */
    function _setFluidDex(
        address _from,
        address _to,
        address _dex,
        bool _swap0to1
    ) internal virtual {
        require(
            _from != address(0) && _to != address(0) && _dex != address(0),
            "bad token"
        );
        require(_from != _to, "same token");

        fluidDexes[_from][_to] = FluidDexConfig({
            dex: _dex,
            swap0to1: _swap0to1
        });
        fluidDexes[_to][_from] = FluidDexConfig({
            dex: _dex,
            swap0to1: !_swap0to1
        });
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allowances as well as not swapping
     * unless `_amountIn` is greater than the set `_minAmountOut`.
     *
     * If one of the tokens matches with the `base` token it will do only
     * one hop, otherwise will do two hops through `base`.
     */
    function _fluidSwapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual returns (uint256 _amountOut) {
        if (_amountIn != 0 && _amountIn >= minAmountToSell) {
            if (_from == base || _to == base) {
                _amountOut = _fluidSwapInStep(
                    _from,
                    _to,
                    _amountIn,
                    _minAmountOut
                );
            } else {
                _amountOut = _fluidSwapInStep(_from, base, _amountIn, 0);
                _amountOut = _fluidSwapInStep(
                    base,
                    _to,
                    _amountOut,
                    _minAmountOut
                );
            }
        }
    }

    /**
     * @dev Execute a single Fluid DEX exact-input hop.
     */
    function _fluidSwapInStep(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual returns (uint256 _amountOut) {
        FluidDexConfig memory _config = fluidDexes[_from][_to];
        require(_config.dex != address(0), "dex not set");

        _checkAllowance(_config.dex, _from, _amountIn);

        _amountOut = IFluidDexT1(_config.dex).swapIn(
            _config.swap0to1,
            _amountIn,
            _minAmountOut,
            address(this)
        );
    }

    /**
     * @dev Ensure `_contract` has sufficient allowance for `_token`.
     */
    function _checkAllowance(
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
