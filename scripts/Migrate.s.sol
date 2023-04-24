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
    function deploySystem(
        address _owner,
        address _kwenta,
        address _supplySchedule,
        address _stakingRewardsV1,
        bool _pauseAndMigrate
    ) public returns (RewardEscrowV2 rewardEscrowV2, StakingRewardsV2 stakingRewardsV2) {
        RewardEscrowV2 rewardEscrowV2 = new RewardEscrowV2(_owner, _kwenta);
        StakingRewardsV2 stakingRewardsV2 = new StakingRewardsV2(
            _kwenta,
            address(rewardEscrowV2),
            _supplySchedule,
            address(_stakingRewardsV1)
        );

        console.log("Deployed StakingRewardsV2 at %s", address(stakingRewardsV2));
        console.log("Deployed RewardEscrowV2 at %s", address(rewardEscrowV2));

        if (_pauseAndMigrate) {
            pauseAndSwitchToStakingRewardsV2(
                _stakingRewardsV1, _supplySchedule, address(stakingRewardsV2), address(rewardEscrowV2)
            );
        }

        return (rewardEscrowV2, stakingRewardsV2);
    }

    function pauseAndSwitchToStakingRewardsV2(
        address _stakingRewardsV1,
        address _supplySchedule,
        address _stakingRewardsV2,
        address _rewardEscrowV2
    ) internal {
        StakingRewards stakingRewardsV1 = StakingRewards(_stakingRewardsV1);
        SupplySchedule supplySchedule = SupplySchedule(_supplySchedule);
        StakingRewardsV2 stakingRewardsV2 = StakingRewardsV2(_stakingRewardsV2);
        RewardEscrowV2 rewardEscrowV2 = RewardEscrowV2(_rewardEscrowV2);

        // Pause StakingV1
        stakingRewardsV1.pauseStakingRewards();

        // Update SupplySchedule to point to StakingV2
        supplySchedule.setStakingRewards(address(stakingRewardsV2));
        rewardEscrowV2.setStakingRewards(address(stakingRewardsV2));

        // Unpause StakingV1
        stakingRewardsV1.unpauseStakingRewards();
    }
}
