// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Upgrade.sol";
import "contracts/AdminFacet.sol";
import "contracts/SwapFacet.sol";
import "contracts/pools/vc/VC.sol";
import "contracts/pools/vc/VeVC.sol";
import "contracts/pools/linear-bribe/LinearBribeFactory.sol";
import "contracts/pools/converter/WETHConverter.sol";
import "contracts/pools/wombat/WombatPool.sol";
import "contracts/pools/wombat/WombatRegistry.sol";
import "contracts/MockERC20.sol";
import "contracts/lens/Lens.sol";
import "contracts/NFTHolderFacet.sol";
import "contracts/sale/VoterFactory.sol";
import "contracts/lens/VelocoreLens.sol";
import "contracts/pools/constant-product/ConstantProductPoolFactory.sol";
import "contracts/pools/constant-product/ConstantProductLibrary.sol";
import "openzeppelin/governance/TimelockController.sol";
import "contracts/authorizer/SimpleAuthorizer.sol";

contract UpgradeScript is Script {
    function setUp() public {}

    function run() public returns (IVault, VC, VeVC) {
        vm.startBroadcast();
        //address[] memory m = new address[](1);
        //m[0] = 0x1234561fEd41DD2D867a038bBdB857f291864225;
        //TimelockController tc = new TimelockController(7 days, m, m, address(0));

        address admin = 0x65432138ae74065Aeb3Bd71aEaC887CCAE0E32a4;
        address vault = 0x10F6b147D51f7578F760065DF7f174c3bc95382c;
        address xyk1 = 0xE1D6a7498DCBcA37DCB112018748C396bA749d66;
        address xyk2 = 0x75cB3eC310d3D1E22637F79D61eab5D9aBCD68BD;
        address lbf = 0x5045c448A06498c29694B7348ec5A5010B6946d9;
        SimpleAuthorizer auth = SimpleAuthorizer(
            0x06b1431b2CFc81FD1e428d6A4916FeC395C9D9Cb
        );
        auth.allowAction(admin, xyk2, "setFee(uint256,uint256)");
        auth.allowAction(admin, xyk2, "setFee(uint32)");
        auth.allowAction(admin, xyk2, "setDecay(uint256)");
        auth.allowAction(admin, xyk2, "setDecay(uint32)");
        auth.allowAction(admin, xyk1, "setFee(uint256,uint256)");
        auth.allowAction(admin, xyk1, "setFee(uint32)");
        auth.allowAction(admin, xyk1, "setDecay(uint256)");
        auth.allowAction(admin, xyk1, "setDecay(uint32)");
        auth.allowAction(admin, admin, "setFee(uint256,uint256)");
        auth.allowAction(admin, admin, "setFee(uint32)");
        auth.allowAction(admin, admin, "setDecay(uint256)");
        auth.allowAction(admin, admin, "setDecay(uint32)");
        auth.allowAction(admin, vault, "killGauge(address,bool)");
        auth.allowAction(admin, vault, "killBribe(address,address)");
        auth.allowAction(admin, vault, "attachBribe(address,address)");
        auth.allowAction(admin, lbf, "setFeeAmount(int128)");
        auth.allowAction(admin, lbf, "setFeeToken(bytes32)");
        auth.allowAction(admin, lbf, "setTreasury(address)");
        address[] memory r = new address[](1);
        r[0] = admin;
        TimelockController tl = new TimelockController(
            6 hours,
            r,
            r,
            address(0)
        );
        auth.grantRole(auth.DEFAULT_ADMIN_ROLE(), address(tl));
        SimpleAuthorizer(address(0xE6D4C953A094Fbc1DBF0D46f51C2B56aB51e9780))
            .renounceRole(0x00, 0x1234561fEd41DD2D867a038bBdB857f291864225);
        vm.stopBroadcast();
    }
}
