import "contracts/lib/Token.sol";
import "contracts/lib/PoolBalanceLib.sol";
import "contracts/pools/Pool.sol";
import "contracts/pools/xyk/XYKPoolFactory.sol";
import "contracts/pools/stableswap/StableSwapPoolFactory.sol";
import "contracts/pools/vc/VC.sol";
import "contracts/VaultStorage.sol";

struct BribeData {
    Token[] tokens;
    uint256[] rates;
    uint256[] userClaimable;
    uint256[] userRates;
}

struct GaugeData {
    address gauge;
    PoolData poolData;
    bool killed;
    uint256 totalVotes;
    uint256 userVotes;
    uint256 userClaimable;
    uint256 emissionRate;
    uint256 userEmissionRate;
    uint256 stakedValueInHubToken;
    uint256 userStakedValueInHubToken;
    uint256 averageInterestRatePerSecond;
    uint256 userInterestRatePerSecond;
    Token[] stakeableTokens;
    uint256[] stakedAmounts;
    uint256[] userStakedAmounts;
    Token[] underlyingTokens;
    uint256[] stakedUnderlying;
    uint256[] userUnderlying;
    BribeData[] bribes;
}

struct PoolData {
    address pool;
    string poolType;
    // lp tokens
    Token[] lpTokens;
    uint256[] mintedLPTokens;
    // tokens constituting the lp token
    Token[] listedTokens;
    uint256[] reserves;
    int256 logYield;
    bytes poolParams;
}

