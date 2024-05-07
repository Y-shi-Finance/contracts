// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../Satellite.sol";
import "./XYKPool.sol";

contract XYKPoolFactory is Satellite {
    event PoolCreated(XYKPool indexed pool, Token t1, Token t2);

    using TokenLib for Token;
    using UncheckedMemory for Token[];
    using UncheckedMemory for uint256[];

    uint32 fee1e9;
    uint32 decay = 4294955811;

    XYKPool[] public poolList;
    mapping(Token => mapping(Token => XYKPool)) public pools;
    mapping(XYKPool => bool) public isPool;

    event FeeChanged(uint256 fee1e18);
    event DecayChanged(uint256 decay);

    function setFee(uint32 fee1e9_) external authenticate {
        fee1e9 = fee1e9_;
        require(fee1e9 <= 0.1e9);
        emit FeeChanged(fee1e9 * uint256(1e8));
    }

    function setDecay(uint32 decay_) external authenticate {
        decay = decay_;
        emit DecayChanged(decay_);
    }

    function getPools(uint256 begin, uint256 maxLength) external view returns (XYKPool[] memory pools) {
        uint256 len = poolList.length <= begin ? 0 : Math.min(poolList.length - begin, maxLength);
        pools = new XYKPool[](len);
        unchecked {
            for (uint256 i = begin; i < begin + len; i++) {
                pools[i] = poolList[i];
            }
        }
    }

    function poolsLength() external view returns (uint256) {
        return poolList.length;
    }

    constructor(IVault vault_) Satellite(vault_, address(this)) {
    }

    function deploy(Token quoteToken, Token baseToken) external returns (XYKPool) {
        require(!(baseToken == quoteToken));
        require(address(pools[quoteToken][baseToken]) == address(0));
        if (!(quoteToken < baseToken)) {
            (quoteToken, baseToken) = (baseToken, quoteToken);
        }

        XYKPool ret = new XYKPool(
            vault,
            string(abi.encodePacked("BladeSwap LP: ", quoteToken.symbol(), " + ", baseToken.symbol())),
            string(abi.encodePacked(quoteToken.symbol(), "-", baseToken.symbol(), "-VLP")),
            quoteToken,
            baseToken,
            fee1e9,
            decay
        );

        poolList.push(ret);
        isPool[ret] = true;
        pools[baseToken][quoteToken] = ret;
        pools[quoteToken][baseToken] = ret;
        emit PoolCreated(ret, quoteToken, baseToken);
        return ret;
    }
}
