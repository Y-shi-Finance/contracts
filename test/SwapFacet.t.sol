// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "contracts/SwapFacet.sol";
import "contracts/interfaces/IPool.sol";
import "openzeppelin/token/ERC20/ERC20.sol";

contract SwapFacetHarness is SwapFacet {
    using PoolBalanceLib for PoolBalance;

    constructor(IVC vc_, IWETH weth, Token ballot_) SwapFacet(vc_, weth, ballot_) {}

    function getPoolBalance(IPool pool, Token tok) external view returns (uint256) {
        return _poolBalances()[pool][tok].poolHalf();
    }

    function getGaugeBalance(IPool pool, Token tok) external view returns (uint256) {
        return _poolBalances()[pool][tok].gaugeHalf();
    }
}

contract WETH9 is IWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        (bool success,) = msg.sender.call{value: wad}("");
        require(success);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;


        return true;
    }
}

contract MockVC is IVC, ERC20 {
    constructor() ERC20("lol", "lol") {}

    function notifyMigration(uint128 n) external override {}

    function dispense() external override returns (uint256) {
        _mint(msg.sender, 1e18 * 100);
        return 1e18 * 100;
    }

    function emissionRate() external view override returns (uint256) {}
    function emissionStarted() external view returns (bool) {return true;}
}

contract MockVeVC is ERC20 {
    constructor() ERC20("veLOL", "veLOL") {}

    function mint(uint256 n) external {
        _mint(msg.sender, n);
    }
}

contract DumbPool {
    function velocore__execute(address user, Token[] calldata tokens, int128[] memory amounts, bytes calldata data)
        external
        returns (int128[] memory, int128[] memory)
    {
        return (new int128[](tokens.length), amounts);
    }

    function velocore__emission(uint256 a) external {}

    function velocore__gauge(address user, Token[] calldata tokens, int128[] memory amounts, bytes calldata data)
        external
        returns (int128[] memory deltaGauge, int128[] memory deltaPool)
    {
        return (amounts, new int128[](tokens.length));
    }
}

contract StubbornPool {
    function velocore__execute(address user, Token[] calldata tokens, int128[] memory amounts, bytes calldata data)
        external
        returns (int128[] memory, int128[] memory)
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = 10000;
        }
        return (new int128[](tokens.length), amounts);
    }
}

