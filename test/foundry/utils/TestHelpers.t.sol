// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract TestHelpers is Test {
    uint256 public userNonce;
    uint256 public nonce;

    function createUser() public returns (address) {
        userNonce++;
        return vm.addr(userNonce);
    }

    // get psuedorandom bool
    function flipCoin() public returns (bool) {
        return (uint256(keccak256(abi.encodePacked(++nonce))) % 2) == 1;
    }

    // get psuedorandom bool with salt
    function flipCoin(uint256 salt) public returns (bool) {
        return (uint256(keccak256(abi.encodePacked(++nonce, salt))) % 2) == 1;
    }

    function min(uint256 a, uint256 b) public pure returns (uint256) {
        return a < b ? a : b;
    }

    function getPseudoRandomNumber(uint256 _max, uint256 _min, uint256 salt) internal returns (uint256 result) {
        require(_min <= _max, "min must be <= max");
        if (_max == _min) return _max;

        if (_min == 0) {
            result = uint256(keccak256(abi.encodePacked(++nonce, salt))) % (_max + 1);
        } else {
            while (result < _min) {
                result = uint256(keccak256(abi.encodePacked(++nonce, salt))) % (_max + 1);
            }
        }
    }
}
