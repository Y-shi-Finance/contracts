import "openzeppelin/token/ERC20/IERC20.sol";
interface IWETH is IERC20 {
    function deposit() external payable;
    function balanceOf(address) external view returns (uint256);
    function withdraw(uint) external;
}
