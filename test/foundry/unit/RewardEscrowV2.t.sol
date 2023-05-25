// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import {IRewardEscrowV2} from "../../../contracts/interfaces/IRewardEscrowV2.sol";
import "../utils/Constants.t.sol";

contract RewardEscrowV2Tests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                        Deploys correctly
    //////////////////////////////////////////////////////////////*/

    function test_Should_Have_A_Kwenta_Token() public {
        assertEq(address(rewardEscrowV2.getKwentaAddress()), address(kwenta));
    }

    function test_Should_Set_Owner() public {
        assertEq(address(rewardEscrowV2.owner()), address(this));
    }

    function test_Should_Set_StakingRewards() public {
        assertEq(address(rewardEscrowV2.stakingRewardsV2()), address(stakingRewardsV2));
    }

    function test_Should_Set_Treasury() public {
        assertEq(address(rewardEscrowV2.treasuryDAO()), address(treasury));
    }

    function test_Should_Not_Allow_Treasury_To_Be_Set_To_Zero_Address() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        rewardEscrowV2.setTreasuryDAO(address(0));
    }

    function test_Should_Not_Allow_StakingRewards_To_Be_Set_Twice() public {
        vm.expectRevert(IRewardEscrowV2.StakingRewardsAlreadySet.selector);
        rewardEscrowV2.setStakingRewardsV2(address(stakingRewardsV1));
    }

    function test_Should_Set_nextEntryId_To_1() public {
        assertEq(rewardEscrowV2.nextEntryId(), 1);
    }
}
