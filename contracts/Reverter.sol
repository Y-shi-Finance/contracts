contract Reverter {
    error BlockNumber(uint256 n);

    fallback() external payable {
        revert BlockNumber(block.number);
    }
}
