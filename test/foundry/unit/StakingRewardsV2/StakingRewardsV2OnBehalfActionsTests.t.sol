// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";
import "../../utils/Constants.t.sol";

contract StakingRewardsV2OnBehalfActionsTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Access Control
    //////////////////////////////////////////////////////////////*/

    function test_Only_Approved_Can_Call_getRewardOnBehalf() public {
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        addNewRewardsToStakingRewardsV2(1 weeks);
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve user1 as operator
        stakingRewardsV2.approveOperator(user1, true);

        // claim rewards on behalf as user2
        vm.prank(user2);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getRewardOnBehalf(address(this));
    }

    function test_Cannot_Get_Reward_On_Behalf_Of_Zero_Address() public {
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        addNewRewardsToStakingRewardsV2(1 weeks);
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve user1 as operator
        stakingRewardsV2.approveOperator(user1, true);

        // claim rewards on behalf as user2
        vm.prank(user1);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getRewardOnBehalf(address(0));
    }

    function test_Only_Approved_Can_Call_getRewardOnBehalf_Fuzz(
        uint32 fundingAmount,
        uint32 newRewards,
        address owner,
        address operator,
        address caller
    ) public {
        vm.assume(fundingAmount > 0);
        vm.assume(newRewards > stakingRewardsV2.rewardsDuration());
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(caller != address(0));
        vm.assume(owner != operator);
        vm.assume(owner != caller);
        vm.assume(operator != caller);
        vm.assume(operator != stakingRewardsV2.owner());

        fundAccountAndStakeV2(owner, fundingAmount);
        addNewRewardsToStakingRewardsV2(newRewards);
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // claim rewards on behalf of owner from non-operator
        vm.prank(caller);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getRewardOnBehalf(address(this));
    }

    function test_Only_Approved_Can_Call_stakeEscrowOnBehalf() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);

        // approve user1 as operator
        stakingRewardsV2.approveOperator(user1, true);

        // stake escrow on behalf as user2
        vm.prank(user2);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.stakeEscrowOnBehalf(address(this), TEST_VALUE);
    }

    function test_Only_Approved_Can_Call_stakeEscrowOnBehalf_Fuzz(
        uint32 escrowAmount,
        uint24 duration,
        address owner,
        address operator,
        address caller
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(duration >= stakingRewardsV2.cooldownPeriod());
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(caller != address(0));
        vm.assume(owner != operator);
        vm.assume(owner != caller);
        vm.assume(operator != caller);
        vm.assume(operator != stakingRewardsV2.owner());

        createRewardEscrowEntryV2(owner, escrowAmount, duration);

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // claim rewards on behalf of owner from non-operator
        vm.prank(caller);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.stakeEscrowOnBehalf(owner, escrowAmount);
    }

    function test_Only_Approved_Can_Call_compoundOnBehalf() public {
        fundAndApproveAccountV2(address(this), TEST_VALUE);

        // configure reward rate
        addNewRewardsToStakingRewardsV2(TEST_VALUE);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // approve user1 as operator
        stakingRewardsV2.approveOperator(user1, true);

        // stake escrow on behalf as user2
        vm.prank(user2);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.compoundOnBehalf(address(this));
    }

    function test_Only_Approved_Can_Call_compoundOnBehalf_Fuzz(
        uint32 initialStake,
        uint32 newRewards,
        address owner,
        address operator,
        address caller
    ) public {
        vm.assume(initialStake > 0);
        vm.assume(newRewards > 0);
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(caller != address(0));
        vm.assume(owner != operator);
        vm.assume(owner != caller);
        vm.assume(operator != caller);
        vm.assume(operator != stakingRewardsV2.owner());

        fundAndApproveAccountV2(owner, TEST_VALUE);

        // configure reward rate
        addNewRewardsToStakingRewardsV2(TEST_VALUE);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // claim rewards on behalf of owner from non-operator
        vm.prank(caller);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.compoundOnBehalf(owner);
    }

    function test_Cannot_Approve_Self() public {
        vm.expectRevert(IStakingRewardsV2.CannotApproveSelf.selector);
        stakingRewardsV2.approveOperator(address(this), true);
    }

    function test_Cannot_Approve_Self_Fuzz(address owner) public {
        vm.expectRevert(IStakingRewardsV2.CannotApproveSelf.selector);
        vm.prank(owner);
        stakingRewardsV2.approveOperator(owner, true);
    }

    /*//////////////////////////////////////////////////////////////
                        Get Reward On Behalf
    //////////////////////////////////////////////////////////////*/

    function test_getRewardOnBehalf() public {
        fundAccountAndStakeV2(address(this), TEST_VALUE);

        // assert initial rewards are 0
        assertEq(rewardEscrowV2.escrowedBalanceOf(address(this)), 0);
        assertEq(rewardEscrowV2.escrowedBalanceOf(user1), 0);

        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        addNewRewardsToStakingRewardsV2(1 weeks);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // claim rewards on behalf
        vm.prank(user1);
        stakingRewardsV2.getRewardOnBehalf(address(this));

        // check rewards
        assertEq(rewardEscrowV2.escrowedBalanceOf(address(this)), 1 weeks);
        assertEq(rewardEscrowV2.escrowedBalanceOf(user1), 0);
    }

    function test_getRewardOnBehalf_Fuzz(
        uint32 fundingAmount,
        uint32 newRewards,
        address owner,
        address operator
    ) public {
        vm.assume(fundingAmount > 0);
        vm.assume(newRewards > stakingRewardsV2.rewardsDuration());
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(operator != owner);

        fundAccountAndStakeV2(owner, fundingAmount);

        // assert initial rewards are 0
        assertEq(rewardEscrowV2.escrowedBalanceOf(owner), 0);
        assertEq(rewardEscrowV2.escrowedBalanceOf(operator), 0);

        // send in rewards
        addNewRewardsToStakingRewardsV2(newRewards);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // claim rewards on behalf
        vm.prank(operator);
        stakingRewardsV2.getRewardOnBehalf(owner);

        // check rewards
        assertGt(rewardEscrowV2.escrowedBalanceOf(owner), 0);
        assertEq(rewardEscrowV2.escrowedBalanceOf(operator), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        Stake Escrow On Behalf
    //////////////////////////////////////////////////////////////*/

    function test_stakeEscrowOnBehalf() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);

        // assert initial escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), 0);
        assertEq(stakingRewardsV2.escrowedBalanceOf(user1), 0);

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // stake escrow on behalf
        vm.prank(user1);
        stakingRewardsV2.stakeEscrowOnBehalf(address(this), TEST_VALUE);

        // check final escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), TEST_VALUE);
        assertEq(stakingRewardsV2.escrowedBalanceOf(user1), 0);
    }

    function test_stakeEscrowOnBehalf_Fuzz(
        address owner,
        address operator,
        uint32 escrowAmount,
        uint24 duration
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(duration >= stakingRewardsV2.cooldownPeriod());
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(owner != operator);

        createRewardEscrowEntryV2(owner, escrowAmount, duration);

        // assert initial escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(owner), 0);
        assertEq(stakingRewardsV2.escrowedBalanceOf(operator), 0);

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // stake escrow on behalf
        vm.prank(operator);
        stakingRewardsV2.stakeEscrowOnBehalf(owner, escrowAmount);

        // check final escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(owner), escrowAmount);
        assertEq(stakingRewardsV2.escrowedBalanceOf(operator), 0);
    }

    function test_Should_Revert_If_Staker_Has_No_Escrow() public {
        stakingRewardsV2.approveOperator(user1, true);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(IStakingRewardsV2.InsufficientUnstakedEscrow.selector, 0)
        );
        stakingRewardsV2.stakeEscrowOnBehalf(address(this), 1 ether);
    }

    function test_Cannot_stakeEscrowOnBehalf_Too_Much() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // stake escrow on behalf
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakingRewardsV2.InsufficientUnstakedEscrow.selector, TEST_VALUE
            )
        );
        stakingRewardsV2.stakeEscrowOnBehalf(address(this), TEST_VALUE + 1);
    }

    function test_Cannot_stakeEscrowOnBehalf_Too_Much_Fuzz(
        address owner,
        address operator,
        uint32 escrowAmount,
        uint32 amountToEscrowStake,
        uint24 duration
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(amountToEscrowStake > escrowAmount);
        vm.assume(duration >= stakingRewardsV2.cooldownPeriod());
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(owner != operator);

        createRewardEscrowEntryV2(owner, escrowAmount, duration);

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // stake escrow on behalf
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStakingRewardsV2.InsufficientUnstakedEscrow.selector, escrowAmount
            )
        );
        stakingRewardsV2.stakeEscrowOnBehalf(owner, amountToEscrowStake);
    }

    /*//////////////////////////////////////////////////////////////
                    Get Reward And Stake On Behalf
    //////////////////////////////////////////////////////////////*/

    function test_Get_Reward_And_Stake_On_Behalf() public {
        fundAccountAndStakeV2(address(this), TEST_VALUE);

        // assert initial rewards are 0
        assertEq(rewardEscrowV2.escrowedBalanceOf(address(this)), 0);
        assertEq(rewardEscrowV2.escrowedBalanceOf(user1), 0);

        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        addNewRewardsToStakingRewardsV2(1 weeks);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // claim rewards on behalf
        vm.prank(user1);
        stakingRewardsV2.getRewardOnBehalf(address(this));

        // check rewards
        assertEq(rewardEscrowV2.escrowedBalanceOf(address(this)), 1 weeks);
        assertEq(rewardEscrowV2.escrowedBalanceOf(user1), 0);

        // stake escrow on behalf
        vm.prank(user1);
        stakingRewardsV2.stakeEscrowOnBehalf(address(this), 1 weeks);

        // check final escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), 1 weeks);
        assertEq(stakingRewardsV2.escrowedBalanceOf(user1), 0);
    }

    function test_Get_Reward_And_Stake_On_Behalf_Fuzz(
        uint32 fundingAmount,
        uint32 newRewards,
        address owner,
        address operator
    ) public {
        vm.assume(fundingAmount > 0);
        vm.assume(newRewards > stakingRewardsV2.rewardsDuration());
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(operator != owner);

        fundAccountAndStakeV2(owner, fundingAmount);

        // assert initial rewards are 0
        assertEq(rewardEscrowV2.escrowedBalanceOf(owner), 0);
        assertEq(rewardEscrowV2.escrowedBalanceOf(operator), 0);

        // send in rewards
        addNewRewardsToStakingRewardsV2(newRewards);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // claim rewards on behalf
        vm.prank(operator);
        stakingRewardsV2.getRewardOnBehalf(owner);

        // check rewards
        uint256 rewardEscrowBalance = rewardEscrowV2.escrowedBalanceOf(owner);
        assertGt(rewardEscrowBalance, 0);
        assertEq(rewardEscrowV2.escrowedBalanceOf(operator), 0);

        // stake escrow on behalf
        vm.prank(operator);
        stakingRewardsV2.stakeEscrowOnBehalf(owner, rewardEscrowBalance);

        // check final escrowed balances
        assertEq(stakingRewardsV2.escrowedBalanceOf(owner), rewardEscrowBalance);
        assertEq(stakingRewardsV2.escrowedBalanceOf(operator), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            Compound On Behalf
    //////////////////////////////////////////////////////////////*/

    function test_compoundOnBehalf() public {
        fundAndApproveAccountV2(address(this), TEST_VALUE);
        uint256 initialEscrowBalance = rewardEscrowV2.escrowedBalanceOf(address(this));

        // stake
        stakingRewardsV2.stake(TEST_VALUE);

        // configure reward rate
        addNewRewardsToStakingRewardsV2(TEST_VALUE);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // compound rewards on behalf
        vm.prank(user1);
        stakingRewardsV2.compoundOnBehalf(address(this));

        // check reward escrow balance increased
        uint256 finalEscrowBalance = rewardEscrowV2.escrowedBalanceOf(address(this));
        assertGt(finalEscrowBalance, initialEscrowBalance);

        // check all escrowed rewards were staked
        uint256 totalRewards = finalEscrowBalance - initialEscrowBalance;
        assertEq(totalRewards, stakingRewardsV2.escrowedBalanceOf(address(this)));
        assertEq(totalRewards + TEST_VALUE, stakingRewardsV2.balanceOf(address(this)));
        assertEq(rewardEscrowV2.unstakedEscrowedBalanceOf(address(this)), 0);
    }

    function test_compoundOnBehalf_Fuzz(
        uint32 initialStake,
        uint32 newRewards,
        address owner,
        address operator
    ) public {
        vm.assume(initialStake > 0);
        // need reward to be greater than duration so that reward rate is above 0
        vm.assume(newRewards > stakingRewardsV2.rewardsDuration());
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(operator != owner);

        fundAndApproveAccountV2(owner, initialStake);

        uint256 initialEscrowBalance = rewardEscrowV2.escrowedBalanceOf(owner);

        // stake
        vm.prank(owner);
        stakingRewardsV2.stake(initialStake);

        // configure reward rate
        addNewRewardsToStakingRewardsV2(newRewards);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // approve operator
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, true);

        // compound rewards on behalf
        vm.prank(operator);
        stakingRewardsV2.compoundOnBehalf(owner);

        // check reward escrow balance increased
        uint256 finalEscrowBalance = rewardEscrowV2.escrowedBalanceOf(owner);
        assertGt(finalEscrowBalance, initialEscrowBalance);

        // check all escrowed rewards were staked
        uint256 totalRewards = finalEscrowBalance - initialEscrowBalance;
        assertEq(totalRewards, stakingRewardsV2.escrowedBalanceOf(owner));
        assertEq(totalRewards + initialStake, stakingRewardsV2.balanceOf(owner));
        assertEq(rewardEscrowV2.unstakedEscrowedBalanceOf(owner), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    function test_approveOperator_Emits_Event() public {
        vm.expectEmit(true, true, true, true);
        emit OperatorApproved(address(this), user1, true);
        stakingRewardsV2.approveOperator(user1, true);
    }

    function test_approveOperator_Emits_Event_Fuzz(address owner, address operator, bool approved)
        public
    {
        vm.assume(owner != address(0));
        vm.assume(operator != address(0));
        vm.assume(owner != operator);

        vm.expectEmit(true, true, true, true);
        emit OperatorApproved(owner, operator, approved);
        vm.prank(owner);
        stakingRewardsV2.approveOperator(operator, approved);
    }

    function test_getRewardOnBehalf_Emits_Event() public {
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        addNewRewardsToStakingRewardsV2(1 weeks);
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // claim rewards on behalf
        vm.expectEmit(true, true, false, true);
        emit RewardPaid(address(this), 1 weeks);
        vm.prank(user1);
        stakingRewardsV2.getRewardOnBehalf(address(this));
    }

    function test_stakeEscrowOnBehalf_Emits_Event() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);

        // approve operator
        stakingRewardsV2.approveOperator(user1, true);

        // stake escrow on behalf
        vm.expectEmit(true, true, false, true);
        emit EscrowStaked(address(this), TEST_VALUE);
        vm.prank(user1);
        stakingRewardsV2.stakeEscrowOnBehalf(address(this), TEST_VALUE);
    }
}
