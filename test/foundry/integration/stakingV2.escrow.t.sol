// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";

contract StakingV2EscrowTests is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                stakeEscrow
    //////////////////////////////////////////////////////////////*/

    function testEscrowStakingViaRewardEscrowDoesNotIncreaseTokenBalance() public {
        uint256 initialBalance = kwenta.balanceOf(address(stakingRewardsV2));

        vm.prank(treasury);
        kwenta.approve(address(rewardEscrow), TEST_VALUE);
        vm.prank(treasury);
        rewardEscrow.createEscrowEntry(address(this), TEST_VALUE, 52 weeks);

        rewardEscrow.stakeEscrow(TEST_VALUE);

        // check balance increased
        assertEq(
            kwenta.balanceOf(address(stakingRewardsV2)),
            initialBalance
        );
    }
}
