// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ISwapRouter} from "../interfaces/Uniswap/V3/ISwapRouter.sol";

/**
 *   @title UniswapV3Swapper
 *   @author Yearn.finance
 *   @dev This is a simple contract that can be inherited by any tokenized
 *   strategy that would like to use Uniswap V3 for swaps. It hold all needed
 *   logic to perform both exact input and exact output swaps.
 *
 *   The global addres variables defualt to the ETH mainnet addresses but
 *   remain settable by the inheriting contract to allow for customization
 *   based on needs or chain its used on.
 *
 *   The only variables that are required to be set are the specific fees
 *   for each token pair. The inheriting contract can use the {_setUniFees}
 *   function to easily set this for any token pairs needed.
 */
contract UniswapV3Swapper {
    // Optional Variable to be set to not sell dust.
    uint256 public minAmountToSell;
    // Defualts to WETH on mainnet.
    address public base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Defualts to Uniswap V3 router on mainnet.
    address public router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // Fees for the Uni V3 pools. Each fee should get set each way in
    // the mapping so no matter the direction the correct fee will get
    // returned for any two tokens.
    mapping(address => mapping(address => uint24)) public uniFees;

    /**
     * @dev All fess will defualt to 0 on creation. A strategist will need
     * To set the mapping for the tokens expected to swap. This function
     * is to help set the mapping. It can be called internally during
     * intialization, through permisioned functions etc.
     */
    function _setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) internal {
        uniFees[_token0][_token1] = _fee;
        uniFees[_token1][_token0] = _fee;
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allownaces as well as not swapping
     * unless `_amountIn` is greater than the set `minAmountToSell`
     *
     * If one of the tokens matches with the `base` token it will do only
     * one jump, otherwise will do two jumps.
     *
     * The corresponding uniFees for each token pair will need to be set
     * other wise this function will revert.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountIn The amount of `_from` we will swap.
     * @param _minAmountOut The min of `_to` to get out.
     * @return _amountOut The actual amount of `_to` that was swapped to
     */
    function _swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal returns (uint256 _amountOut) {
        if (_amountIn > minAmountToSell) {
            _checkAllowance(router, _from, _amountIn);
            if (_from == base || _to == base) {
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams(
                        _from, // tokenIn
                        _to, // tokenOut
                        uniFees[_from][_to], // from-to fee
                        address(this), // recipient
                        block.timestamp, // deadline
                        _amountIn, // amountIn
                        _minAmountOut, // amountOut
                        0 // sqrtPriceLimitX96
                    );

                _amountOut = ISwapRouter(router).exactInputSingle(params);
            } else {
                bytes memory path = abi.encodePacked(
                    _from, // tokenIn
                    uniFees[_from][base], // from-base fee
                    base, // base token
                    uniFees[base][_to], // base-to fee
                    _to // tokenOut
                );

                _amountOut = ISwapRouter(router).exactInput(
                    ISwapRouter.ExactInputParams(
                        path,
                        address(this),
                        block.timestamp,
                        _amountIn,
                        _minAmountOut
                    )
                );
            }
        }
    }

    /**
     * @dev Used to swap a specific amount of `_to` from `_from` unless
     * it takes more than `_maxAmountFrom`.
     *
     * This will check and handle all allownaces as well as not swapping
     * unless `_maxAmountFrom` is greater than the set `minAmountToSell`
     *
     * If one of the tokens matches with the `base` token it will do only
     * one jump, otherwise will do two jumps.
     *
     * The corresponding uniFees for each token pair will need to be set
     * other wise this function will revert.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountTo The amount of `_to` we need out.
     * @param _maxAmountFrom The max of `_from` we will swap.
     * @return _amountIn The actual amouont of `_from` swapped.
     */
    function _swapTo(
        address _from,
        address _to,
        uint256 _amountTo,
        uint256 _maxAmountFrom
    ) internal returns (uint256 _amountIn) {
        if (_maxAmountFrom > minAmountToSell) {
            _checkAllowance(router, _from, _maxAmountFrom);
            if (_from == base || _to == base) {
                ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
                    .ExactOutputSingleParams(
                        _from, // tokenIn
                        _to, // tokenOut
                        uniFees[_from][_to], // from-to fee
                        address(this), // recipient
                        block.timestamp, // deadline
                        _amountTo, // amountOut
                        _maxAmountFrom, // maxAmountIn
                        0 // sqrtPriceLimitX96
                    );

                _amountIn = ISwapRouter(router).exactOutputSingle(params);
            } else {
                bytes memory path = abi.encodePacked(
                    _to,
                    uniFees[base][_to], // base-to fee
                    base,
                    uniFees[_from][base], // from-base fee
                    _from
                );

                _amountIn = ISwapRouter(router).exactOutput(
                    ISwapRouter.ExactOutputParams(
                        path,
                        address(this),
                        block.timestamp,
                        _amountTo, // How much we want out
                        _maxAmountFrom
                    )
                );
            }
        }
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).approve(_contract, 0);
            ERC20(_token).approve(_contract, _amount);
        }
    }
}
