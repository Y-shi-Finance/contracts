import "openzeppelin/token/ERC20/IERC20.sol";
IERC20Rebasing constant BLAST_USDB = IERC20Rebasing(
    0x4300000000000000000000000000000000000003
);
IERC20Rebasing constant BLAST_WETH = IERC20Rebasing(
    0x4300000000000000000000000000000000000004
);

interface IERC20Rebasing is IERC20 {
    enum YieldMode {
        AUTOMATIC,
        VOID,
        CLAIMABLE
    }

    function configure(YieldMode) external returns (uint256);

    function claim(
        address recipient,
        uint256 amount
    ) external returns (uint256);

    function getClaimableAmount(
        address account
    ) external view returns (uint256);

    function price() external view returns (uint256);
    function sharePrice() external view returns (uint256);
}
