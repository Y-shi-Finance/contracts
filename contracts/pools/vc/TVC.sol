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

contract TVC is IVC, PoolWithLPToken, ISwap, SatelliteUpgradeable {
    uint256 constant DECAY = 999999991712067125; // (0.995)^(1/(seconds in a week)) * 1e18
    uint256 constant START = 1700024400;
    uint256 constant INITIAL_SUPPLY = 6_000_000e18;

    using TokenLib for Token;
    using SafeCast for uint256;
    using SafeCast for int256;

    uint128 _totalSupply;
    uint128 lastEmission;

    address immutable veVC;
    bool initialized;
    bool initialMint;

    constructor(address selfAddr, IVault vault_, Token, address veVC_) Pool(vault_, selfAddr, address(this)) {
        veVC = veVC_;
    }
    function emissionStarted() external view returns (bool) {return true;}

    function totalSupply() public view override(IERC20, PoolWithLPToken) returns (uint256) {
        return _totalSupply;
    }

    function initialize() external {
        if (!initialized) {
            lastEmission = uint128(block.timestamp);
            PoolWithLPToken._initialize("Telos Velocore", "TVC");
            initialized = true;
        }
    }

    /**
     * the emission schedule depends on total supply of veVC + VC.
     * therefore, on veVC migration, this function should be called to nofity the change.
     */
    function notifyMigration(uint128 n) external {
        require(msg.sender == veVC);
        _totalSupply += n;
        _balanceOf[address(vault)] += n; // mint vc to the vault to simulate vc locking.
        _simulateMint(n);
    }

    /**
     * called by the vault.
     * (maxSupply - mintedSupply) decays 1% by every week.
     * @return newlyMinted amount of VCs to be distributed to gauges
     */
    function dispense() external onlyVault returns (uint256) {
        unchecked {
            uint256 emitted;

            if (lastEmission < START) {
                lastEmission = uint128(Math.min(block.timestamp, START));
            }
            if (lastEmission == block.timestamp) return 0;

            if (_totalSupply < 10_000_000e18) {
                uint256 decay1e18 = 1e18 - rpow(DECAY, block.timestamp - lastEmission, 1e18);
                emitted = (decay1e18 * (14_000_000e18 - _totalSupply)) / 1e18;
            } else {
                emitted = (block.timestamp - lastEmission) * 0.03306878306e18;
            }

            lastEmission = uint128(block.timestamp);
            _totalSupply += uint128(emitted);
            _simulateMint(emitted);
            return emitted;
        }
    }

    /**
     * VC emission rate per second
     */
    function emissionRate() external view override returns (uint256) {
        if (block.timestamp < START) return 0;
        if (_totalSupply > 10_000_000e18) return 0.03306878306e18;
        uint256 a = ((14_000_000e18 - _totalSupply) * rpow(DECAY, block.timestamp - lastEmission, 1e18)) / 1e18;

        return a - ((a * DECAY) / 1e18);
    }

    function velocore__execute(address user, Token[] calldata tokens, int128[] memory r, bytes calldata)
        external
        onlyVault
        returns (int128[] memory, int128[] memory)
    {
        require(!initialMint && user == address(uint160(uint256(_readVaultStorage(SSLOT_HYPERCORE_TREASURY)))));
        require(tokens.length == 1 && tokens[0] == toToken(this));

        initialMint = true;
        r[0] = -INITIAL_SUPPLY.toInt256().toInt128();
        _totalSupply += uint128(INITIAL_SUPPLY);
        _simulateMint(INITIAL_SUPPLY);
        return (new int128[](1), r);
    }

    function swapType() external view override returns (string memory) {
        return "VC";
    }

    function listedTokens() external view override returns (Token[] memory ret) {
        ret = new Token[](0);
    }

    function lpTokens() external view override returns (Token[] memory ret) {
        ret = new Token[](1);
        ret[0] = toToken(this);
    }

    function underlyingTokens(Token lp) external view override returns (Token[] memory) {
        return new Token[](0);
    }
}
