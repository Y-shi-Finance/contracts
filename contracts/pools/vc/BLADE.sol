// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../PoolWithLPToken.sol";
import "contracts/lib/RPow.sol";
import "contracts/interfaces/IVC.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/Math.sol";
import "../SatelliteUpgradeable.sol";

/**
 * @dev The emission token of Velocore.
 *
 * implemented as a pool. VC is its "LP" token.
 * - takes old version of VC token and gives the same amount of new VC token.
 * - when called by vault, emits VC on an exponentially decaying schedule
 *
 */

contract Blade is IVC, PoolWithLPToken, ISwap {
    uint256 constant INITIAL_SUPPLY = 80_000_000e18;

    using TokenLib for Token;
    using SafeCast for uint256;
    using SafeCast for int256;

    uint128 cumEmission;
    address immutable veVC;
    bool initialized;
    uint256[256] uinused;
    bool initialMint;

    function emissionStarted() external view returns (bool) {
        return block.timestamp > 1714197600;
    }

    constructor(
        address selfAddr,
        IVault vault_,
        address veVC_
    ) Pool(vault_, selfAddr, address(this)) {
        veVC = veVC_;
    }

    function totalSupply()
        public
        view
        override(IERC20, PoolWithLPToken)
        returns (uint256)
    {
        return INITIAL_SUPPLY + cumEmission;
    }

    function initialize() external {
        if (!initialized) {
            PoolWithLPToken._initialize("Blade", "BLADE");
            initialized = true;
        }
    }

    function notifyMigration(uint128 n) external {}

    function dispense() external onlyVault returns (uint256 minted) {
        uint256 b = emissionCurve(block.timestamp);
        minted = b - cumEmission;
        cumEmission = b.toUint128();
        if (minted > 0) {
            _simulateMint(minted);
        }
    }

    function emissionRate() external view override returns (uint256) {
        return
            emissionCurve(block.timestamp + 1) - emissionCurve(block.timestamp);
    }

    function toEmissionTime(uint256 timestamp) public pure returns (uint256) {
        if (timestamp <= 1714197600) return 0;
        return timestamp - 1714197600;
    }

    function weeklyCumEmission(uint256 w) public pure returns (uint256 cum) {
        cum +=
            (1.2e24 * (rpow(1.03e27, Math.min(14, w), 1e27) - 1e27)) /
            0.03e27;
        if (w > 14) {
            cum +=
                (
                    1.744618051580458404807796e24 * (
                        1e27 - rpow(0.99e27, w - 14, 1e27)
                    )
                ) /
                (1e27 - 0.99e27);
        }
        if (cum > 120e24) cum = 120e24;
    }

    function emissionCurve(uint256 t) public pure returns (uint256) {
        t = toEmissionTime(t);
        uint256 a = weeklyCumEmission(t / 1 weeks);
        uint256 b = weeklyCumEmission(t / 1 weeks + 1);
        return a + ((b - a) * (t % 1 weeks)) / (1 weeks);
    }

    function velocore__execute(
        address user,
        Token[] calldata tokens,
        int128[] memory r,
        bytes calldata
    ) external onlyVault returns (int128[] memory, int128[] memory) {
        revert();
    }

    function swapType() external view override returns (string memory) {
        return "VC";
    }

    function listedTokens()
        external
        view
        override
        returns (Token[] memory ret)
    {
        ret = new Token[](0);
    }

    function lpTokens() external view override returns (Token[] memory ret) {
        ret = new Token[](1);
        ret[0] = toToken(this);
    }

    function underlyingTokens(
        Token lp
    ) external view override returns (Token[] memory) {
        return new Token[](0);
    }
}
