// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../Satellite.sol";
import "./StableSwapPool.sol";

contract StableSwapPoolFactory is Satellite {
    event PoolCreated(StableSwapPool indexed pool, Token t1, Token t2);

    using TokenLib for Token;
    using UncheckedMemory for Token[];
    using UncheckedMemory for uint256[];

    uint32 fee1e9;
    uint32 decay = 4294955811;

    StableSwapPool[] public poolList;
    mapping(Token => mapping(Token => StableSwapPool)) public pools;
    mapping(StableSwapPool => bool) public isPool;

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

    function getPools(uint256 begin, uint256 maxLength) external view returns (StableSwapPool[] memory pools) {
        uint256 len = poolList.length <= begin ? 0 : Math.min(poolList.length - begin, maxLength);
        pools = new StableSwapPool[](len);
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

    function deploy(Token quoteToken, Token baseToken) external authenticate returns (StableSwapPool) {
        require(!(baseToken == quoteToken));
        require(address(pools[quoteToken][baseToken]) == address(0));
        if (!(quoteToken < baseToken)) {
            (quoteToken, baseToken) = (baseToken, quoteToken);
        }

        StableSwapPool ret = new StableSwapPool(
            vault,
            string(abi.encodePacked("BladeSwap Stable LP: ", quoteToken.symbol(), " + ", baseToken.symbol())),
            string(abi.encodePacked(quoteToken.symbol(), "-", baseToken.symbol(), "-SLP")),
            quoteToken,
            baseToken,
            fee1e9,
            decay,
            2000
        );

        poolList.push(ret);
        isPool[ret] = true;
        pools[baseToken][quoteToken] = ret;
        pools[quoteToken][baseToken] = ret;
        emit PoolCreated(ret, quoteToken, baseToken);
        return ret;
    }
}
