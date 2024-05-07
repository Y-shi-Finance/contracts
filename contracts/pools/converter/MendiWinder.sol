// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/IERC20.sol";

import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/token/ERC1155/IERC1155.sol";
import "openzeppelin/token/ERC1155/extensions/ERC1155Supply.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC721/extensions/IERC721Metadata.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "../Pool.sol";

uint256 constant WIND = 0;
uint256 constant UNWIND = 1;

uint8 constant CONVERT = 2;
uint8 constant EVERYTHING = 3;

interface IWETH9 is IERC20 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

interface CToken is IERC20 {
    function mint(uint256) external;

    function mint() external payable;

    function repayBorrow(uint256) external;

    function repayBorrow() external payable;

    function redeem(uint256) external;

    function borrow(uint256) external;

    function underlying() external view returns (address);

    function borrowBalanceCurrent(address) external returns (uint256);
}

interface Comptroller {
    function markets(address) external view returns (bool, uint256, uint256);

    function getAllMarkets() external view returns (CToken[] memory);
}

contract MendiWinder is Pool {
    using SafeCast for uint256;
    using SafeCast for int256;
    using TokenLib for Token;

    IWETH9 immutable weth;
    Comptroller immutable comptroller;
    address immutable thisImplementation;

    constructor(Comptroller comptroller_, IWETH9 weth_, IVault vault) Pool(vault, address(this), address(this)) {
        weth = weth_;
        comptroller = comptroller_;
        thisImplementation = address(this);
    }

    function velocore__convert(address user, Token[] calldata tokens, int128[] memory inputs, bytes calldata data)
        external
        onlyVault
    {
        require(user == address(this));
        (uint256 command, uint256 underlyingAmount, CToken cToken) = abi.decode(data, (uint256, uint256, CToken));

        if (command == WIND) _wind(cToken, underlyingAmount);
        else if (command == UNWIND) _unwind(cToken);

        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].transferFrom(address(this), msg.sender, int256(inputs[i]).toUint256());
        }
    }

    function _wind(CToken cToken, uint256 targetDeposit) internal {
        (, uint256 collateralFactor_e18,) = comptroller.markets(address(cToken));
        uint256 targetSupply = (targetDeposit * 1e18) / (1e18 - ((collateralFactor_e18 * 98) / 100));
        uint256 targetBorrow = targetSupply - targetDeposit;
        if (address(this).balance > 0) {
            weth.deposit{value: address(this).balance}();
        }
        IERC20(cToken.underlying()).approve(address(cToken), targetSupply);
        cToken.mint(targetSupply);
        cToken.borrow(targetBorrow);
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) weth.withdraw(wethBalance);
    }

    function _unwind(CToken cToken) internal {
        if (address(this).balance > 0) {
            weth.deposit{value: address(this).balance}();
        }
        uint256 borrowBalance = cToken.borrowBalanceCurrent(address(this));
        if (borrowBalance != 0) {
            IERC20(cToken.underlying()).approve(address(cToken), borrowBalance);
            cToken.repayBorrow(borrowBalance);
        }
        uint256 balance = cToken.balanceOf(address(this));
        if (balance > 0) {
            cToken.redeem(balance);
        }
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) weth.withdraw(wethBalance);
    }

    /*
    function _unwind() internal {
        Ctoken[] memory markets = comptroller.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            CToken cToken = markets[i];
            uint256 borrowBalance = cToken.borrowBalanceCurrent(address(this));
            if (borrowBalance != 0) {
                if (cToken == mETH) {
                    cToken.repay{value: borrowBalance}();
                } else {
                    cToken.underlying().approve(address(cToken), borrowBalance);
                    cToken.repay(borrowBalance);
                }
            }
        }
        
        for (uint256 i = 0; i < markets.length; i++) {
            CToken cToken = markets[i];
            uint256 balance = cToken.balanceOf(address(this));
            if (balance > 0) {
                cToken.redeem(balance);
            }
        }
    }
    */
    function wind(CToken cToken, uint256 underlyingAmount) external expectCallback {
        address underlying = cToken.underlying();
        if (underlying == address(weth)) underlying = address(0);
        vault.execute1(
            address(this),
            CONVERT,
            underlying,
            EVERYTHING,
            underlyingAmount.toInt256().toInt128(),
            abi.encode(WIND, underlyingAmount, cToken)
        );
    }

    function unwind(CToken cToken) external expectCallback {
        address underlying = cToken.underlying();
        if (underlying == address(weth)) underlying = address(0);
        vault.execute1(address(this), CONVERT, underlying, EVERYTHING, 0, abi.encode(UNWIND, 0, cToken));
    }

    modifier expectCallback() {
        address originalImplementation;
        address thisImplementation_ = thisImplementation;
        assembly {
            originalImplementation := sload(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)
            sstore(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc, thisImplementation_)
        }
        _;
        assembly {
            sstore(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc, originalImplementation)
        }
    }

    receive() external payable {}
}
