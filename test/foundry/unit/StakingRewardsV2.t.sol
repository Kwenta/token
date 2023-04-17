// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";

uint256 constant INITIAL_SUPPLY = 313373 ether;

contract StakingRewardsV2Test is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                        Constructor & Settings
    //////////////////////////////////////////////////////////////*/

    function testTokenSet() public {
        address token = address(stakingRewardsV2.token());
        assertEq(token, address(kwenta));
    }

    function testOwnerSet() public {
        address owner = stakingRewardsV2.owner();
        assertEq(owner, address(this));
    }

    function testRewardEscrowSet() public {
        address rewardEscrowAddress = address(stakingRewardsV2.rewardEscrow());
        assertEq(rewardEscrowAddress, address(rewardEscrow));
    }

    function testSupplyScheduleSet() public {
        address supplyScheduleAddress = address(
            stakingRewardsV2.supplySchedule()
        );
        assertEq(supplyScheduleAddress, address(supplySchedule));
    }

    /*//////////////////////////////////////////////////////////////
                        Function Permissions
    //////////////////////////////////////////////////////////////*/

    function testOnlySupplyScheduleCanCallNotifyRewardAmount() public {
        vm.expectRevert("StakingRewards: Only Supply Schedule");
        stakingRewardsV2.notifyRewardAmount(1 ether);
    }

    // TODO: test happy path - see fast forward in hardhat tests
    function testOnlyOwnerCanCallSetRewardsDuration() public {
        vm.prank(user1);
        vm.expectRevert("Only the contract owner may perform this action");
        stakingRewardsV2.setRewardsDuration(1 weeks);
    }

    function testOnlyOwnerCanCallRecoverERC20() public {
        vm.prank(user1);
        vm.expectRevert("Only the contract owner may perform this action");
        stakingRewardsV2.recoverERC20(address(kwenta), 0);
    }

    function testCannotUnstakeStakingToken() public {
        vm.expectRevert("StakingRewards: Cannot unstake the staking token");
        stakingRewardsV2.recoverERC20(address(kwenta), 0);
    }

    function testOnlyRewardEscrowCanCallStakeEscrow() public {
        vm.expectRevert("StakingRewards: Only Reward Escrow");
        stakingRewardsV2.stakeEscrow(address(this), 1 ether);
    }

    function testOnlyRewardEscrowCanCallUnStakeEscrow() public {
        vm.expectRevert("StakingRewards: Only Reward Escrow");
        stakingRewardsV2.unstakeEscrow(address(this), 1 ether);
    }

    function testCannotUnStakeEscrowInvalidAmount() public {
        vm.prank(address(rewardEscrow));
        vm.expectRevert("StakingRewards: Invalid Amount");
        stakingRewardsV2.unstakeEscrow(address(this), 1 ether);
    }

    function testOnlyOwnerCanPauseContract() public {
        // attempt to pause
        vm.prank(user1);
        vm.expectRevert("Only the contract owner may perform this action");
        stakingRewardsV2.pauseStakingRewards();

        // pause
        stakingRewardsV2.pauseStakingRewards();

        // attempt to unpause
        vm.prank(user1);
        vm.expectRevert("Only the contract owner may perform this action");
        stakingRewardsV2.unpauseStakingRewards();

        // unpause
        stakingRewardsV2.unpauseStakingRewards();
    }

    function testOnlyOwnerCanNominateNewOwner() public {
        // attempt to nominate new owner
        vm.prank(user1);
        vm.expectRevert("Only the contract owner may perform this action");
        stakingRewardsV2.nominateNewOwner(address(this));

        // nominate new owner
        stakingRewardsV2.nominateNewOwner(address(user1));

        // attempt to accept ownership
        vm.prank(user2);
        vm.expectRevert(
            "You must be nominated before you can accept ownership"
        );
        stakingRewardsV2.acceptOwnership();

        // accept ownership
        vm.prank(user1);
        stakingRewardsV2.acceptOwnership();

        // check ownership
        assertEq(stakingRewardsV2.owner(), address(user1));
    }

    /*//////////////////////////////////////////////////////////////
                                Pausable
    //////////////////////////////////////////////////////////////*/

    // function testCannotStakeWhenPaused() public {
    //     // pause
    //     stakingRewardsV2.pauseStakingRewards();

    //     // fund so that staking would succeed if not paused
    //     fundAndApproveAccount(address(this), 1 ether);

    //     // attempt to stake
    //     vm.expectRevert("Pausable: paused");
    //     stakingRewardsV2.stake(1 ether);
    // }
}
