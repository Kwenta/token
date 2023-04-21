// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TestHelpers} from "../utils/TestHelpers.t.sol";

contract TestHelpersTests is TestHelpers {
    function testGetPseudoRandomNumberFuzz(
        uint8 max,
        uint8 min,
        uint8 salt
    ) public {
        vm.assume(max >= min);
        uint256 result = getPseudoRandomNumber(max, min, salt);
        assertTrue(result >= min && result <= max);
    }
}
