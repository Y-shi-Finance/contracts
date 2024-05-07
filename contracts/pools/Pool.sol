// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "contracts/lib/Token.sol";
import "contracts/lib/PoolBalanceLib.sol";
import "contracts/lib/UncheckedMemory.sol";
import "contracts/interfaces/IVault.sol";
import "contracts/interfaces/ISwap.sol";
import "contracts/interfaces/IAuthorizer.sol";
import "contracts/VaultStorage.sol";
import "./Satellite.sol";

/**
 * @dev a base contract for pools.
 *
 * - holds pool-specific slot of vault's storage as an immutable value.
 * - provides getters for the slot.
 *
 */
abstract contract Pool is IPool, Satellite {
    using PoolBalanceLib for PoolBalance;
    using UncheckedMemory for bytes32[];
    using UncheckedMemory for Token[];

    address immutable selfAddr;

    constructor(
        IVault vault_,
        address selfAddr_,
        address factory
    ) Satellite(vault_, factory) {
        selfAddr = selfAddr_;
    }

    /**
     * pool balance is stored as two uint128; poolBalance and gaugeBalance.
     */

    function _getPoolBalance(Token token) internal view returns (uint256) {
        return vault.getPoolBalance(selfAddr, token);
    }

    function _getGaugeBalance(Token token) internal view returns (uint256) {
        return vault.getGaugeBalance(selfAddr, token);
    }

    function _getPoolBalances(
        Token[] memory tokens
    ) internal view returns (uint256[] memory ret2) {
        uint256[] memory ret = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            ret[i] = vault.getPoolBalance(selfAddr, tokens[i]);
        }
    }
    function poolParams()
        external
        view
        virtual
        override
        returns (bytes memory)
    {
        return "";
    }
}
