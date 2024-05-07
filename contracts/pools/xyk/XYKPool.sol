// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "openzeppelin/utils/math/Math.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import {ud60x18, intoUint256, exp2, log2, convert, pow} from "@prb/math/src/UD60x18.sol";
import "contracts/lib/Token.sol";
import "contracts/lib/UncheckedMemory.sol";
import "contracts/lib/PoolBalanceLib.sol";
import {rpow} from "contracts/lib/RPow.sol";
import "contracts/pools/SingleTokenGauge.sol";

/**
 * @dev a pool with weighted geometric average as its invariant, aka Balancer weighted pool.
 * Please refer to the url below for detailed mathematical explanation.
 * https://velocore.gitbook.io/velocore-v2/technical-docs/pool-specifics/generalized-cpmm
 *
 * There is two implementation of the same mathematical function. one in this contract, and another in ConstantProductLibrary.
 * they were separated to make compiled bytecode less than 24kb.
 *
 * one implementation uses integer division; they are cheap and accurate, but prone to overflows, especially when weights are high.
 * one implementation uses addition and substraction over logarithm; they are expensive and inaccurate, but can handle far more ranges.
 *
 * this contract is the first one. it falls back to the second one (ConstantProductLibrary) when neccesary.
 *
 */

contract XYKPool is SingleTokenGauge, PoolWithLPToken, ISwap, IBribe {
    using UncheckedMemory for uint256[];
    using UncheckedMemory for int128[];
    using UncheckedMemory for Token[];
    using SafeCast for int256;
    using SafeCast for uint256;
    using TokenLib for Token;

    event FeeChanged(uint256 fee1e18);
    event DecayChanged(uint256 decay);

    Token public immutable token0;
    Token public immutable token1;
    uint256 internal immutable _3token_i_0;
    uint256 internal immutable _3token_i_1;
    uint256 internal immutable _3token_i_lp;

    uint32 public decayRate;
    uint32 public fee1e9;
    uint32 public lastWithdrawTimestamp;
    uint32 lastTradeTimestamp;
    uint128 public feeMultiplier;
    uint8 internal immutable _lpDecimals;
    int256 public index;
    int256 lastIndex;
    int256 logYieldEMA;

    function getLogYieldEMA() external view returns (int256) {
        int256 indexNew = ((_invariant() * 1e18) / (totalSupply() + 2))
            .toInt256();
        if (lastTradeTimestamp != block.timestamp) {
            int256 an = int256(
                rpow(
                    0.999983955055097432543272791e27,
                    block.timestamp - lastTradeTimestamp,
                    1e27
                )
            );
            int256 logYield = (int256(
                intoUint256(log2(ud60x18(uint256(indexNew * 1e27))))
            ) - int256(intoUint256(log2(ud60x18(uint256(lastIndex * 1e27)))))) /
                int256(block.timestamp - lastTradeTimestamp);
            return (logYieldEMA * an + (1e27 - an) * logYield) / 1e27;
        }
        return logYieldEMA;
    }
    function floorDiv(int256 a, int256 b) internal pure returns (int256) {
        uint256 a_ = SignedMath.abs(a);
        uint256 b_ = SignedMath.abs(b);
        if ((a > 0) == (b > 0)) {
            return SafeCast.toInt256(a_ / b_);
        } else {
            return -SafeCast.toInt256(Math.ceilDiv(a_, b_));
        }
    }

    function ceilDiv(int256 a, int256 b) internal pure returns (int256) {
        uint256 a_ = SignedMath.abs(a);
        uint256 b_ = SignedMath.abs(b);
        if ((a > 0) == (b > 0)) {
            return SafeCast.toInt256(Math.ceilDiv(a_, b_));
        } else {
            return -SafeCast.toInt256(a_ / b_);
        }
    }

    function setDecay(uint256 decayRate_) external authenticate {
        decayRate = uint32(decayRate_);
        emit DecayChanged(decayRate);
    }

    function setFee(uint256 fee1e9_, uint256 decayRate_) external authenticate {
        require(fee1e9 <= 0.1e9);
        fee1e9 = uint32(fee1e9_);
        emit FeeChanged(fee1e9 * uint256(1e8));
    }

    constructor(
        IVault vault_,
        string memory _name,
        string memory _symbol,
        Token t0,
        Token t1,
        uint32 fee1e9_,
        uint32 decay
    ) SingleTokenGauge(vault_, toToken(this), this) {
        decayRate = decay;
        fee1e9 = fee1e9_;
        index = 1e18;
        lastIndex = 1e18;
        PoolWithLPToken._initialize(_name, _symbol);
        emit FeeChanged(fee1e9 * uint256(1e8));
        emit DecayChanged(decayRate);
        token0 = t0;
        token1 = t1;
        uint256 ilp;
        uint256 i0;
        uint256 i1;
        if (toToken(this) < t0) {
            ilp = 0;
            i0 = 1;
            i1 = 2;
        } else if (toToken(this) < t1) {
            ilp = 1;
            i0 = 0;
            i1 = 2;
        } else {
            ilp = 2;
            i0 = 0;
            i1 = 1;
        }
        _3token_i_0 = i0;
        _3token_i_1 = i1;
        _3token_i_lp = ilp;

        _lpDecimals = (t0.decimals() + t1.decimals()) / 2;
    }

    // positive amount => pool receives, user gives
    // negative amount => user receives, pool gives
    // type(int256).max => to be computed

    event Sync(uint112 reserve0, uint112 reserve1);

    function velocore__execute(
        address user,
        Token[] calldata t,
        int128[] memory r,
        bytes calldata
    )
        external
        onlyVault
        returns (int128[] memory deltaGauge, int128[] memory deltaPool)
    {
        deltaGauge = new int128[](t.length);
        deltaPool = new int128[](t.length);
        (int256 a_0, int256 a_1, ) = getReserves();
        emit Sync(uint112(uint256(a_0)), uint112(uint256(a_1)));
        a_0 += 1;
        a_1 += 1;

        if (lastWithdrawTimestamp != block.timestamp) {
            feeMultiplier = 1e9;
        }

        if (!vault.emissionStarted()) {
            int256 indexNew = ((_invariant() * 1e18) / (totalSupply() + 1))
                .toInt256();
            if (
                lastTradeTimestamp != block.timestamp && lastIndex != indexNew
            ) {
                int256 an = int256(
                    rpow(
                        0.999983955055097432543272791e27,
                        block.timestamp - lastTradeTimestamp,
                        1e27
                    )
                );
                int256 logYield = (int256(
                    intoUint256(log2(ud60x18(uint256(indexNew * 1e27))))
                ) -
                    int256(
                        intoUint256(log2(ud60x18(uint256(lastIndex * 1e27))))
                    )) / int256(block.timestamp - lastTradeTimestamp);
                logYieldEMA =
                    (logYieldEMA * an + (1e27 - an) * logYield) /
                    1e27;
                lastIndex = indexNew;
                lastTradeTimestamp = uint32(block.timestamp);
            }
            index = indexNew;
        }

        if (t.length == 3) {
            require(
                t.u(_3token_i_lp) == toToken(this) &&
                    t.u(_3token_i_0) == token0 &&
                    t.u(_3token_i_1) == token1
            );

            int256 r_lp = r.u(_3token_i_lp);
            int256 r_0 = r.u(_3token_i_0);
            int256 r_1 = r.u(_3token_i_1);

            if (r_lp != type(int128).max) {
                if (r_0 != type(int128).max) {
                    r_1 = _exchange_for_t1(
                        a_0,
                        a_1,
                        r_0,
                        floorDiv(r_lp * index, 1e18),
                        int256(uint256(fee1e9 * feeMultiplier))
                    );
                } else if (r_1 != type(int128).max) {
                    r_0 = _exchange_for_t0(
                        a_0,
                        a_1,
                        r_1,
                        floorDiv(r_lp * index, 1e18),
                        int256(uint256(fee1e9 * feeMultiplier))
                    );
                } else {
                    (r_0, r_1) = _exchange_from_lp(
                        a_0,
                        a_1,
                        floorDiv(r_lp * index, 1e18)
                    );
                }
            } else {
                require(r_0 != type(int128).max || r_1 != type(int128).max);
                if (r_0 == type(int128).max) {
                    r_0 = (r_1 * (a_0)) / (a_1);
                } else if (r_1 == type(int128).max) {
                    r_1 = (r_0 * (a_1)) / (a_0);
                }
                r_lp = ceilDiv(
                    _exchange_for_lp(
                        a_0,
                        a_1,
                        r_0,
                        r_1,
                        int256(uint256(fee1e9 * feeMultiplier))
                    ) * 1e18,
                    index
                );
            }
            deltaPool.u(_3token_i_0, r_0.toInt128());
            deltaPool.u(_3token_i_1, r_1.toInt128());
            deltaPool.u(_3token_i_lp, r_lp.toInt128());
            _handleSwap(user, r_lp, r_0, r_1);
            return (deltaGauge, deltaPool);
        } else if (t.length == 2) {
            require(
                (r.u(0) == type(int128).max) != (r.u(1) == type(int128).max)
            );

            uint256 i_lp = 2;
            uint256 i_0 = 2;
            uint256 i_1 = 2;

            Token tt = t.u(0);
            if (tt == toToken(this)) i_lp = 0;
            else if (tt == token0) i_0 = 0;
            else if (tt == token1) i_1 = 0;
            else revert("unsupported token");

            tt = t.u(1);
            if (tt == toToken(this)) i_lp = 1;
            else if (tt == token0) i_0 = 1;
            else if (tt == token1) i_1 = 1;
            else revert("unsupported token");

            int256 r_lp = i_lp == 2 ? int256(0) : r.u(i_lp);
            int256 r_0 = i_0 == 2 ? int256(0) : r.u(i_0);
            int256 r_1 = i_1 == 2 ? int256(0) : r.u(i_1);

            if (r_lp == type(int128).max) {
                r_lp = ceilDiv(
                    _exchange_for_lp(
                        a_0,
                        a_1,
                        r_0,
                        r_1,
                        int256(uint256(fee1e9 * feeMultiplier))
                    ) * 1e18,
                    index
                );
            } else if (r_1 == type(int128).max) {
                r_1 = _exchange_for_t1(
                    a_0,
                    a_1,
                    r_0,
                    floorDiv(r_lp * index, 1e18),
                    int256(uint256(fee1e9 * feeMultiplier))
                );
            } else {
                r_0 = _exchange_for_t0(
                    a_0,
                    a_1,
                    r_1,
                    floorDiv(r_lp * index, 1e18),
                    int256(uint256(fee1e9 * feeMultiplier))
                );
            }

            if (i_lp != 2) {
                deltaPool.u(i_lp, r_lp.toInt128());
            } else {
                require(r_lp == 0);
            }

            if (i_0 != 2) {
                deltaPool.u(i_0, r_0.toInt128());
            } else {
                require(r_0 == 0);
            }

            if (i_1 != 2) {
                deltaPool.u(i_1, r_1.toInt128());
            } else {
                require(r_1 == 0);
            }

            _handleSwap(user, r_lp, r_0, r_1);
            return (deltaGauge, deltaPool);
        } else {
            revert("unsupported operation");
        }
    }

    function getReserves() public view returns (int256, int256, uint256) {
        return (
            _getPoolBalance(token0).toInt256(),
            _getPoolBalance(token1).toInt256(),
            block.timestamp
        );
    }

    function _exchange(
        int256 a_0,
        int256 a_1,
        int256 b_1,
        int256 d_k,
        int256 fee
    ) internal returns (int256) {
        int256 a_k = Math
            .sqrt((a_0.toUint256()) * (a_1.toUint256()), Math.Rounding.Up)
            .toInt256();
        int256 b_k = a_k - d_k;
        require(b_k > 0);

        if (a_k <= b_k) {
            b_1 -= (SignedMath.max(((a_k * b_1) / b_k) - a_1, 0) * fee) / 1e18;
        } else if (a_k >= b_k) {
            b_1 -= (SignedMath.max(b_1 - ((b_k * a_1) / a_k), 0) * fee) / 1e18;
        }

        int256 b_0 = ceilDiv(b_k ** 2, b_1);

        if (a_k <= b_k) {
            b_0 +=
                (SignedMath.max(((a_k * b_0) / b_k) - a_0, 0) * fee) /
                (1e18 - fee);
        } else if (a_k > b_k) {
            b_0 +=
                (SignedMath.max(b_0 - ((b_k * a_0) / a_k), 0) * fee) /
                (1e18 - fee);
        }

        return b_0 - a_0;
    }

    function _exchange_for_t0(
        int256 a_0,
        int256 a_1,
        int256 r_1,
        int256 r_lp,
        int256 fee
    ) internal returns (int256) {
        return _exchange(a_0, a_1, a_1 + r_1, r_lp, fee);
    }

    function _exchange_for_t1(
        int256 a_0,
        int256 a_1,
        int256 r_0,
        int256 r_lp,
        int256 fee
    ) internal returns (int256) {
        return _exchange(a_1, a_0, a_0 + r_0, r_lp, fee);
    }

    function _exchange_for_lp(
        int256 a_0,
        int256 a_1,
        int256 r_0,
        int256 r_1,
        int256 fee
    ) internal returns (int256) {
        int256 b_0 = a_0 + r_0;
        int256 b_1 = a_1 + r_1;

        int256 a_k = Math
            .sqrt((a_0 * a_1).toUint256(), Math.Rounding.Up)
            .toInt256();
        int256 b_k = invariant(b_0, b_1);

        if (a_k <= b_k) {
            b_0 -= (SignedMath.max(((a_k * b_0) / b_k) - a_0, 0) * fee) / 1e18;
            b_1 -= (SignedMath.max(((a_k * b_1) / b_k) - a_1, 0) * fee) / 1e18;
        } else if (a_k > b_k) {
            b_0 -= (SignedMath.max(b_0 - ((b_k * a_0) / a_k), 0) * fee) / 1e18;
            b_1 -= (SignedMath.max(b_1 - ((b_k * a_1) / a_k), 0) * fee) / 1e18;
        }
        return a_k - invariant(b_0, b_1);
    }

    function _exchange_from_lp(
        int256 a_0,
        int256 a_1,
        int256 r_lp
    ) internal returns (int256, int256) {
        Math.Rounding r = r_lp > 0 ? Math.Rounding.Up : Math.Rounding.Down;
        int256 inv = Math
            .sqrt((a_0.toUint256()) * (a_1.toUint256()), r)
            .toInt256();
        return (ceilDiv(-((a_0) * r_lp), inv), ceilDiv(-((a_1) * r_lp), inv));
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(
        address indexed sender,
        uint amount0,
        uint amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );

    function _handleSwap(
        address user,
        int256 rlp,
        int256 r0,
        int256 r1
    ) internal {
        if (rlp > 0) {
            emit Burn(user, uint256(-int256(r0)), uint256(-int256(r1)), user);
            _simulateBurn(uint256(int256(rlp)));
            uint256 inv = _invariant();
            uint256 d = (inv - uint256(int256(rlp)));
            feeMultiplier = uint128((feeMultiplier * inv) / Math.max(1, d));
        } else if (rlp < 0) {
            emit Mint(user, uint256(int256(r0)), uint256(int256(r1)));
            _simulateMint(uint256(-int256(rlp)));
        } else {
            uint256 a0i;
            uint256 a1i;
            uint256 a0o;
            uint256 a1o;
            if (r0 > 0) {
                a0i = uint256(int256(r0));
            } else {
                a0o = uint256(int256(-r0));
            }
            if (r1 > 0) {
                a1i = uint256(int256(r1));
            } else {
                a1o = uint256(int256(-r1));
            }
            emit Swap(user, a0i, a1i, a0o, a1o, user);
        }
    }

    function poolBalances() public view returns (uint256[] memory) {
        return _getPoolBalances(relevantTokens());
    }

    function relevantTokens() public view virtual returns (Token[] memory) {
        Token[] memory ret = new Token[](3);
        unchecked {
            ret.u(0, toToken(this));
            ret.u(1, token0);
            ret.u(2, token1);
        }
        return ret;
    }

    function invariant(int256 a, int256 b) internal pure returns (int256) {
        uint256 a_ = a.toUint256();
        uint256 b_ = b.toUint256();
        return invariant(a_, b_).toInt256();
    }

    function invariant(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.sqrt(a * b);
    }

    function _invariant() internal view virtual returns (uint256) {
        (int256 a_0, int256 a_1, ) = getReserves();
        return invariant(a_0 + 1, a_1 + 1).toUint256();
    }

    function _excessInvariant() internal view virtual returns (uint256) {
        uint256 minted = Math.ceilDiv(
            (totalSupply() + 1) * index.toUint256(),
            1e18
        );
        (int256 a_0, int256 a_1, ) = getReserves();
        uint256 actual = _invariant();
        return actual < minted ? 0 : actual - minted;
    }

    function listedTokens() public view override returns (Token[] memory) {
        Token[] memory ret = new Token[](2);
        unchecked {
            ret.u(0, token0);
            ret.u(1, token1);
        }
        return ret;
    }

    function swapType() external view override returns (string memory) {
        return "cpmm";
    }

    function lpTokens() public view override returns (Token[] memory ret) {
        ret = new Token[](1);
        ret[0] = toToken(this);
    }

    function poolParams()
        external
        view
        override(IPool, Pool)
        returns (bytes memory)
    {
        uint256[] memory r = new uint256[](2);
        r[0] = 1;
        r[1] = 1;
        return abi.encode(fee1e9 * uint256(1e9), r);
    }

    function decimals() external view override returns (uint8) {
        return _lpDecimals;
    }

    function velocore__bribe(
        IGauge gauge,
        uint256 elapsed
    )
        external
        onlyVault
        returns (
            Token[] memory bribeTokens,
            int128[] memory deltaGauge,
            int128[] memory deltaPool,
            int128[] memory deltaExternal
        )
    {
        require(address(gauge) == address(this));
        bribeTokens[0] = toToken(this);
        deltaGauge = new int128[](1);
        deltaPool = new int128[](1);
        deltaExternal = new int128[](1);

        if (IVault(vault).emissionStarted()) {
            uint256 decay = 2 ** 32 - rpow(decayRate, elapsed, 2 ** 32);
            uint256 decayed = (_excessInvariant() * 1e18 / uint256(index) * decay) / 2 ** 32;

            bribeTokens = new Token[](1);
            deltaPool.u(0, -decayed.toInt256().toInt128());
        }
    }

    function bribeTokens(IGauge gauge) external view returns (Token[] memory) {
        Token v = toToken(this);
        assembly {
            mstore(0, 0x20)
            mstore(0x20, 1)
            mstore(0x40, v)
            return(0, 0x60)
        }
    }

    function bribeRates(IGauge gauge) external view returns (uint256[] memory) {
        uint256 v;
        unchecked {
            v = address(gauge) == address(this)
                ? (_excessInvariant() * 1e18 / uint256(index) * (2 ** 32 - uint256(decayRate))) /
                    2 ** 32
                : 0;
        }
        assembly {
            mstore(0, 0x20)
            mstore(0x20, 1)
            mstore(0x40, v)
            return(0, 0x60)
        }
    }

    function underlyingTokens(
        Token tok
    ) external view returns (Token[] memory) {
        require(tok == toToken(this));
        return listedTokens();
    }

    function setFeeToZero() external onlyVault {
        feeMultiplier = 0;
        fee1e9 = 0;
    }
}
