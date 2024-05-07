// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "script/Deploy.generic.s.sol";
import "contracts/MockERC20.sol";
import "contracts/pools/constant-product/ConstantProductPool.sol";
import {StableSwapPoolFactory, StableSwapPool} from "contracts/pools/stableswap/StableSwapPoolFactory.sol";
import "contracts/pools/constant-product/ConstantProductLibrary.sol";
import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "forge-std/console.sol";

contract MockVC is IVC, ERC20 {
    constructor() ERC20("lol", "lol") {}

    function notifyMigration(uint128 n) external {}

    function dispense() external override returns (uint256) {
        _mint(msg.sender, 1e18 * 100);
        return 1e18 * 100;
    }

    function emissionRate() external view override returns (uint256) {}
    function emissionStarted() external view returns (bool) {return true;}
}

contract TestFacet is VaultStorage, IFacet {
    address immutable thisImplementation;
    constructor() {
        thisImplementation = address(this);
    }
    function initializeFacet() external {
        _setFunction(TestFacet.setBalance.selector, thisImplementation);
    }
    function setBalance(address pool, Token token, uint128 balance) external {
        _poolBalances()[IPool(pool)][token] = PoolBalance.wrap(bytes32(uint256(balance)));
    }
}
contract StableSwapPoolTest is Test {
    using TokenLib for Token;
    using SafeCast for uint256;
    using SafeCast for int256;

    MockERC20 public usdc;
    MockERC20 public btc;
    ConstantProductPool pool1;
    StableSwapPool pool2;

    Token usdcT;
    Token btcT;
    Token pool1T;
    Token pool2T;


    Deployer deployer;
    Placeholder placeholder_;
    IVault vault;
    ConstantProductLibrary cpl;
    ConstantProductPoolFactory cpf;
    SimpleAuthorizer auth;
    AdminFacet adminFacet;
    uint256 i0;
    uint256 i1;
    uint256 ilp;

    uint8 usdcDecimals;
    uint8 btcDecimals;
    function sb(Token t, uint256 b) internal {
        TestFacet(address(vault)).setBalance(address(pool2), t, b.toUint128());
    }
    function setUp() public {
        deployer = new Deployer();
        placeholder_ = new Placeholder();
        auth = new SimpleAuthorizer();
        adminFacet = new AdminFacet(
            auth,
            address(this)
        );
        IVC vc = new MockVC();
        vault = IVault(adminFacet.deploy(vm.getCode("Diamond.yul:Diamond")));
        vault.admin_addFacet(new SwapFacet(vc, new WETH9(), NATIVE_TOKEN));
        vault.admin_addFacet(new SwapAuxillaryFacet(vc, NATIVE_TOKEN));

        usdc = new MockERC20("USDC", "USDC");
        btc = new MockERC20("BTC", "BTC");

        usdc.setDecimals(6);
        btc.setDecimals(8);

        usdc.mint(type(uint128).max);
        btc.mint(type(uint128).max);
        usdc.approve(address(vault), type(uint256).max);
        btc.approve(address(vault), type(uint256).max);

        StableSwapPoolFactory fac = new StableSwapPoolFactory(vault);
        vault.admin_addFacet(new TestFacet());

        //fac.setFee(0.01e9);
        fac.deploy(toToken(usdc), toToken(btc));

        btcT = toToken(btc);
        usdcT = toToken(usdc);
        if (btcT < usdcT) {
            (usdcT, btcT) = (btcT, usdcT);
            (btc, usdc) = (usdc, btc);
        }
        pool2 = fac.pools(toToken(usdc), toToken(btc));
        pool1T = toToken(pool1);
        pool2T = toToken(pool2);
        console.log(address(btc));
        console.log(address(usdc));
        Token t0 = usdcT;
        Token t1 = btcT;
        if (t1 < t0) {
            (t0, t1) = (t1, t0);
        }
        if (toToken(pool2) < t0) {
            ilp = 0;
            i0 = 1;
            i1 = 2;
        } else if (toToken(pool2) < t1) {
            ilp = 1;
            i0 = 0;
            i1 = 2;
        } else {
            ilp = 2;
            i0 = 0;
            i1 = 1;
        }
        btcDecimals = 18 - btc.decimals();
        usdcDecimals = 18 - usdc.decimals();
    }

    function testFuzz_s0(uint112 ba, uint112 bb, int112 q) public {
        vm.assume(int256(uint256(bb)) + q >= 1);
        ba /= uint112(10 ** usdcDecimals);
        bb /= uint112(10 ** btcDecimals);
        q /= int112(int256(10 ** btcDecimals));
        sb(usdcT, ba);
        sb(btcT, bb);

        Token[] memory t = new Token[](2);
        t[0] = toToken(usdc);
        t[1] = toToken(btc);

        int128[] memory r = new int128[](2);
        r[0] = type(int128).max;
        r[1] = q;

        assumeValid(ba, bb);
        vm.prank(address(vault));
        try pool2.velocore__execute(address(this), t, r, "") returns (int128[] memory, int128[] memory rb) {
        uint256 i0 = pool2.invariant();
        sb(usdcT, (int256(uint256(ba)) + int256(rb[0])).toUint256());
        sb(btcT, (int256(uint256(bb)) + int256(rb[1])).toUint256());
        uint256 i1 = pool2.invariant();
        require(i1 >= i0);
        } catch (bytes memory data) {
         bytes4 expectedSelector = ReserveWillBecomeOutOfBound.selector;
        bytes4 receivedSelector = bytes4(data);
        require (expectedSelector == receivedSelector);
            vm.assume(false);
        }
    }
    error ReserveWillBecomeOutOfBound(int256 b0, int256 b1);
    event Int(int256 a); 
    function assumeValid(uint256 ba, uint256 bb) internal {
        try pool2._validatePoolState(int256(uint256(ba) * (10 ** usdcDecimals)) + 1, int256(uint256(bb) * (10 ** btcDecimals))+1) {}
        catch (bytes memory data) {
         bytes4 expectedSelector = ReserveWillBecomeOutOfBound.selector;
        bytes4 receivedSelector = bytes4(data);
        require (expectedSelector == receivedSelector);
            vm.assume(false);
        }
    }

    function reasonable(int256 a, int256 b) internal returns (bool) {
        return (a * 1e18 / b < 1000e18) && (a * 1e18 / b > 0.001e18);
    }
    function testFuzz_s1(uint112 ba, uint120 bb, int56 q) public {
        vm.assume(int256(uint256(ba)) + q >= 1);
        ba /= uint112(10 ** usdcDecimals);
        bb /= uint112(10 ** btcDecimals);
        q /= int56(int256(10 ** usdcDecimals));
        sb(usdcT, ba);
        sb(btcT, bb);
        assumeValid(ba, bb);
        assumeValid(uint256(int256(uint256(ba)) + q), bb);

        uint256 iusdc = 0;
        uint256 ipool = 1;

        if (toToken(pool2) < toToken(usdc)) {
            iusdc = 1;
            ipool = 0;
        }

        Token[] memory t = new Token[](2);
        t[iusdc] = toToken(usdc);
        t[ipool] = toToken(pool2);

        int128[] memory r = new int128[](2);
        r[iusdc] = q;
        r[ipool] = type(int128).max;



        vm.prank(address(vault));
        try pool2.velocore__execute(address(this), t, r, "") returns (int128[] memory, int128[] memory rb) {
        uint256 i0 = pool2.invariant();
        sb(usdcT, (int256(uint256(ba)) + int256(rb[iusdc])).toUint256());
        uint256 i1 = (int256(pool2.invariant()) + int256(rb[ipool])).toUint256();
        require(i1 >= i0);
        } catch (bytes memory data) {
         bytes4 expectedSelector = ReserveWillBecomeOutOfBound.selector;
        bytes4 receivedSelector = bytes4(data);
        require (expectedSelector == receivedSelector);
            vm.assume(false);
        }
    }
    function testFuzz_s2(uint112 ba, uint112 bb, int56 q) public {
        vm.assume(ba >= (10 ** usdcDecimals));
        vm.assume(bb >= (10 ** btcDecimals));
        ba /= uint112(10 ** usdcDecimals);
        bb /= uint112(10 ** btcDecimals);
        sb(usdcT, ba);
        sb(btcT, bb);
        assumeValid(ba, bb);
        vm.assume(int256(uint256(pool2.invariant())) - q >= 2);

        uint256 iusdc = 0;
        uint256 ipool = 1;

        if (toToken(pool2) < toToken(usdc)) {
            iusdc = 1;
            ipool = 0;
        }

        Token[] memory t = new Token[](2);
        t[iusdc] = toToken(usdc);
        t[ipool] = toToken(pool2);

        int128[] memory r = new int128[](2);
        r[ipool] = q;
        r[iusdc] = type(int128).max;



        vm.prank(address(vault));
        try pool2.velocore__execute(address(this), t, r, "") returns (int128[] memory, int128[] memory rb) {
        uint256 i0 = pool2.invariant();
        sb(usdcT, (int256(uint256(ba)) + int256(rb[iusdc])).toUint256());
        uint256 i1 = (int256(pool2.invariant()) + int256(rb[ipool])).toUint256();
        require(i1 >= i0);
        } catch (bytes memory data) {
         bytes4 expectedSelector = ReserveWillBecomeOutOfBound.selector;
        bytes4 receivedSelector = bytes4(data);
        require (expectedSelector == receivedSelector);
            vm.assume(false);
        }
    }
    function testFuzz_s3(uint120 ba, uint120 bb, int56 q) public {
        vm.assume(ba >= (10 ** usdcDecimals));
        vm.assume(bb >= (10 ** btcDecimals));
        ba /= uint112(10 ** usdcDecimals);
        bb /= uint112(10 ** btcDecimals);
        sb(usdcT, ba);
        sb(btcT, bb);
        assumeValid(ba, bb);
        vm.assume(int256(uint256(pool2.invariant())) - q >= 2);

        uint256 iusdc = i0;
        uint256 ipool = ilp;
        uint256 ibtc = i1;
        Token[] memory t = new Token[](3);
        t[iusdc] = toToken(usdc);
        t[ipool] = toToken(pool2);
        t[ibtc] = toToken(btc);

        int128[] memory r = new int128[](3);
        r[ipool] = q;
        r[iusdc] = type(int128).max;
        r[ibtc] = type(int128).max;

        vm.prank(address(vault));
        try pool2.velocore__execute(address(this), t, r, "") returns (int128[] memory, int128[] memory rb) {
        uint256 i0 = pool2.invariant();
        sb(usdcT, (int256(uint256(ba)) + int256(rb[iusdc])).toUint256());
        sb(btcT, (int256(uint256(bb)) + int256(rb[ibtc])).toUint256());
        uint256 i1 = (int256(pool2.invariant()) + int256(rb[ipool])).toUint256();
        require(i1 >= i0);
        } catch (bytes memory data) {
         bytes4 expectedSelector = ReserveWillBecomeOutOfBound.selector;
        bytes4 receivedSelector = bytes4(data);
        require (expectedSelector == receivedSelector);
            vm.assume(false);
        }
    }
    function testFuzz_s4(uint112 ba, uint112 bb, int56 q, int56 p) public {
        vm.assume(ba >= (10 ** usdcDecimals));
        vm.assume(bb >= (10 ** btcDecimals));
        ba /= uint112(10 ** usdcDecimals);
        bb /= uint112(10 ** btcDecimals);
        p /= int56(int256(10 ** usdcDecimals));
        sb(usdcT, ba);
        sb(btcT, bb);
        assumeValid(ba, bb);
        vm.assume(int256(uint256(pool2.invariant())) - q >= 2);

        uint256 iusdc = i0;
        uint256 ipool = ilp;
        uint256 ibtc = i1;
        Token[] memory t = new Token[](3);
        t[iusdc] = toToken(usdc);
        t[ipool] = toToken(pool2);
        t[ibtc] = toToken(btc);

        int128[] memory r = new int128[](3);
        r[ipool] = q;
        r[iusdc] = p;
        r[ibtc] = type(int128).max;

        vm.prank(address(vault));
        try pool2.velocore__execute(address(this), t, r, "") returns (int128[] memory, int128[] memory rb) {
        uint256 i0 = pool2.invariant();
        sb(usdcT, (int256(uint256(ba)) + int256(rb[iusdc])).toUint256());
        sb(btcT, (int256(uint256(bb)) + int256(rb[ibtc])).toUint256());
        uint256 i1 = (int256(pool2.invariant()) + int256(rb[ipool])).toUint256();
        require(i1 >= i0);
        } catch (bytes memory data) {
         bytes4 expectedSelector = ReserveWillBecomeOutOfBound.selector;
        bytes4 receivedSelector = bytes4(data);
        require (expectedSelector == receivedSelector);
            vm.assume(false);
        }
    }

    function testFuzz_invariant(uint112 b0, uint112 b1) public {
        int256 ratio = int256((uint256(b0) + 1) * 1e18 / (uint256(b1) + 1));
        vm.assume(ratio <= 10000e18 && ratio >= 0.0001e18);
        int256 d = pool2.invariant(int256(uint256(b0)+1), int256(uint256(b1)+1));
        require(pool2._y(d, int256(uint256(b0)+1)) >= int256(uint256(b1))+1);
        require(pool2._y(d, int256(uint256(b1)+1)) >= int256(uint256(b0))+1);
    }

}
