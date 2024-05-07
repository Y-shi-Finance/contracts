pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 _decimals = 18;
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function setDecimals(uint8 d) public {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
