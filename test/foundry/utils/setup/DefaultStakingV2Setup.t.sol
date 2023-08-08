// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {EscrowMigratorTestHelpers} from "../../utils/helpers/EscrowMigratorTestHelpers.t.sol";
import "../../utils/Constants.t.sol";

contract DefaultStakingV2Setup is EscrowMigratorTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        super.setUp();

        switchToStakingV2();
    }
}
