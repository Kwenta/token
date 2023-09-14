// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";
import "../../utils/Constants.t.sol";

contract StakingRewardsV2CompoundTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Compound Function
    //////////////////////////////////////////////////////////////*/

    function test_compound() public {
        fundAndApproveAccountV2(address(this), TEST_VALUE);
        uint256 initialEscrowBalance = rewardEscrowV2.escrowedBalanceOf(address(this));

        // stake
        stakingRewardsV2.stake(TEST_VALUE);

        // configure reward rate
        addNewRewardsToStakingRewardsV2(TEST_VALUE);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // compound rewards
        stakingRewardsV2.compound();

        // check reward escrow balance increased
        uint256 finalEscrowBalance = rewardEscrowV2.escrowedBalanceOf(address(this));
        assertGt(finalEscrowBalance, initialEscrowBalance);

        // check all escrowed rewards were staked
        uint256 totalRewards = finalEscrowBalance - initialEscrowBalance;
        assertEq(totalRewards, stakingRewardsV2.escrowedBalanceOf(address(this)));
        assertEq(totalRewards + TEST_VALUE, stakingRewardsV2.balanceOf(address(this)));
        assertEq(rewardEscrowV2.unstakedEscrowedBalanceOf(address(this)), 0);
    }

    function test_compound_Fuzz(uint32 initialStake, uint32 newRewards) public {
        vm.assume(initialStake > 0);
        // need reward to be greater than duration so that reward rate is above 0
        vm.assume(newRewards > stakingRewardsV2.rewardsDuration());

        fundAndApproveAccountV2(address(this), initialStake);

        uint256 initialEscrowBalance = rewardEscrowV2.escrowedBalanceOf(address(this));

        // stake
        stakingRewardsV2.stake(initialStake);

        // configure reward rate
        addNewRewardsToStakingRewardsV2(newRewards);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // compound rewards
        stakingRewardsV2.compound();

        // check reward escrow balance increased
        uint256 finalEscrowBalance = rewardEscrowV2.escrowedBalanceOf(address(this));
        assertGt(finalEscrowBalance, initialEscrowBalance);

        // check all escrowed rewards were staked
        uint256 totalRewards = finalEscrowBalance - initialEscrowBalance;
        assertEq(totalRewards, stakingRewardsV2.escrowedBalanceOf(address(this)));
        assertEq(totalRewards + initialStake, stakingRewardsV2.balanceOf(address(this)));
        assertEq(rewardEscrowV2.unstakedEscrowedBalanceOf(address(this)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            Access Control
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_compound_Anothers_Rewards() public {
        fundAndApproveAccountV2(address(this), TEST_VALUE);

        // stake
        stakingRewardsV2.stake(TEST_VALUE);

        // configure reward rate
        addNewRewardsToStakingRewardsV2(TEST_VALUE);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // compound rewards from another account
        vm.expectRevert(IStakingRewardsV2.AmountZero.selector);
        vm.prank(user1);
        stakingRewardsV2.compound();
    }

    /*//////////////////////////////////////////////////////////////
                            Events
    //////////////////////////////////////////////////////////////*/

    function test_compound_Events() public {
        fundAndApproveAccountV2(address(this), TEST_VALUE);

        // stake
        stakingRewardsV2.stake(TEST_VALUE);

        // configure reward rate
        addNewRewardsToStakingRewardsV2(1 weeks);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // expect events
        vm.expectEmit(true, true, false, true);
        emit RewardPaid(address(this), 1 weeks);
        vm.expectEmit(true, true, false, true);
        emit EscrowStaked(address(this), 1 weeks);

        // compound rewards
        stakingRewardsV2.compound();
    }
}