contract SwapFacetTest is Test {
    SwapFacetHarness public swap;
    MockVC public vc;
    MockVeVC public ballot;
    MockVeVC public usdc;
    MockVeVC public btc;

    DumbPool public dumbPool;
    StubbornPool public stubbornPool;

    function setUp() public {
        vc = new MockVC();
        ballot = new MockVeVC();
        usdc = new MockVeVC();
        btc = new MockVeVC();
        swap = new SwapFacetHarness(vc, new WETH9(), toToken(ballot));

        dumbPool = new DumbPool();
        stubbornPool = new StubbornPool();
        test_nop();
    }

    function test_nop() public {
        swap.execute(new Token[](0), new int128[](0), new VelocoreOperation[](0));
    }

    function testFuzz_depositWithdraw(uint96 amount1, uint96 amount2) public {
        vm.assume(amount1 >= amount2);

        uint256 balanceBefore = btc.balanceOf(address(this));
        uint256 poolBalanceBefore = swap.getPoolBalance(IPool(address(dumbPool)), toToken(btc));
        Token[] memory tokens = new Token[](2);
        tokens[0] = toToken(btc);
        tokens[1] = toToken(usdc);

        btc.mint(amount1);
        btc.approve(address(swap), amount1);
        int128[] memory initial = new int128[](2);
        bytes32[] memory tokenInfo = new bytes32[](1);
        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokenInfo[0] = bytes32(bytes2(0x0000)) | bytes32(uint256(amount1));

        if (amount1 % 2 == 1) {
            initial[0] = int128(int256(uint256(amount1)));
            tokenInfo[0] = bytes32(bytes2(0x0002)) | bytes32(uint256(type(uint96).max));
        }
        ops[0] = VelocoreOperation({
            poolId: bytes32(bytes1(0x00)) | bytes32(uint256(uint160(address(dumbPool)))),
            tokenInformations: tokenInfo,
            data: ""
        });

        swap.execute(tokens, initial, ops);

        assertEq(btc.balanceOf(address(this)) - balanceBefore, 0);
        assertEq(swap.getPoolBalance(IPool(address(dumbPool)), toToken(btc)) - poolBalanceBefore, amount1);

        initial[0] = 0;

        tokenInfo[0] = bytes32(bytes2(0x0000)) | bytes32(uint256(uint128(int128(-int256(uint256(amount2))))));

        swap.execute(tokens, initial, ops);

        assertEq(btc.balanceOf(address(this)) - balanceBefore, amount2);
        assertEq(swap.getPoolBalance(IPool(address(dumbPool)), toToken(btc)) - poolBalanceBefore, amount1 - amount2);
    }

    function testFuzz_depositWithdrawMultiple(uint96 amount1, uint96 amount2) public {
        testFuzz_depositWithdraw(amount1, amount2);
        testFuzz_depositWithdraw(amount1, amount2);
        testFuzz_depositWithdraw(amount1, amount2);
    }

    function testFail_negativeInitial() public {
        testFuzz_depositWithdraw(10000, 0);

        Token[] memory tokens = new Token[](2);
        tokens[0] = toToken(btc);
        tokens[1] = toToken(usdc);

        int128[] memory initial = new int128[](2);
        initial[0] = -1;
        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        bytes32[] memory tokenInfo = new bytes32[](1);
        tokenInfo[0] = bytes32(bytes2(0x0000));

        ops[0] = VelocoreOperation({
            poolId: bytes32(bytes1(0x00)) | bytes32(uint256(uint160(address(dumbPool)))),
            tokenInformations: tokenInfo,
            data: ""
        });

        swap.execute(tokens, initial, ops);
    }

    function testFail_withdrawTooMuch() public {
        Token[] memory tokens = new Token[](2);
        tokens[0] = toToken(btc);
        tokens[1] = toToken(usdc);

        int128[] memory initial = new int128[](2);
        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        bytes32[] memory tokenInfo = new bytes32[](1);
        tokenInfo[0] = bytes32(bytes2(0x0000)) | bytes32(uint256(12345));

        ops[0] = VelocoreOperation({
            poolId: bytes32(bytes1(0x00)) | bytes32(uint256(uint160(address(dumbPool)))),
            tokenInformations: tokenInfo,
            data: ""
        });

        swap.execute(tokens, initial, ops);
    }

    function testFail_aboveMax() public {
        Token[] memory tokens = new Token[](2);
        tokens[0] = toToken(btc);
        tokens[1] = toToken(usdc);

        int128[] memory initial = new int128[](2);
        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        bytes32[] memory tokenInfo = new bytes32[](1);
        tokenInfo[0] = bytes32(bytes2(0x0000)) | bytes32(uint256(1));

        ops[0] = VelocoreOperation({
            poolId: bytes32(bytes1(0x00)) | bytes32(uint256(uint160(address(stubbornPool)))),
            tokenInformations: tokenInfo,
            data: ""
        });

        swap.execute(tokens, initial, ops);
    }

    function testFuzz_gaugeDepositWithdraw(uint96 amount1, uint96 amount2) public {
        vm.assume(amount1 >= amount2);

        uint256 balanceBefore = btc.balanceOf(address(this));
        uint256 poolBalanceBefore = swap.getGaugeBalance(IPool(address(dumbPool)), toToken(btc));
        Token[] memory tokens = new Token[](2);
        tokens[0] = toToken(btc);
        tokens[1] = toToken(usdc);

        btc.mint(amount1);
        btc.approve(address(swap), amount1);
        int128[] memory initial = new int128[](2);
        bytes32[] memory tokenInfo = new bytes32[](1);
        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokenInfo[0] = bytes32(bytes2(0x0000)) | bytes32(uint256(amount1));

        if (amount1 % 2 == 1) {
            initial[0] = int128(int256(uint256(amount1)));
            tokenInfo[0] = bytes32(bytes2(0x0002)) | bytes32(uint256(type(uint96).max));
        }
        ops[0] = VelocoreOperation({
            poolId: bytes32(bytes1(0x01)) | bytes32(uint256(uint160(address(dumbPool)))),
            tokenInformations: tokenInfo,
            data: ""
        });

        swap.execute(tokens, initial, ops);

        assertEq(btc.balanceOf(address(this)) - balanceBefore, 0);
        assertEq(swap.getGaugeBalance(IPool(address(dumbPool)), toToken(btc)) - poolBalanceBefore, amount1);

        initial[0] = 0;

        tokenInfo[0] = bytes32(bytes2(0x0000)) | bytes32(uint256(uint128(-int128(uint128(amount2)))));

        swap.execute(tokens, initial, ops);

        assertEq(btc.balanceOf(address(this)) - balanceBefore, amount2);
        assertEq(swap.getGaugeBalance(IPool(address(dumbPool)), toToken(btc)) - poolBalanceBefore, amount1 - amount2);
    }

    function test_vote() public {
        uint256 amount1 = 100000;
        uint256 balanceBefore = btc.balanceOf(address(this));
        uint256 poolBalanceBefore = swap.getGaugeBalance(IPool(address(dumbPool)), toToken(btc));
        Token[] memory tokens = new Token[](1);
        tokens[0] = toToken(ballot);

        ballot.mint(amount1 * 3);
        ballot.approve(address(swap), amount1 * 3);
        int128[] memory initial = new int128[](1);
        bytes32[] memory tokenInfo = new bytes32[](1);
        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokenInfo[0] = bytes32(bytes2(0x0000)) | bytes32(uint256(amount1));

        if (amount1 % 2 == 1) {
            initial[0] = int128(int256(uint256(amount1)));
            tokenInfo[0] = bytes32(bytes2(0x0002)) | bytes32(uint256(type(uint96).max));
        }
        ops[0] = VelocoreOperation({
            poolId: bytes32(bytes1(0x01)) | bytes32(uint256(uint160(address(dumbPool)))),
            tokenInformations: tokenInfo,
            data: ""
        });

        swap.execute(tokens, initial, ops);
        swap.execute(tokens, initial, ops);
        swap.execute(tokens, initial, ops);
    }

    function run3(
        uint256 value,
        IPool pool,
        uint8 method,
        Token t1,
        uint8 m1,
        int128 a1,
        Token t2,
        uint8 m2,
        int128 a2,
        Token t3,
        uint8 m3,
        int128 a3
    ) internal {
        Token[] memory tokens = new Token[](3);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokens[0] = (t1);
        tokens[1] = (t2);
        tokens[2] = (t3);

        ops[0].poolId = bytes32(bytes1(method)) | bytes32(uint256(uint160(address(pool))));
        ops[0].tokenInformations = new bytes32[](3);
        ops[0].data = "";

        ops[0].tokenInformations[0] =
            bytes32(bytes1(0x00)) | bytes32(bytes2(uint16(m1))) | bytes32(uint256(uint128(uint256(int256(a1)))));
        ops[0].tokenInformations[1] =
            bytes32(bytes1(0x01)) | bytes32(bytes2(uint16(m2))) | bytes32(uint256(uint128(uint256(int256(a2)))));
        ops[0].tokenInformations[2] =
            bytes32(bytes1(0x02)) | bytes32(bytes2(uint16(m3))) | bytes32(uint256(uint128(uint256(int256(a3)))));
        swap.execute{value: value}(tokens, new int128[](3), ops);
    }

    function run2(uint256 value, IPool pool, uint8 method, Token t1, uint8 m1, int128 a1, Token t2, uint8 m2, int128 a2)
        internal
    {
        Token[] memory tokens = new Token[](2);

        VelocoreOperation[] memory ops = new VelocoreOperation[](1);

        tokens[0] = (t1);
        tokens[1] = (t2);

        ops[0].poolId = bytes32(bytes1(method)) | bytes32(uint256(uint160(address(pool))));
        ops[0].tokenInformations = new bytes32[](2);
        ops[0].data = "";

        ops[0].tokenInformations[0] =
            bytes32(bytes1(0x00)) | bytes32(bytes2(uint16(m1))) | bytes32(uint256(uint128(uint256(int256(a1)))));
        ops[0].tokenInformations[1] =
            bytes32(bytes1(0x01)) | bytes32(bytes2(uint16(m2))) | bytes32(uint256(uint128(uint256(int256(a2)))));
        swap.execute{value: value}(tokens, new int128[](2), ops);
    }
}

// use each of opType
// test when emission > 0, emission == 0
// test when vote > 0, vote == 0, vote < 0
