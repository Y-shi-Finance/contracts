// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "openzeppelin/access/AccessControl.sol";
import "contracts/interfaces/IAuthorizer.sol";

contract SimpleAuthorizer is IAuthorizer, AccessControl {
    event ActionAllowed(
        address indexed who,
        address indexed factory,
        bytes4 indexed sig,
        string func
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function allowAction(
        address who,
        address factory,
        string memory func
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes4 sig = bytes4(keccak256(bytes(func)));
        _grantRole(
            keccak256(
                abi.encodePacked(
                    bytes32(uint256(uint160(address(factory)))),
                    sig
                )
            ),
            who
        );

        emit ActionAllowed(who, factory, sig, func);
    }

    function canPerform(
        bytes32 actionId,
        address account,
        address where
    ) external view override returns (bool) {
        return
            hasRole(DEFAULT_ADMIN_ROLE, account) || hasRole(actionId, account);
    }
}
