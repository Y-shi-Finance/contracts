// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "contracts/lib/Token.sol";
import "contracts/lib/PoolBalanceLib.sol";
import "contracts/interfaces/IPool.sol";
import "contracts/interfaces/ISwap.sol";
import "contracts/interfaces/IConverter.sol";
import "contracts/interfaces/IVC.sol";
import "contracts/interfaces/IVault.sol";
import "contracts/interfaces/IFacet.sol";
import "contracts/VaultStorage.sol";
import "contracts/Common.sol";
import "contracts/pools/xyk/XYKPoolFactory.sol";
import "contracts/pools/stableswap/StableSwapPoolFactory.sol";
import "contracts/pools/constant-product/ConstantProductPoolFactory.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/Math.sol";


contract SwapHelperFacet2 is VaultStorage, IFacet, Common {
struct route {
    address from;
    address to;
    bool stable;
}
    using UncheckedMemory for Token[];
    using PoolBalanceLib for PoolBalance;
    using SafeCast for uint256;
    using SafeCast for int256;

    address immutable thisImplementation;
    XYKPoolFactory public immutable factory;
    StableSwapPoolFactory public immutable stableFactory;
    address immutable vc;

    constructor(address vc_, XYKPoolFactory factory_, StableSwapPoolFactory factory2_) {
        vc = vc_;
        factory = factory_;
        stableFactory = factory2_;
        thisImplementation = address(this);
    }

    /**
     * @dev called by AdminFacet.admin_addFacet().
     * doesnt get added to the routing table, hence the lack of access control.
     */

    function initializeFacet() external {
        _setFunction(
            SwapHelperFacet2(this).addLiquidity.selector,
            thisImplementation
        );
        _setFunction(
            SwapHelperFacet2(this).addLiquidityETH.selector,
            thisImplementation
        );
        _setFunction(
            SwapHelperFacet2(this).quoteAddLiquidity.selector,
            thisImplementation
        );
        _setFunction(
            SwapHelperFacet2(this).removeLiquidity.selector,
            thisImplementation
        );
        _setFunction(
            SwapHelperFacet2(this).removeLiquidityETH.selector,
            thisImplementation
        );
        _setFunction(
            SwapHelperFacet2(this).quoteRemoveLiquidity.selector,
            thisImplementation
        );
        _setFunction(
            SwapHelperFacet2(this).deposit.selector,
            thisImplementation
        );
        _setFunction(
            SwapHelperFacet2(this).withdraw.selector,
            thisImplementation
        );
    }

    function execute1(
        IPool pool,
        uint8 method,
        address t1,
        uint8 m1,
        int128 a1,
        bytes memory data
    ) public payable returns (int128[] memory) {
        Token[] memory tokens = new Token[](1);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokens[0] = t1 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t1));

        ops[0].poolId =
            bytes32(bytes1(method)) |
            bytes32(uint256(uint160(address(pool))));
        ops[0].tokenInformations = new bytes32[](1);
        ops[0].data = data;

        ops[0].tokenInformations[0] =
            bytes32(bytes1(0x00)) |
            bytes32(bytes2(uint16(m1))) |
            bytes32(uint256(uint128(uint256(int256(a1)))));
        return execute(tokens, new int128[](1), ops);
    }

    function query1(
        IPool pool,
        uint8 method,
        address t1,
        uint8 m1,
        int128 a1,
        bytes memory data
    ) public returns (int128[] memory) {
        Token[] memory tokens = new Token[](1);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokens[0] = t1 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t1));

        ops[0].poolId =
            bytes32(bytes1(method)) |
            bytes32(uint256(uint160(address(pool))));
        ops[0].tokenInformations = new bytes32[](1);
        ops[0].data = data;

        ops[0].tokenInformations[0] =
            bytes32(bytes1(0x00)) |
            bytes32(bytes2(uint16(m1))) |
            bytes32(uint256(uint128(uint256(int256(a1)))));
        return query(tokens, new int128[](1), ops);
    }

    function execute2(
        IPool pool,
        uint8 method,
        address t1,
        uint8 m1,
        int128 a1,
        address t2,
        uint8 m2,
        int128 a2,
        bytes memory data
    ) public payable returns (int128[] memory) {
        Token[] memory tokens = new Token[](2);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokens[0] = t1 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t1));
        tokens[1] = t2 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t2));

        ops[0].poolId =
            bytes32(bytes1(method)) |
            bytes32(uint256(uint160(address(pool))));
        ops[0].tokenInformations = new bytes32[](2);
        ops[0].data = data;

        ops[0].tokenInformations[0] =
            bytes32(bytes1(0x00)) |
            bytes32(bytes2(uint16(m1))) |
            bytes32(uint256(uint128(uint256(int256(a1)))));
        ops[0].tokenInformations[1] =
            bytes32(bytes1(0x01)) |
            bytes32(bytes2(uint16(m2))) |
            bytes32(uint256(uint128(uint256(int256(a2)))));
        return execute(tokens, new int128[](2), ops);
    }

    function query2(
        IPool pool,
        uint8 method,
        address t1,
        uint8 m1,
        int128 a1,
        address t2,
        uint8 m2,
        int128 a2,
        bytes memory data
    ) public returns (int128[] memory) {
        Token[] memory tokens = new Token[](2);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokens[0] = t1 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t1));
        tokens[1] = t2 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t2));

        ops[0].poolId =
            bytes32(bytes1(method)) |
            bytes32(uint256(uint160(address(pool))));
        ops[0].tokenInformations = new bytes32[](2);
        ops[0].data = data;

        ops[0].tokenInformations[0] =
            bytes32(bytes1(0x00)) |
            bytes32(bytes2(uint16(m1))) |
            bytes32(uint256(uint128(uint256(int256(a1)))));
        ops[0].tokenInformations[1] =
            bytes32(bytes1(0x01)) |
            bytes32(bytes2(uint16(m2))) |
            bytes32(uint256(uint128(uint256(int256(a2)))));
        return query(tokens, new int128[](2), ops);
    }

    function execute3(
        IPool pool,
        uint8 method,
        address t1,
        uint8 m1,
        int128 a1,
        address t2,
        uint8 m2,
        int128 a2,
        address t3,
        uint8 m3,
        int128 a3,
        bytes memory data
    ) public payable returns (int128[] memory) {
        Token[] memory tokens = new Token[](3);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokens[0] = t1 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t1));
        tokens[1] = t2 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t2));
        tokens[2] = t3 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t3));

        ops[0].poolId =
            bytes32(bytes1(method)) |
            bytes32(uint256(uint160(address(pool))));
        ops[0].tokenInformations = new bytes32[](3);
        ops[0].data = data;

        ops[0].tokenInformations[0] =
            bytes32(bytes1(0x00)) |
            bytes32(bytes2(uint16(m1))) |
            bytes32(uint256(uint128(uint256(int256(a1)))));
        ops[0].tokenInformations[1] =
            bytes32(bytes1(0x01)) |
            bytes32(bytes2(uint16(m2))) |
            bytes32(uint256(uint128(uint256(int256(a2)))));
        ops[0].tokenInformations[2] =
            bytes32(bytes1(0x02)) |
            bytes32(bytes2(uint16(m3))) |
            bytes32(uint256(uint128(uint256(int256(a3)))));
        return execute(tokens, new int128[](3), ops);
    }

    function query3(
        IPool pool,
        uint8 method,
        address t1,
        uint8 m1,
        int128 a1,
        address t2,
        uint8 m2,
        int128 a2,
        address t3,
        uint8 m3,
        int128 a3,
        bytes memory data
    ) public returns (int128[] memory) {
        Token[] memory tokens = new Token[](3);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokens[0] = t1 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t1));
        tokens[1] = t2 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t2));
        tokens[2] = t3 == address(0) ? NATIVE_TOKEN : toToken(IERC20(t3));

        ops[0].poolId =
            bytes32(bytes1(method)) |
            bytes32(uint256(uint160(address(pool))));
        ops[0].tokenInformations = new bytes32[](3);
        ops[0].data = data;

        ops[0].tokenInformations[0] =
            bytes32(bytes1(0x00)) |
            bytes32(bytes2(uint16(m1))) |
            bytes32(uint256(uint128(uint256(int256(a1)))));
        ops[0].tokenInformations[1] =
            bytes32(bytes1(0x01)) |
            bytes32(bytes2(uint16(m2))) |
            bytes32(uint256(uint128(uint256(int256(a2)))));
        ops[0].tokenInformations[2] =
            bytes32(bytes1(0x02)) |
            bytes32(bytes2(uint16(m3))) |
            bytes32(uint256(uint128(uint256(int256(a3)))));
        return query(tokens, new int128[](3), ops);
    }

    function execute(
        Token[] memory tokens,
        int128[] memory deposits,
        VelocoreOperation[] memory ops
    ) internal returns (int128[] memory ret) {
        bytes memory cd = abi.encodeWithSelector(
            IVault.execute.selector,
            tokens,
            deposits,
            ops
        );
        ret = new int128[](tokens.length);
        uint256 len = tokens.length * 32;
        assembly {
            let success := delegatecall(
                gas(),
                address(),
                add(cd, 32),
                mload(cd),
                0,
                0
            )

            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returndatacopy(ret, 32, add(32, len))
        }
    }

    function query(
        Token[] memory tokens,
        int128[] memory deposits,
        VelocoreOperation[] memory ops
    ) internal returns (int128[] memory ret) {
        bytes memory cd = abi.encodeWithSelector(
            IVault.query.selector,
            msg.sender,
            tokens,
            deposits,
            ops
        );
        ret = new int128[](tokens.length);
        uint256 len = tokens.length * 32;
        assembly {
            let success := delegatecall(
                gas(),
                address(),
                add(cd, 32),
                mload(cd),
                0,
                0
            )

            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returndatacopy(ret, 32, add(32, len))
        }
    }

    function _toToken(address a) internal pure returns (Token) {
        if (a == address(0)) return NATIVE_TOKEN;
        return toToken(IERC20(a));
    }

    function getPair(
        address t0,
        address t1,
        bool stable
    ) public view returns (address) {
        Token t0_ = toToken(IERC20(t0));
        Token t1_ = toToken(IERC20(t1));

        if (t0 == address(0)) t0_ = NATIVE_TOKEN;
        if (t1 == address(0)) t1_ = NATIVE_TOKEN;
        return _getPair(t0_, t1_, stable);
    }

    function _getPair(
        Token t0,
        Token t1,
        bool stable
    ) internal view returns (address) {
        if (stable) return address(stableFactory.pools(t0, t1));
        return address(factory.pools(t0, t1));
    }

    function allPairs(uint256 i) external view returns (address) {
        return address(factory.poolList(i));
    }

    function allPairsLength() external view returns (uint256) {
        return factory.poolsLength();
    }

    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        address pair = getPair(tokenA, tokenB, stable);
        int128[] memory r = query3(
            IPool(pair),
            0,
            tokenA,
            0,
            amountADesired.toInt256().toInt128(),
            tokenB,
            0,
            amountBDesired.toInt256().toInt128(),
            pair,
            0,
            type(int128).max,
            ""
        );
        return (int256(-r[0]).toUint256(), int256(-r[1]).toUint256(), int256(r[2]).toUint256());
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(to == msg.sender, "'to' must be msg.sender");
        require(deadline > block.timestamp, "deadline");
        address pair = getPair(tokenA, tokenB, stable);
        int128[] memory r = execute3(
            IPool(pair),
            0,
            tokenA,
            0,
            amountADesired.toInt256().toInt128(),
            tokenB,
            0,
            amountBDesired.toInt256().toInt128(),
            pair,
            0,
            type(int128).max,
            ""
        );
        return (int256(-r[0]).toUint256(), int256(-r[1]).toUint256(), int256(r[2]).toUint256());
    }

    function addLiquidityETH(
        address tokenA,
        bool stable,
        uint256 amountADesired,
        uint256 amountAMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountA, uint256 amountETH, uint256 liquidity)
    {
        require(to == msg.sender, "'to' must be msg.sender");
        require(deadline > block.timestamp, "deadline");
        address pair = getPair(tokenA, address(0), stable);
        int128[] memory r = execute3(
            IPool(pair),
            0,
            tokenA,
            0,
            amountADesired.toInt256().toInt128(),
            address(0),
            0,
            msg.value.toInt256().toInt128(),
            pair,
            0,
            type(int128).max,
            ""
        );
        return (int256(-r[0]).toUint256(), int256(-r[1]).toUint256(), int256(r[2]).toUint256());
    }

    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity
    ) external returns (uint256 amountA, uint256 amountB) {
        address pair = getPair(tokenA, tokenB, stable);
        int128[] memory r = query3(
            IPool(pair),
            0,
            tokenA,
            0,
            type(int128).max,
            tokenB,
            0,
            type(int128).max,
            pair,
            0,
            liquidity.toInt256().toInt128(),
            ""
        );
        return (int256(r[0]).toUint256(), int256(r[1]).toUint256());
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public returns (uint256 amountA, uint256 amountB) {
        require(to == msg.sender, "'to' must be msg.sender");
        require(deadline > block.timestamp, "deadline");
        address pair = getPair(tokenA, tokenB, stable);
        int128[] memory r = execute3(
            IPool(pair),
            0,
            tokenA,
            1,
            -amountAMin.toInt256().toInt128(),
            tokenB,
            1,
            -amountBMin.toInt256().toInt128(),
            pair,
            0,
            liquidity.toInt256().toInt128(),
            ""
        );
        return (int256(r[0]).toUint256(), int256(r[1]).toUint256());
    }

    function removeLiquidityETH(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public returns (uint256 amountToken, uint256 amountETH) {
        require(to == msg.sender, "'to' must be msg.sender");
        require(deadline > block.timestamp, "deadline");
        address pair = getPair(token, address(0), stable);
        int128[] memory r = execute3(
            IPool(pair),
            0,
            token,
            1,
            -amountTokenMin.toInt256().toInt128(),
            address(0),
            1,
            -amountETHMin.toInt256().toInt128(),
            pair,
            0,
            liquidity.toInt256().toInt128(),
            ""
        );
        return (int256(r[0]).toUint256(), int256(r[1]).toUint256());
    }

    function deposit(address p, uint256 a) external {
        execute2(IPool(p),0, p, 0, a.toInt256().toInt128(), vc, 0, 0, "");
    }
    function withdraw(address p, uint256 a) external {
        execute2(IPool(p),0,p, 0, -a.toInt256().toInt128(), vc, 0, 0, "");
    }
}
