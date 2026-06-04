// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

contract MockERC20 {
    string  public name;
    string  public symbol;
    uint8   public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name; symbol = _symbol; decimals = _decimals;
    }

    function mint(address _to, uint256 _amount) external {
        totalSupply += _amount; balanceOf[_to] += _amount;
        emit Transfer(address(0), _to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        balanceOf[_from] -= _amount; totalSupply -= _amount;
        emit Transfer(_from, address(0), _amount);
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        allowance[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _to, uint256 _amount) external returns (bool) {
        balanceOf[msg.sender] -= _amount; balanceOf[_to] += _amount;
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool) {
        if (allowance[_from][msg.sender] != type(uint256).max)
            allowance[_from][msg.sender] -= _amount;
        balanceOf[_from] -= _amount; balanceOf[_to] += _amount;
        emit Transfer(_from, _to, _amount);
        return true;
    }
}
