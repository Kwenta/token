// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {DefaultStakingRewardsV2Setup} from "../utils/DefaultStakingRewardsV2Setup.t.sol";
import "../utils/Constants.t.sol";

contract StakingV2EscrowTests is DefaultStakingRewardsV2Setup {
    /*//////////////////////////////////////////////////////////////
                                stakeEscrow
    //////////////////////////////////////////////////////////////*/

    function testEscrowStakingViaRewardEscrowDoesNotIncreaseTokenBalance() public {
        uint256 initialBalance = kwenta.balanceOf(address(stakingRewardsV2));

        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        rewardEscrowV2.stakeEscrow(TEST_VALUE);

        // check balance increased
        assertEq(
            kwenta.balanceOf(address(stakingRewardsV2)),
            initialBalance
        );
    }
}
