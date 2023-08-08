// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";

contract TestHelpers is Test {
    uint256 internal userNonce;
    uint256 internal nonce;

    string private checkpointLabel;
    uint256 private checkpointGasLeft = 1; // Start the slot warm.

    /// @dev start measuring gas consumption
    /// @param label the string to print next to the gas consumed
    /// when stopping measuring
    function startMeasuringGas(string memory label) internal virtual {
        checkpointLabel = label;

        checkpointGasLeft = gasleft();
    }

    /// @dev stop measuring gas consumption
    /// @return gasDelta the gas consumed since startMeasuringGas was called
    /// @dev Add 21k to this amount to get gas used in a transaction
    function stopMeasuringGas() internal virtual returns (uint256 gasDelta) {
        uint256 checkpointGasLeft2 = gasleft();

        // Subtract 100 to account for the warm SLOAD in startMeasuringGas.
        gasDelta = checkpointGasLeft - checkpointGasLeft2 - 100;

        emit log_named_uint(string(abi.encodePacked(checkpointLabel, " Gas")), gasDelta);
    }

    /// @dev create a new user address
    function createUser() internal returns (address) {
        userNonce++;
        return vm.addr(userNonce);
    }

    /// @dev assert two numbers are close to each other
    /// @param _a first number
    /// @param _b second number
    /// @param _tolerance maximum difference between a and b allowed
    function assertCloseTo(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        if (_tolerance == 0) {
            assertEq(_a, _b);
        } else if (_a > _b) {
            assertLe(_a - _b, _tolerance, "a - b <= tolerance");
        } else if (_b > _a) {
            assertLe(_b - _a, _tolerance, "b - a <= tolerance");
        }
    }

    /// @dev check if two numbers are close to each other
    /// @param _a first number
    /// @param _b second number
    /// @param _tolerance maximum difference between a and b allowed
    /// @return result true if a and b are close to each other within the tolerance
    function closeTo(uint256 _a, uint256 _b, uint256 _tolerance) internal pure returns (bool) {
        if (_a == _b) return true;
        if (_a > _b) return _a - _b <= _tolerance;
        else return _b - _a <= _tolerance;
    }

    /// @dev get minimum of two numbers
    /// @param _a first number
    /// @param _b second number
    /// @return result minimum of a and b
    function min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _a : _b;
    }

    /// @dev  get psuedorandom bool
    /// @return result psuedorandom bool
    function flipCoin() internal returns (bool) {
        return (uint256(keccak256(abi.encodePacked(++nonce))) % 2) == 1;
    }

    /// @dev get psuedorandom bool with salt
    /// @param _salt salt to influence random number
    /// @return result psuedorandom bool
    function flipCoin(uint256 _salt) internal returns (bool) {
        return (uint256(keccak256(abi.encodePacked(++nonce, _salt))) % 2) == 1;
    }

    /// @dev get psuedorandom uint256
    /// @param _max max value
    /// @param _min min value
    /// @param _salt salt to influence random number
    /// @return result psuedorandom number
    function getPseudoRandomNumber(uint256 _max, uint256 _min, uint256 _salt)
        internal
        returns (uint256 result)
    {
        require(_min <= _max, "min must be <= max");
        if (_max == _min) return _max;

        uint256 effectiveMax = type(uint256).max == _max ? type(uint256).max : _max + 1;

        if (_min == 0) {
            result = uint256(keccak256(abi.encodePacked(++nonce, _salt))) % effectiveMax;
        } else {
            while (result < _min) {
                result = uint256(keccak256(abi.encodePacked(++nonce, _salt))) % effectiveMax;
            }
        }
    }

    function goForward(uint256 time) internal {
        vm.warp(block.timestamp + time);
        uint256 blockNumber = time / 12;
        vm.roll(block.number + blockNumber);
    }
}
