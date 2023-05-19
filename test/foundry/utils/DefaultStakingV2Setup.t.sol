// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/StakingTestHelpers.t.sol";
import "../utils/Constants.t.sol";

contract DefaultStakingV2Setup is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public override virtual {
        super.setUp();

        switchToStakingV2();
    }
}
