// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITokenDistributor} from "../../../../contracts/interfaces/ITokenDistributor.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {StakingSetup} from "../../utils/setup/StakingSetup.t.sol";
import {TokenDistributorInternals} from "../../utils/TokenDistributorInternals.sol";
import {TokenDistributor} from "../../../../contracts/TokenDistributor.sol";


/// @notice test how many weeks we can go without checkpointing
/// and how much gas will it cost
contract TokenDistributorGasCalculation is StakingSetup {

    TokenDistributor public tokenDistributor;

    function setUp() public override {
        /// @dev starts after a week so the startTime is != 0
        goForward(1 weeks + 1);
        super.setUp();
        switchToStakingV2();
        tokenDistributor = new TokenDistributor(
            address(kwenta),
            address(stakingRewardsV2),
            address(rewardEscrowV2),
            0
        );
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
    }

    function testGas() public {

        for(int i = 0 ; i < 52 ; i++) {
            vm.prank(address(treasury));
            kwenta.transfer(address(tokenDistributor), 3);
            goForward(1 weeks);
        }

        tokenDistributor.checkpointToken();

    }

}