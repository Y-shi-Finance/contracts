// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Upgrade.sol";
import "contracts/AdminFacet.sol";
import "contracts/SwapFacet.sol";
import "contracts/SwapAuxillaryFacet.sol";
import "contracts/pools/GovernanceToken.sol";
import "contracts/pools/LockedToken.sol";
import "contracts/pools/converter/WETHConverter.sol";
import "contracts/MockERC20.sol";
import "contracts/deployment/Deployer.sol";
import "contracts/lens/Lens.sol";
import "contracts/NFTHolderFacet.sol";
import "contracts/InspectorFacet.sol";
import "contracts/SwapHelperFacet.sol";
import "contracts/SwapHelperFacet2.sol";
import "contracts/lens/VelocoreLens.sol";
import "contracts/pools/xyk/XYKPoolFactory.sol";
import "contracts/pools/linear-bribe/LinearBribeFactory.sol";
import "contracts/authorizer/SimpleAuthorizer.sol";
import "contracts/Placeholder.sol";

contract WETH9 {
    string public name = "Wrapped EDU";
    string public symbol = "WEDU";
    uint8 public decimals = 18;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad, "");
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) public returns (bool) {
        require(balanceOf[src] >= wad, "");

        if (
            src != msg.sender && allowance[src][msg.sender] != type(uint256).max
        ) {
            require(allowance[src][msg.sender] >= wad, "");
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }
}

contract Main is Script {
    Deployer public deployer;
    Placeholder public placeholder_;
    IVault public vault;
    GovernanceToken public gov;
    LockedToken public ballot;
    XYKPoolFactory public cpf;
    IAuthorizer public auth;
    AdminFacet public adminFacet;
    LinearBribeFactory public lbf;
    WETHConverter public wethConverter;
    VelocoreLens public lens;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_TAIKO");
        vm.startBroadcast(deployerPrivateKey);
        address admin = 0x086878cAcCC00930CfE701a7cA26D3094E42B1b8;
        deployer = new Deployer();
        placeholder_ = new Placeholder();
        auth = new SimpleAuthorizer();
        adminFacet = new AdminFacet(auth);
        vault = IVault(adminFacet.deploy());
        gov = new GovernanceToken(address(vault), "Yooshi", "YOO");
        ballot = LockedToken(placeholder());
        lbf = new LinearBribeFactory(vault);
        address weth = address(new WETH9());
        wethConverter = new WETHConverter(vault, IWETH(weth));
        lbf.setFeeToken(toToken(ballot));
        lbf.setFeeAmount(1000e18);
        lbf.setTreasury(admin);

        SimpleAuthorizer(address(auth)).grantRole(
            keccak256(
                abi.encodePacked(
                    bytes32(uint256(uint160(address(vault)))),
                    IVault.attachBribe.selector
                )
            ),
            address(lbf)
        );

        cpf = new XYKPoolFactory(vault, weth, "veYOO");
        cpf.setFee(0.01e9);
        lens = VelocoreLens(address(new Lens(vault)));
        Lens(address(lens)).upgrade(
            address(
                new VelocoreLens(
                    toToken(IERC20(weth)),
                    gov,
                    XYKPoolFactory(address(cpf)),
                    VelocoreLens(address(lens))
                )
            )
        );

        vault.admin_addFacet(new SwapFacet(gov, IWETH(weth), toToken(ballot)));
        vault.admin_addFacet(new SwapAuxillaryFacet(gov, toToken(ballot)));
        vault.admin_addFacet(new NFTHolderFacet());
        vault.admin_addFacet(new InspectorFacet());
        //try vault.admin_addFacet(new BlastFacet()) {} catch (bytes memory) {}
        vault.admin_addFacet(new SwapHelperFacet(address(gov), cpf));
        vault.admin_addFacet(new SwapHelperFacet2(address(gov), cpf));

        Placeholder(address(ballot)).upgradeToAndCall(
            address(new LockedToken(address(ballot), vault, gov)),
            abi.encodeWithSelector(
                LockedToken.initialize.selector,
                "Locked Yooshi",
                "veYOO"
            )
        );

        cpf.deploy(NATIVE_TOKEN, toToken(gov));

        //vault.execute1(address(vc), 0, address(vc), 0, 0, "");
        SwapHelperFacet2(address(vault)).addLiquidity{value: 1e18}(
            address(0),
            address(gov),
            false,
            1e18,
            10000e18,
            0,
            0,
            admin,
            type(uint256).max
        );

        vm.stopBroadcast();
        console.log("authorizer: %s", address(auth));
        console.log("IVault: %s", address(vault));
        console.log("Lens: %s", address(lens));

        console.log("cpf: %s", address(cpf));
        console.log("vc token: %s", address(gov));
        console.log("vevc token: %s", address(ballot));
        console.log("LinearBribeFactory: %s", address(lbf));
        console.log("WETH: %s", address(weth));
        console.log("WETHConverter: %s", address(wethConverter));
    }

    function placeholder() internal returns (address) {
        return
            deployer.deployAndCall(
                vm.getCode("DumbProxy.sol:DumbProxy"),
                abi.encode(placeholder_)
            );
    }
}
