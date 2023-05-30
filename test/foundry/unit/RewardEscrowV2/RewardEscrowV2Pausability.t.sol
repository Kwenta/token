// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IRewardEscrowV2} from "../../../../contracts/interfaces/IRewardEscrowV2.sol";
import "../../utils/Constants.t.sol";

contract RewardEscrowV2PausabilityTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Pausability
    //////////////////////////////////////////////////////////////*/

    function test_Only_Owner_Can_Pause_Contract() public {
        // attempt to pause
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.pauseRewardEscrow();

        // pause
        rewardEscrowV2.pauseRewardEscrow();

        // attempt to unpause
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.unpauseRewardEscrow();

        // unpause
        rewardEscrowV2.unpauseRewardEscrow();
    }
}
