// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";

/// @title Script to migration from StakingV1 to StakingV2
/// @author tommyrharper (tom@solidity.ninja)
contract Setup {
    function deploySystem(address _owner, address _kwenta, address _supplySchedule, address _stakingRewardsV1)
        public
        returns (RewardEscrowV2 rewardEscrowV2, StakingRewardsV2 stakingRewardsV2)
    {
        RewardEscrowV2 rewardEscrowV2 = new RewardEscrowV2(_owner, _kwenta);
        StakingRewardsV2 stakingRewardsV2 = new StakingRewardsV2(
            _kwenta,
            address(rewardEscrowV2),
            _supplySchedule,
            address(_stakingRewardsV1)
        );

        StakingRewards stakingRewardsV1 = StakingRewards(_stakingRewardsV1);
        SupplySchedule supplySchedule = SupplySchedule(_supplySchedule);

        // // Pause StakingV1
        // stakingRewardsV1.pauseStakingRewards();

        // // Update SupplySchedule to point to StakingV2
        // supplySchedule.setStakingRewards(address(stakingRewardsV2));
        // rewardEscrowV2.setStakingRewards(address(stakingRewardsV2));

        // // Unpause StakingV1
        // stakingRewardsV1.unpauseStakingRewards();
    }
}
