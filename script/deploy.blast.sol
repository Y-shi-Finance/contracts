// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Upgrade.sol";
import "contracts/AdminFacet.sol";
import "contracts/SwapFacet.sol";
import "contracts/SwapAuxillaryFacet.sol";
import "contracts/pools/vc/BLADE.sol";
import "contracts/pools/vc/veBLADE.sol";
import "contracts/pools/converter/WETHConverter.sol";
import "contracts/pools/wombat/WombatPool.sol";
import "contracts/MockERC20.sol";
import "contracts/lens/Lens.sol";
import "contracts/NFTHolderFacet.sol";
import "contracts/InspectorFacet.sol";
import "contracts/SwapHelperFacet.sol";
import "contracts/BlastFacet.sol";
import "contracts/SwapHelperFacet2.sol";
import "contracts/lens/VelocoreLens.sol";
import "contracts/pools/xyk/XYKPoolFactory.sol";
import "contracts/pools/constant-product/ConstantProductPoolFactory.sol";
import "contracts/pools/linear-bribe/LinearBribeFactory.sol";
import "contracts/authorizer/SimpleAuthorizer.sol";
import "contracts/MockERC20.sol";

contract Placeholder is ERC1967Upgrade {
    address immutable admin;

    constructor() {
        admin = msg.sender;
    }

    function upgradeTo(address newImplementation) external {
        require(msg.sender == admin, "not admin");
        ERC1967Upgrade._upgradeTo(newImplementation);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external {
        require(msg.sender == admin, "not admin");
        ERC1967Upgrade._upgradeToAndCall(newImplementation, data, true);
    }
}

contract Deployer {
    function deployAndCall(bytes memory bytecode, bytes memory cd) external returns (address) {
        address deployed;
        bool success;
        assembly ("memory-safe") {
            deployed := create(0, add(bytecode, 32), mload(bytecode))
            success := call(gas(), deployed, 0, add(cd, 32), mload(cd), 0, 0)
        }
        require(deployed != address(0) && success);
        return deployed;
    }
}

contract DeployScript is Script {
    Deployer public deployer;
    Placeholder public placeholder_;
    IVault public vault;
    Blade public vc;
    VeBlade public veVC;
    MockERC20 public oldVC;
    WombatPool public wombat;
    XYKPoolFactory public cpf;
    StableSwapPoolFactory public spf;
    IAuthorizer public auth;
    AdminFacet public adminFacet;
    LinearBribeFactory public lbf;
    WETHConverter public wethConverter;
    VelocoreLens public lens;
    MockERC20 public crvUSD;
    MockERC20 public USDB;


    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        deployer = new Deployer();
        placeholder_ = new Placeholder();
        auth = new SimpleAuthorizer();
        adminFacet = new AdminFacet(
            auth,
            tx.origin
        );
        vault = IVault(adminFacet.deploy(vm.getCode("Diamond.yul:Diamond")));
        vc = Blade(placeholder());
        veVC = VeBlade(placeholder());
        lbf = new LinearBribeFactory(vault);
        address weth = address(BLAST_WETH);
        wethConverter = new WETHConverter(vault, IWETH(weth));
        lbf.setFeeToken(toToken(veVC));
        lbf.setFeeAmount(1000e18);
        lbf.setTreasury(tx.origin);
        SimpleAuthorizer(address(auth)).grantRole(
            keccak256(abi.encodePacked(bytes32(uint256(uint160(address(vault)))), IVault.attachBribe.selector)),
            address(lbf)
        );

        cpf = new XYKPoolFactory(vault);
        spf = new StableSwapPoolFactory(vault);
        cpf.setFee(0.01e9);
        spf.setFee(0.0005e9);
        lens = VelocoreLens(address(new Lens(vault)));
        Lens(address(lens)).upgrade(
            address(
                new VelocoreLens(
                    NATIVE_TOKEN,
                    vc,
                    XYKPoolFactory(address(cpf)),
                    spf,
                    XYKPoolFactory(address(cpf)),
                    VelocoreLens(address(lens))
                )
            )
        );

        vault.admin_addFacet(new SwapFacet(vc, IWETH(weth), toToken(veVC)));
        vault.admin_addFacet(new SwapAuxillaryFacet(vc, toToken(veVC)));
        vault.admin_addFacet(new NFTHolderFacet());
        vault.admin_addFacet(new InspectorFacet());
        try vault.admin_addFacet(new BlastFacet()) {} catch(bytes memory) {}
        vault.admin_addFacet(new SwapHelperFacet(address(vc), cpf, spf));
        vault.admin_addFacet(new SwapHelperFacet2(address(vc), cpf, spf));

        Placeholder(address(vc)).upgradeToAndCall(
            address(
                new Blade(
                    address(vc),
                    vault,
                    address(veVC)
                )
            ),
            abi.encodeWithSelector(Blade.initialize.selector)
        );

        Placeholder(address(veVC)).upgradeToAndCall(
            address(new VeBlade(address(veVC), vault, vc)), abi.encodeWithSelector(VeBlade.initialize.selector)
        );

        //cpf.deploy(NATIVE_TOKEN, toToken(vc));
        cpf.deploy(NATIVE_TOKEN, toToken(BLAST_USDB));
        //vault.execute1(address(vc), 0, address(vc), 0, 0, "");
        /*
        SwapHelperFacet2(address(vault)).addLiquidity{value: 1e18}(address(0), address(vc), false, 1e18, 10000e18, 0, 0, tx.origin, type(uint256).max); 
        SwapHelperFacet2(address(vault)).addLiquidity{value: 1e18}(address(USDB), address(0), false, 10000e18, 1e18, 0, 0, tx.origin, type(uint256).max); 
        SwapHelperFacet2(address(vault)).addLiquidity(address(USDB), address(crvUSD), true, 10000e18, 10000e18, 0, 0, tx.origin, type(uint256).max); 

       */
        vm.stopBroadcast();
        console.log("authorizer: %s", address(auth));
        console.log("IVault: %s", address(vault));
        console.log("Lens: %s", address(lens));

        console.log("cpf: %s", address(cpf));
        console.log("spf: %s", address(spf));
        console.log("vc: %s", address(vc));
        console.log("veVC: %s", address(veVC));
        console.log("LinearBribeFactory: %s", address(lbf));
        console.log("WETH: %s", address(weth));
        console.log("WETHConverter: %s", address(wethConverter));
    }

    function placeholder() internal returns (address) {
        return deployer.deployAndCall(vm.getCode("DumbProxy.yul:DumbProxy"), abi.encode(placeholder_));
    }
}
