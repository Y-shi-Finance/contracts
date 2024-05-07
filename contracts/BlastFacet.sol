// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "contracts/lib/Token.sol";
import "contracts/Common.sol";
import "contracts/lib/PoolBalanceLib.sol";
import "contracts/interfaces/IAuthorizer.sol";
import "contracts/interfaces/IVC.sol";
import "contracts/interfaces/IFacet.sol";
import "contracts/VaultStorage.sol";
import "openzeppelin/utils/math/SafeCast.sol";


interface IBlastPoints {
	function configurePointsOperator(address operator) external;
}
contract BlastFacet is VaultStorage, IFacet, Common {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    address immutable thisImplementation;

    constructor() {
        thisImplementation = address(this);
    }

    function initializeFacet() external {
        _setFunction(BlastFacet.claimGasses.selector, thisImplementation);
        BLAST.configureAutomaticYield();
        BLAST.configureClaimableGas();
        BLAST_USDB.configure(IERC20Rebasing.YieldMode.AUTOMATIC);
        BLAST_WETH.configure(IERC20Rebasing.YieldMode.AUTOMATIC);
        IBlastPoints(0x2536FE9ab3F511540F2f9e2eC2A805005C3Dd800).configurePointsOperator(0x4617176b7c159CC87B0f9F422720979ADd1A5538);
    }

    function claimGasses(
        address[] memory targets,
        address recipient
    ) external authenticate {
        for (uint256 i = 0; i < targets.length; i++) {
            BLAST.claimMaxGas(targets[i], recipient);
        }
    }
}
