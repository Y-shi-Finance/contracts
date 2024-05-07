import "openzeppelin/access/Ownable.sol";
import "openzeppelin/security/ReentrancyGuard.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";
import "openzeppelin/utils/cryptography/MerkleProof.sol";
import "./VelocoreGirls.sol";

contract LinearVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    uint256 public immutable vestBeginning;
    uint256 public immutable vestDuration;

    mapping(address => uint256) public claimableTotal;
    mapping(address => uint256) public claimed;
    mapping(address => bool) public registered;

    event ClaimVesting(address addr, uint256 amount);

    constructor(IERC20 rewardToken_, uint256 vestBeginning_, uint256 vestDuration_) {
        rewardToken = rewardToken_;
        vestBeginning = vestBeginning_;
        vestDuration = vestDuration_;
    }

    function _grantVestedReward(address addr, uint256 amount) internal {
        require(!registered[addr], "already registered");
        claimableTotal[addr] = amount;
        registered[addr] = true;
    }

    function claim3(address addr) public nonReentrant returns (uint256) {
        require(registered[addr]);
        uint256 vested = 0;
        if (block.timestamp < vestBeginning) {
            vested = 0;
        } else if (block.timestamp >= vestBeginning + vestDuration) {
            vested = claimableTotal[addr];
        } else {
            vested = Math.mulDiv(claimableTotal[addr], block.timestamp - vestBeginning, vestDuration);
        }

        uint256 delta = vested - claimed[addr];
        claimed[addr] = vested;

        rewardToken.safeTransfer(addr, delta);
        emit ClaimVesting(addr, delta);
        return delta;
    }
}

contract Airdrop is LinearVesting {
    using SafeERC20 for IERC20;

    bytes32 public constant root = 0x56cf922d2b2ecc2eddf1a2edfe36ba0937d3e8f9f3c195923b652b33e18b0964;

    constructor(IERC20 rewardToken_, uint256 vestBeginning_, uint256 vestDuration_)
        LinearVesting(rewardToken_, vestBeginning_, vestDuration_)
    {}

    function claim(bytes32[] memory proof, uint256 amount) public {
        require(!registered[msg.sender], "Already claimed");

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));
        require(MerkleProof.verify(proof, root, leaf), "Invalid proof");
        rewardToken.safeTransfer(msg.sender, (amount * 3) / 10);
        _grantVestedReward(msg.sender, (amount * 7) / 10);
    }
}
