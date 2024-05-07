// SPDX-License-Identifier: AUNLICENSED
pragma solidity ^0.8.0;

import {Token} from "contracts/lib/Token.sol";

// solidity by default perform bound check for every array access.
// we define functions for unchecked access here
library UncheckedMemory {
    using UncheckedMemory for bytes32[];
    using UncheckedMemory for uint256[];
    using UncheckedMemory for Token[];

    function u(bytes32[] memory self, uint256 i) internal view returns (bytes32 ret) {
        assembly ("memory-safe") {
            ret := mload(add(self, mul(32, add(i, 1))))
        }
    }

    function u(bytes32[] memory self, uint256 i, bytes32 v) internal view {
        assembly ("memory-safe") {
            mstore(add(self, mul(32, add(i, 1))), v)
        }
    }

    function u(uint256[] memory self, uint256 i) internal view returns (uint256 ret) {
        assembly ("memory-safe") {
            ret := mload(add(self, mul(32, add(i, 1))))
        }
    }

    function u(uint256[] memory self, uint256 i, uint256 v) internal view {
        assembly ("memory-safe") {
            mstore(add(self, mul(32, add(i, 1))), v)
        }
    }

    function u(int128[] memory self, uint256 i) internal view returns (int128 ret) {
        assembly ("memory-safe") {
            ret := mload(add(self, mul(32, add(i, 1))))
        }
    }

    function u(int128[] memory self, uint256 i, int128 v) internal view {
        assembly ("memory-safe") {
            mstore(add(self, mul(32, add(i, 1))), v)
        }
    }

    // uc instead u for calldata array; as solidity does not support type-location overloading.
    function uc(Token[] calldata self, uint256 i) internal view returns (Token ret) {
        assembly ("memory-safe") {
            ret := calldataload(add(self.offset, mul(32, i)))
        }
    }

    function u(Token[] memory self, uint256 i) internal view returns (Token ret) {
        assembly ("memory-safe") {
            ret := mload(add(self, mul(32, add(i, 1))))
        }
    }

    function u(Token[] memory self, uint256 i, Token v) internal view {
        assembly ("memory-safe") {
            mstore(add(self, mul(32, add(i, 1))), v)
        }
    }
}

using UncheckedMemory for bytes32[];
using UncheckedMemory for uint256[];
using UncheckedMemory for Token[];

// binary search on sorted arrays
function _binarySearch(Token[] calldata arr, Token token) view returns (uint256) {
    if (arr.length == 0) return type(uint256).max;
    uint256 start = 0;
    uint256 end = arr.length - 1;
    unchecked {
        while (start <= end) {
            uint256 mid = start + (end - start) / 2;
            if (arr.uc(mid) == token) {
                return mid;
            } else if (arr.uc(mid) < token) {
                start = mid + 1;
            } else {
                if (mid == 0) return type(uint256).max;
                end = mid - 1;
            }
        }
    }
    return type(uint256).max;
}

// binary search on sorted arrays, memory array version
function _binarySearchM(Token[] memory arr, Token token) view returns (uint256) {
    if (arr.length == 0) return type(uint256).max;
    uint256 start = 0;
    uint256 end = arr.length - 1;
    unchecked {
        while (start <= end) {
            uint256 mid = start + (end - start) / 2;
            if (arr.u(mid) == token) {
                return mid;
            } else if (arr.u(mid) < token) {
                start = mid + 1;
            } else {
                if (mid == 0) return type(uint256).max;
                end = mid - 1;
            }
        }
    }
    return type(uint256).max;
}
