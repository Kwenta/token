// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

contract TestHelpers is Test {
    uint256 public userNonce;
    uint256 public nonce;

    /// @dev create a new user address
    function createUser() public returns (address) {
        userNonce++;
        return vm.addr(userNonce);
    }

    /// @dev assert two numbers are close to each other
    /// @param a first number
    /// @param b second number
    /// @param tolerance maximum difference between a and b allowed
    function assertCloseTo(uint256 a, uint256 b, uint256 tolerance) public {
        if (tolerance == 0) {
            assertEq(a, b);
        } else if (a > b) {
            assertLe(a - b, tolerance, "a - b <= tolerance");
        } else if (b > a) {
            assertLe(b - a, tolerance, "b - a <= tolerance");
        }
    }

    /// @dev check if two numbers are close to each other
    /// @param a first number
    /// @param b second number
    /// @param tolerance maximum difference between a and b allowed
    /// @return result true if a and b are close to each other within the tolerance
    function closeTo(uint256 a, uint256 b, uint256 tolerance) public pure returns (bool) {
        if (a == b) return true;
        if (a > b) return a - b <= tolerance;
        else return b - a <= tolerance;
    }

    /// @dev get minimum of two numbers
    /// @param a first number
    /// @param b second number
    /// @return result minimum of a and b
    function min(uint256 a, uint256 b) public pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev  get psuedorandom bool
    /// @return result psuedorandom bool
    function flipCoin() public returns (bool) {
        return (uint256(keccak256(abi.encodePacked(++nonce))) % 2) == 1;
    }

    /// @dev get psuedorandom bool with salt
    /// @param salt salt to influence random number
    /// @return result psuedorandom bool
    function flipCoin(uint256 salt) public returns (bool) {
        return (uint256(keccak256(abi.encodePacked(++nonce, salt))) % 2) == 1;
    }

    /// @dev get psuedorandom uint256
    /// @param _max max value
    /// @param _min min value
    /// @param salt salt to influence random number
    /// @return result psuedorandom number
    function getPseudoRandomNumber(uint256 _max, uint256 _min, uint256 salt)
        internal
        returns (uint256 result)
    {
        require(_min <= _max, "min must be <= max");
        if (_max == _min) return _max;

        uint256 effectiveMax = type(uint256).max == _max ? type(uint256).max : _max + 1;

        if (_min == 0) {
            result = uint256(keccak256(abi.encodePacked(++nonce, salt))) % effectiveMax;
        } else {
            while (result < _min) {
                result = uint256(keccak256(abi.encodePacked(++nonce, salt))) % effectiveMax;
            }
        }
    }
}
