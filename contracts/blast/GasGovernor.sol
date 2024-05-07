// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "contracts/blast/IBLAST.sol";
import "contracts/interfaces/IVault.sol";
import "openzeppelin/access/Ownable.sol";

contract GasClaimer is Ownable {
    mapping(address => bool) registered;
    address[] contracts;
    IVault immutable vault;

    constructor(IVault v) {vault = v;}

    function addContract(address a) external onlyOwner {
        require (!registered[a]);
        registered[a] = true;
        contracts.push(a);
    }
    function claim() external onlyOwner {
       vault.claimGasses(contracts, msg.sender); 
    }
}
