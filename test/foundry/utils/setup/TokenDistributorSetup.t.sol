// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {EscrowMigratorTestHelpers} from "../../utils/helpers/EscrowMigratorTestHelpers.t.sol";
import {TokenDistributor} from "../../../../contracts/TokenDistributor.sol";
import "../../utils/Constants.t.sol";

contract TokenDistributorSetup is EscrowMigratorTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    TokenDistributor tokenDistributor;

    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        super.setUp();
        switchToStakingV2();
        tokenDistributor = new TokenDistributor({
            _rewardsToken: address(kwenta),
            _stakingRewardsV2: address(stakingRewardsV2),
            _daysToOffsetBy: 0
        });
    }
}
