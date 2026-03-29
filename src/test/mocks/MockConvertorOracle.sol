// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

contract MockConvertorOracle {
    uint256 public price;

    function setPrice(uint256 _price) external {
        require(_price > 0, "price");
        price = _price;
    }
}
