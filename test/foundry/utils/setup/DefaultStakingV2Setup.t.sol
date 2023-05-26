// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../../utils/helpers/StakingTestHelpers.t.sol";
import "../../utils/Constants.t.sol";

contract DefaultStakingV2Setup is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        super.setUp();

        switchToStakingV2();
    }
}
