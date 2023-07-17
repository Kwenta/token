// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {IERC20} from "../../../../contracts/interfaces/IERC20.sol";
import "../../utils/Constants.t.sol";

contract StakingRewardsV2FlashAttackTest is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                        Constructor & Settings
    //////////////////////////////////////////////////////////////*/

    // TODO: update to ensure that a user CANNOT flash attack
    function test_Can_Flash_Attack() public {
        uint256 totalNewRewards = 100_000 ether;
        fundAccountAndStakeV2(user1, 100 ether);
        fundAccountAndStakeV2(user2, 100 ether);
        addNewRewardsToStakingRewardsV2(totalNewRewards);
        vm.warp(block.timestamp + 4 weeks);

        // flash attack
        uint256 fundsBorrwedViaFlashLoan = 100_000 ether;
        fundAccountAndStakeV1(user3, fundsBorrwedViaFlashLoan);
        vm.prank(user3);
        stakingRewardsV2.getReward();

        uint256 escrowedBalance = rewardEscrowV2.escrowedBalanceOf(user3);
        // users claimed at least 99.8% of all the rewards
        assertCloseTo(escrowedBalance, totalNewRewards, 200 ether);
        // then user would pay back the flash loan
    }
}
