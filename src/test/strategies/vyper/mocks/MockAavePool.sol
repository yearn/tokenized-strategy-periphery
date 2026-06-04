// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IMintBurn is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * @title  MockAavePool
 * @notice Minimal Aave V3 Pool stand-in for unit tests.
 *         supply()  — transfers underlying from caller → pool, mints aToken 1:1.
 *         withdraw() — burns aToken from caller, sends underlying to `to`.
 *         simulateYield() — mints extra aToken to simulate rebasing interest;
 *                           test fixture must also fund the pool with matching
 *                           underlying so withdrawals can be served.
 */
contract MockAavePool {
    using SafeERC20 for IERC20;

    mapping(address => address) public atokenFor;

    function setAtoken(address _asset, address _atoken) external {
        atokenFor[_asset] = _atoken;
    }

    function supply(address _asset, uint256 _amount, address _onBehalfOf, uint16) external {
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);
        IMintBurn(atokenFor[_asset]).mint(_onBehalfOf, _amount);
    }

    function withdraw(address _asset, uint256 _amount, address _to) external returns (uint256) {
        IMintBurn(atokenFor[_asset]).burn(msg.sender, _amount);
        IERC20(_asset).safeTransfer(_to, _amount);
        return _amount;
    }

    function simulateYield(address _asset, address _holder, uint256 _amount) external {
        IMintBurn(atokenFor[_asset]).mint(_holder, _amount);
    }
}
