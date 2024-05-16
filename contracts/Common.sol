// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "contracts/blast/IBLAST.sol";

contract Common {
    address constant governor = 0x65432138ae74065Aeb3Bd71aEaC887CCAE0E32a4;
    constructor() {
        if (block.chainid == 81457) {
          BLAST.configureClaimableGas();
          BLAST.configureGovernor(governor);
        }
    }
}
