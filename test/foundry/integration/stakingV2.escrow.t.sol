// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import "../utils/Constants.t.sol";

// TODO: remove from own test file?
contract StakingV2EscrowTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                    Stake Escrow Integration Tests
    //////////////////////////////////////////////////////////////*/

    function test_Escrow_Staking_Via_RewardEscrowV2_Does_Not_Increase_StakingRewardsV2_Token_Balance() public {
        uint256 initialBalance = kwenta.balanceOf(address(stakingRewardsV2));

        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        rewardEscrowV2.stakeEscrow(TEST_VALUE);

        uint256 finalBalance = kwenta.balanceOf(address(stakingRewardsV2));

        assertEq(finalBalance, initialBalance);
    }
}