contract VelocoreLens is VaultStorage {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for uint256;
    using SafeCast for int256;
    using PoolBalanceLib for PoolBalance;
    using TokenLib for Token;

    IVC immutable vc;
    XYKPoolFactory immutable factory;
    StableSwapPoolFactory immutable factory2;
    Token immutable usdc;
    VelocoreLens immutable lens;

    using PoolBalanceLib for bytes32;

    function spotPrice(ISwap swap, Token base, Token quote, uint256 baseAmount) public returns (uint256) {
        Token[] memory tokens = new Token[](2);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);
        XYKPool(address(swap)).setFeeToZero();
        ops[0].poolId = bytes32(bytes1(0x00)) | bytes32(uint256(uint160(address(swap))));
        ops[0].tokenInformations = new bytes32[](tokens.length);
        ops[0].data = "";

        tokens[0] = base;
        tokens[1] = quote;
        ops[0].tokenInformations[0] = bytes32(bytes2(0x0000)) | bytes32(uint256(uint128(baseAmount)));
        ops[0].tokenInformations[1] =
            bytes32(bytes2(0x0101)) | bytes32(uint256(uint128(uint256(int256(type(int128).max)))));
        try IVault(address(this)).query(address(this), tokens, new int128[](2), ops) returns (int128[] memory a) {
            return uint128(a[1] > 0 ? a[1] : int128(0));
        } catch {
            return 0;
        }
    }

    function spotPrice(Token base, Token quote, uint256 amount) public returns (uint256) {
        if (base == quote) {
            return amount;
        }
        if (address(factory2.pools(base, quote)) != address(0)) {
            return spotPrice(factory.pools(base, quote), base, quote, amount);
        } else if (address(factory.pools(base, quote)) != address(0)) {
            return spotPrice(factory.pools(base, quote), base, quote, amount);
        } else if (factory.isPool(XYKPool(base.addr()))) {
            return spotPrice(
                ISwap(base.addr()).underlyingTokens(base)[0],
                quote,
                spotPrice(ISwap(base.addr()), base, ISwap(base.addr()).underlyingTokens(base)[0], amount)
            );
        } else if (factory2.isPool(StableSwapPool(base.addr()))) {
            return spotPrice(
                ISwap(base.addr()).underlyingTokens(base)[0],
                quote,
                spotPrice(ISwap(base.addr()), base, ISwap(base.addr()).underlyingTokens(base)[0], amount)
            );
        } else if (address(factory.pools(base, NATIVE_TOKEN)) != address(0)) {
            return
                spotPrice(NATIVE_TOKEN, quote, spotPrice(factory.pools(base, NATIVE_TOKEN), base, NATIVE_TOKEN, amount));
        } else if (address(factory.pools(base, usdc)) != address(0)) {
            return spotPrice(usdc, quote, spotPrice(factory.pools(base, usdc), base, usdc, amount));
        } else if (address(factory.pools(base, toToken(vc))) != address(0)) {
            return spotPrice(toToken(vc), quote, spotPrice(factory.pools(base, toToken(vc)), base, toToken(vc), amount));
        }
        return 0;
    }

    function spotPrice(Token quote, Token[] memory tok, uint256[] memory amount) public returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < tok.length; i++) {
            sum += spotPrice(tok[i], quote, amount[i]);
        }
        return sum;
    }

    function userBalances(address user, Token[] calldata ts) public view returns (uint256[] memory balances) {
        balances = new uint256[](ts.length);
        for (uint256 i = 0; i < ts.length; i++) {
            balances[i] = ts[i].fromScaledBalance(_userBalances()[user][ts[i]]);
        }
    }

    constructor(
        Token usdc_,
        IVC vc_,
        XYKPoolFactory factory_,
        StableSwapPoolFactory sFactory_,
        VelocoreLens lens_
    ) {
        usdc = usdc_;
        vc = vc_;
        factory = factory_;
        factory2 = sFactory_;
        lens = lens_;
    }

    function wombatGauges(address user) external returns (GaugeData[] memory gaugeDataArray) {
        StableSwapPool[] memory pools = factory2.getPools(0, 100);
        gaugeDataArray = new GaugeData[](
                pools.length
        );
        for (uint256 i = 0; i < pools.length; i++) {
            _queryGauge(address(pools[i]), user, gaugeDataArray[i]);
        }
    }

    function canonicalPools(address user, uint256 begin, uint256 maxLength)
        external
        returns (GaugeData[] memory gaugeDataArray)
    {
        XYKPool[] memory pools = factory.getPools(0, begin + maxLength);
        gaugeDataArray = new GaugeData[](
            Math.min(
                maxLength,
                begin >= pools.length ? 0 : pools.length - begin
            )
        );
        for (uint256 i = begin; i < begin + maxLength && i < pools.length; i++) {
            _queryGauge(address(pools[i]), user, gaugeDataArray[i - begin]);
        }
    }

    function canonicalPoolLength() external returns (uint256) {
        return factory.poolsLength();
    }

    function queryGauge(address gauge, address user) external returns (GaugeData memory poolData) {
        _queryGauge(gauge, user, poolData);
    }

    function _queryGauge(address gauge, address user, GaugeData memory gaugeData) internal {
        GaugeInformation storage g = _e().gauges[IGauge(gauge)];
        _queryPool(IGauge(gauge).stakeableTokens()[0].addr(), gaugeData.poolData);
        gaugeData.gauge = gauge;
        gaugeData.killed = g.lastBribeUpdate == 1;
        gaugeData.totalVotes = g.totalVotes;
        gaugeData.userVotes = g.userVotes[user];
        if (_e().totalVotes > 0 && !gaugeData.killed) {
            gaugeData.emissionRate = (vc.emissionRate() * gaugeData.totalVotes) / _e().totalVotes;
            gaugeData.userEmissionRate = (gaugeData.emissionRate * IGauge(gauge).emissionShare(user)) / 1e18;
        }
        gaugeData.stakeableTokens = IGauge(gauge).stakeableTokens();
        gaugeData.userClaimable = _userClaimable(gauge, user);
        gaugeData.stakedAmounts = IGauge(gauge).stakedTokens();
        gaugeData.userStakedAmounts = IGauge(gauge).stakedTokens(user);
        for (uint256 i = 0; i < gaugeData.stakeableTokens.length; i++) {
            if (gaugeData.stakedAmounts[i] > 0) {
                uint256 spot =
                    lens.spotPrice(gaugeData.stakeableTokens[i], NATIVE_TOKEN, gaugeData.stakedAmounts[i] / 1000);
                gaugeData.stakedValueInHubToken += spot * 1000;
                gaugeData.userStakedValueInHubToken +=
                    (spot * gaugeData.userStakedAmounts[i] * 1000) / gaugeData.stakedAmounts[i];
            }
        }

        if (gaugeData.userStakedValueInHubToken > 0 && gaugeData.userEmissionRate > 0) {
            gaugeData.userInterestRatePerSecond = (
                lens.spotPrice(toToken(vc), NATIVE_TOKEN, gaugeData.userEmissionRate) * 1e18
            ) / gaugeData.userStakedValueInHubToken;
        }
        if (gaugeData.stakedValueInHubToken > 0 && gaugeData.emissionRate > 0) {
            gaugeData.averageInterestRatePerSecond = (
                lens.spotPrice(toToken(vc), NATIVE_TOKEN, gaugeData.emissionRate) * 1e18
            ) / gaugeData.stakedValueInHubToken;
        }

        uint256 len = 0;
        for (uint256 i = 0; i < gaugeData.stakeableTokens.length; i++) {
            len += ISwap(gaugeData.poolData.pool).underlyingTokens(gaugeData.stakeableTokens[i]).length;
        }
        gaugeData.underlyingTokens = new Token[](len);

        for (uint256 i = 0; i < gaugeData.stakeableTokens.length; i++) {
            Token[] memory ts = ISwap(gaugeData.poolData.pool).underlyingTokens(gaugeData.stakeableTokens[i]);
            for (uint256 j = 0; j < ts.length; j++) {
                gaugeData.underlyingTokens[--len] = ts[j];
            }
        }

        _fillUserUnderlyingAmounts(gaugeData.poolData.pool, user, gaugeData);

        _fillStakedUnderlyingAmounts(gaugeData.poolData.pool, gaugeData);

        if (!gaugeData.killed) {
            EnumerableSet.AddressSet storage bribes = g.bribes;
            gaugeData.bribes = new BribeData[](bribes.length());
            uint256 elapsed = g.lastBribeUpdate == 0 ? 0 : block.timestamp - g.lastBribeUpdate;
            for (uint256 i = 0; i < bribes.length(); i++) {
                gaugeData.bribes[i].tokens = IBribe(bribes.at(i)).bribeTokens(IGauge(gauge));
                gaugeData.bribes[i].rates = IBribe(bribes.at(i)).bribeRates(IGauge(gauge));
                gaugeData.bribes[i].userRates = new uint256[](
                    gaugeData.bribes[i].rates.length
                );
                if (gaugeData.totalVotes == 0) continue;
                for (uint256 j = 0; j < gaugeData.bribes[i].userRates.length; j++) {
                    gaugeData.bribes[i].userRates[j] =
                        (gaugeData.bribes[i].rates[j] * gaugeData.userVotes) / gaugeData.totalVotes;
                }

                gaugeData.bribes[i].userClaimable = new uint256[](
                    gaugeData.bribes[i].tokens.length
                );
                try IBribe(bribes.at(i)).velocore__bribe(IGauge(gauge), elapsed) returns (
                    Token[] memory bribeTokens,
                    int128[] memory deltaGauge,
                    int128[] memory deltaPool,
                    int128[] memory deltaExternal
                ) {
                    for (uint256 j = 0; j < bribeTokens.length; j++) {
                        uint256 netDelta = uint256(-int256(deltaGauge[j] + deltaPool[j] + deltaExternal[j]));
                        Token token = bribeTokens[j];
                        //require(deltaExternal[j] <= 0);
                        //_modifyPoolBalance(IBribe(bribes.at(i)), token, deltaGauge[j], deltaPool[j], deltaExternal[j]);
                        Rewards storage r = g.rewards[IBribe(bribes.at(i))][token];
                        if (g.totalVotes > 0) {
                            r.current += (netDelta * 1e18) / g.totalVotes;
                        }
                        gaugeData.bribes[i].userClaimable[j] =
                            ((r.current - r.snapshots[user]) * uint256(g.userVotes[user])) / 1e18;
                    }
                } catch {}
            }
        }
    }

    function _modifyPoolBalance(IPool pool, Token tok, int128 dGauge, int128 dPool, int128 dExternal) internal {
        _poolBalances()[pool][tok] = _poolBalances()[pool][tok].credit(tok.toScaledBalance(dGauge), tok.toScaledBalance(dPool));

        if (dExternal < 0) {
            tok.safeTransferFrom(address(pool), address(this), uint256(int256(-dExternal)));
        }
    }

    function _fillUserUnderlyingAmounts(address pool, address user, GaugeData memory gaugeData) internal {
        Token[] memory tokens = new Token[](
            gaugeData.underlyingTokens.length + gaugeData.stakeableTokens.length
        );

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);
        ops[0].poolId = bytes32(bytes1(0x00)) | bytes32(uint256(uint160(pool)));
        ops[0].tokenInformations = new bytes32[](tokens.length);
        ops[0].data = "";

        for (uint256 i = 0; i < gaugeData.underlyingTokens.length; i++) {
            tokens[i] = gaugeData.underlyingTokens[i];
            ops[0].tokenInformations[i] = bytes32(
                bytes32(bytes1(uint8(i))) | bytes32(bytes2(0x0001)) | bytes32(uint256(uint128(type(int128).max)))
            );
        }
        for (uint256 i = 0; i < gaugeData.stakeableTokens.length; i++) {
            tokens[i + gaugeData.underlyingTokens.length] = gaugeData.stakeableTokens[i];
            ops[0].tokenInformations[i + gaugeData.underlyingTokens.length] = bytes32(
                bytes32(bytes1(uint8(i + gaugeData.underlyingTokens.length))) | bytes32(bytes2(0x0000))
                    | bytes32(uint256(uint128(gaugeData.userStakedAmounts[i])))
            );
        }

        gaugeData.userUnderlying = new uint256[](
            gaugeData.underlyingTokens.length
        );
        try IVault(address(this)).query(user, tokens, new int128[](tokens.length), ops) returns (int128[] memory delta)
        {
            for (uint256 i = 0; i < gaugeData.underlyingTokens.length; i++) {
                if (delta[i] < 0) continue;
                gaugeData.userUnderlying[i] = uint256(int256(delta[i]));
            }
        } catch {}
    }

    function _fillStakedUnderlyingAmounts(address pool, GaugeData memory gaugeData) internal {
        Token[] memory tokens = new Token[](
            gaugeData.underlyingTokens.length + gaugeData.stakeableTokens.length
        );
        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        ops[0].poolId = bytes32(bytes1(0x00)) | bytes32(uint256(uint160(pool)));
        ops[0].tokenInformations = new bytes32[](tokens.length);
        ops[0].data = "";

        for (uint256 i = 0; i < gaugeData.underlyingTokens.length; i++) {
            tokens[i] = gaugeData.underlyingTokens[i];
            ops[0].tokenInformations[i] = bytes32(
                bytes32(bytes1(uint8(i))) | bytes32(bytes2(0x0001)) | bytes32(uint256(uint128(type(int128).max)))
            );
        }
        for (uint256 i = 0; i < gaugeData.stakeableTokens.length; i++) {
            tokens[i + gaugeData.underlyingTokens.length] = gaugeData.stakeableTokens[i];
            ops[0].tokenInformations[i + gaugeData.underlyingTokens.length] = bytes32(
                bytes32(bytes1(uint8(i + gaugeData.underlyingTokens.length))) | bytes32(bytes2(0x0000))
                    | bytes32(uint256(uint128(gaugeData.stakedAmounts[i])))
            );
        }

        gaugeData.stakedUnderlying = new uint256[](
            gaugeData.underlyingTokens.length
        );
        try IVault(address(this)).query(address(this), tokens, new int128[](tokens.length), ops) returns (
            int128[] memory delta
        ) {
            for (uint256 i = 0; i < gaugeData.underlyingTokens.length; i++) {
                if (delta[i] < 0) continue;
                gaugeData.stakedUnderlying[i] = uint256(int256(delta[i]));
            }
        } catch {}
    }

    function _userClaimable(address pool, address user) internal returns (uint256) {
        Token[] memory tokens = new Token[](1);
        tokens[0] = toToken(vc);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);
        ops[0].poolId = bytes32(bytes1(0x01)) | bytes32(uint256(uint160(pool)));
        ops[0].tokenInformations = new bytes32[](1);
        ops[0].data = "";

        ops[0].tokenInformations[0] = bytes32(0);

        try IVault(address(this)).query(user, tokens, new int128[](1), ops) returns (int128[] memory r) {
            return uint128(r[0]);
        } catch {
            return 0;
        }
    }

    function emissionRate(IGauge gauge) external returns (uint256) {
        GaugeInformation storage g = _e().gauges[IGauge(gauge)];
        return (vc.emissionRate() * g.totalVotes) / _e().totalVotes;
    }

    function getPoolBalance(address pool, Token t) external view returns (uint256) {
        return IVault(address(this)).getPoolBalance(pool, t);
    }

    function _queryPool(address pool, PoolData memory poolData) internal {
        poolData.pool = pool;
        poolData.poolType = ISwap(poolData.pool).swapType();
        poolData.listedTokens = ISwap(poolData.pool).listedTokens();
        poolData.reserves = new uint256[](poolData.listedTokens.length);
        for (uint256 i = 0; i < poolData.listedTokens.length; i++) {
            poolData.reserves[i] = IVault(address(this)).getPoolBalance(pool, poolData.listedTokens[i]);
        }
        poolData.lpTokens = ISwap(pool).lpTokens();
        poolData.mintedLPTokens = new uint256[](poolData.lpTokens.length);
        for (uint256 i = 0; i < poolData.mintedLPTokens.length; i++) {
            if (poolData.lpTokens[i].spec() == TokenSpec.ERC1155) {
                poolData.mintedLPTokens[i] =
                    type(uint128).max - _poolBalances()[IPool(pool)][poolData.lpTokens[i]].poolHalf();
            } else {
                poolData.mintedLPTokens[i] = poolData.lpTokens[i].totalSupply();
            }
        }
        try XYKPool(pool).getLogYieldEMA() returns (int256 yield) {
            poolData.logYield = yield;
        } catch (bytes memory) {}
        poolData.poolParams = IPool(pool).poolParams();
    }

    function queryPool(address pool) external returns (PoolData memory ret) {
        _queryPool(pool, ret);
    }
}
