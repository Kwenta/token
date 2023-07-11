// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TestHelpers} from "./TestHelpers.t.sol";

contract TestHelpersTests is TestHelpers {
    function test_getPseudoRandomNumber_Fuzz(uint256 max, uint16 min, uint128 salt) public {
        vm.assume(max >= min);
        uint256 result = getPseudoRandomNumber(max, min, salt);
        assertTrue(result >= min && result <= max);
    }

    function test_min_Fuzz(uint256 a, uint256 b) public {
        uint256 result = min(a, b);
        assertLe(result, a);
        assertLe(result, b);
    }

    function test_closeTo_Fuzz(uint256 a, uint256 b, uint256 tolerance) public {
        bool result = closeTo(a, b, tolerance);
        if (a == b) {
            assertTrue(result);
        } else if (a > b) {
            assertTrue(result == ((a - b) <= tolerance));
        } else if (b > a) {
            assertTrue(result == ((b - a) <= tolerance));
        }
    }
}
