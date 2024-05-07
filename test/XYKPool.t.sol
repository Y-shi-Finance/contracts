// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "script/Deploy.generic.s.sol";
import "contracts/MockERC20.sol";
import "contracts/pools/constant-product/ConstantProductPool.sol";
import {XYKPool, XYKPoolFactory} from "contracts/pools/xyk/XYKPoolFactory.sol";
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

    function emissionRate() external view override returns (uint256) {return 0;}
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
contract XYKPoolTest is Test {
    using TokenLib for Token;

    MockERC20 public usdc;
    MockERC20 public btc;
    ConstantProductPool pool1;
    XYKPool pool2;

    Token usdcT;
    Token btcT;
    Token pool1T;
    Token pool2T;

    uint256 i0;
    uint256 i1;
    uint256 ilp;


    Deployer deployer;
    Placeholder placeholder_;
    IVault vault;
    ConstantProductLibrary cpl;
    ConstantProductPoolFactory cpf;
    SimpleAuthorizer auth;
    AdminFacet adminFacet;
    function setUp() public {
        deployer = new Deployer();
        placeholder_ = new Placeholder();
        auth = new SimpleAuthorizer();
        adminFacet = new AdminFacet(
            auth,
            address(this)
        );
        vault = IVault(adminFacet.deploy(vm.getCode("Diamond.yul:Diamond")));
        IVC vc = new MockVC();
        vault.admin_addFacet(new SwapFacet(vc, new WETH9(), NATIVE_TOKEN));
        vault.admin_addFacet(new SwapAuxillaryFacet(vc, NATIVE_TOKEN));

        usdc = new MockERC20("USDC", "USDC");
        btc = new MockERC20("BTC", "BTC");

        usdc.mint(type(uint128).max);
        btc.mint(type(uint128).max);
        usdc.approve(address(vault), type(uint256).max);
        btc.approve(address(vault), type(uint256).max);

        XYKPoolFactory fac = new XYKPoolFactory(vault);
        vault.admin_addFacet(new TestFacet());

        //fac.setFee(0.01e9);
        fac.deploy(toToken(usdc), toToken(btc));

        btcT = toToken(btc);
        usdcT = toToken(usdc);
        if (btcT < usdcT) {
            (usdcT, btcT) = (btcT, usdcT);
            (usdc, btc) = (btc, usdc);
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

        if (toToken(btc) < toToken(usdc)) {
            (i0, i1) = (i1, i0);
        }
    }

    function invariant(int256 a, int256 b) internal pure returns (int256) {
        uint256 a_ = uint256(a);
        uint256 b_ = uint256(b);
        return int256(invariant(a_, b_));
    }

    function invariant(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.sqrt((a + 1) * (b + 1));
    }
    function sb(Token t, uint128 b) internal {
        TestFacet(address(vault)).setBalance(address(pool2), t, b);
    }

    function similar(int128[] memory a, int128[] memory b) internal returns (bool) {
        for (uint256 i = 0; i < a.length; i++) {
            uint256 diff = SignedMath.abs(int256(a[i]) - int256(b[i]));
            uint256 diffRatio1 = a[i] == 0 ? 0 : diff * 1e18 / SignedMath.abs(a[i]);
            uint256 diffRatio2 = b[i] == 0 ? 0 : diff * 1e18 / SignedMath.abs(b[i]);
            if ((diffRatio1 > 0.001e18 || diffRatio2 > 0.001e18) && diff > 1e7) {
                return false;
            }
        }
        return true;
    }

    function testFuzz_s0(uint120 ba, uint120 bb, int120 q) public {
        vm.assume(int256(uint256(bb)) + int256(q) >= 0);
        sb(usdcT, ba);
        sb(btcT, bb);
        
        uint256 iusdc = 0;
        uint256 ibtc = 1;

        if (i1 < i0) {
            iusdc = 1;
            ibtc =0;
        }

        Token[] memory t = new Token[](2);
        t[iusdc] = toToken(usdc);
        t[ibtc] = toToken(btc);

        int128[] memory r = new int128[](2);
        r[iusdc] = type(int128).max;
        r[ibtc] = q;

        vm.prank(address(vault));
        (,int128[] memory rb) = pool2.velocore__execute(address(this), t, r, "");
        int256 i0 = invariant(int256(uint256(ba)), int256(uint256(bb)));
        int256 i1 = invariant(int256(uint256(ba)) + int256(rb[iusdc]), int256(uint256(bb)) + int256(rb[ibtc]));
        require(i1 >= i0);
    }
    event Int(int256 a); 
    function testFuzz_s1(uint120 ba, uint120 bb, int120 q) public {
        vm.assume(int256(uint256(ba)) + int256(q) >= 0);
        sb(usdcT, ba);
        sb(btcT, bb);

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
        (,int128[] memory rb) = pool2.velocore__execute(address(this), t, r, "");
        int256 i0 = invariant(int256(uint256(ba)), int256(uint256(bb)));
        int256 i1 = invariant(int256(uint256(ba)) + int256(rb[iusdc]), int256(uint256(bb))) + int256(rb[ipool]);
        emit Int(i0);
        emit Int(i1);
        require(i1 >= i0);
    }
    function testFuzz_s2(uint120 ba, uint120 bb, int56 q) public {
        vm.assume(int256(invariant(ba, bb)) - int256(q) >= 1);
        sb(usdcT, ba);
        sb(btcT, bb);

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
        (,int128[] memory rb) = pool2.velocore__execute(address(this), t, r, "");
        int256 i0 = invariant(int256(uint256(ba)), int256(uint256(bb)));
        int256 i1 = invariant(int256(uint256(ba)) + int256(rb[iusdc]), int256(uint256(bb))) + int256(rb[ipool]);
        emit Int(i0);
        emit Int(i1);
        require(i1 >= i0);
    }
    function testFuzz_s3(uint120 ba, uint120 bb, int56 q) public {
        vm.assume(int256(invariant(ba, bb)) - int256(q) >= 1);
        sb(usdcT, ba);
        sb(btcT, bb);

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
        (,int128[] memory rb) = pool2.velocore__execute(address(this), t, r, "");
        int256 i0 = invariant(int256(uint256(ba)), int256(uint256(bb)));
        int256 i1 = invariant(int256(uint256(ba)) + int256(rb[iusdc]), int256(uint256(bb)) + rb[ibtc]) + int256(rb[ipool]);
        emit Int(i0);
        emit Int(i1);
        require(i1 >= i0);
    }
    function testFuzz_s4(uint120 ba, uint120 bb, int56 q, int120 p) public {
        vm.assume(int256(invariant(ba, bb)) - int256(q) >= 1);
        vm.assume(int256(uint256(ba)) + int256(p) >= 0);
        sb(usdcT, ba);
        sb(btcT, bb);

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
        (,int128[] memory rb) = pool2.velocore__execute(address(this), t, r, "");
        int256 i0 = invariant(int256(uint256(ba)), int256(uint256(bb)));
        int256 i1 = invariant(int256(uint256(ba)) + int256(rb[iusdc]), int256(uint256(bb)) + rb[ibtc]) + int256(rb[ipool]);
        emit Int(i0);
        emit Int(i1);
        require(i1 >= i0);
    }
}
