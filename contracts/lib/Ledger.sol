// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.10;

import "openzeppelin/utils/math/Math.sol";
import "./Token.sol";

struct Ledger {
    uint256 total;
    mapping(address => uint256) balances;
    mapping(Token => Emission) emissions;
}

struct Emission {
    uint256 current;
    mapping(address => uint256) snapshots;
}

library LedgerLib {
    using LedgerLib for Ledger;

    function deposit(
        Ledger storage self,
        address account,
        uint256 amount
    ) internal {
        self.total += amount;
        self.balances[account] += amount;
    }

    function shareOf(
        Ledger storage self,
        address account
    ) internal view returns (uint256) {
        if (self.total == 0) return 0;
        return (self.balances[account] * 1e18) / self.total;
    }

    function withdraw(
        Ledger storage self,
        address account,
        uint256 amount
    ) internal {
        self.total -= amount;
        self.balances[account] -= amount;
    }

    function withdrawAll(
        Ledger storage self,
        address account
    ) internal returns (uint256) {
        uint256 amount = self.balances[account];
        self.withdraw(account, amount);
        return amount;
    }

    function reward(
        Ledger storage self,
        Token emissionToken,
        uint256 amount
    ) internal {
        Emission storage emission = self.emissions[emissionToken];
        if (self.total != 0) {
            emission.current += (amount * 1e18) / self.total;
        }
    }

    function harvest(
        Ledger storage self,
        address account,
        Token emissionToken
    ) internal returns (uint256) {
        Emission storage emission = self.emissions[emissionToken];
        uint256 harvested = (self.balances[account] *
            (emission.current - emission.snapshots[account])) / 1e18;
        emission.snapshots[account] = emission.current;
        return harvested;
    }
}
