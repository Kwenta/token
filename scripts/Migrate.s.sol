// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import {Kwenta} from "../contracts/Kwenta.sol";
import {StakingRewards} from "../contracts/StakingRewards.sol";
import {SupplySchedule} from "../contracts/SupplySchedule.sol";
import {RewardEscrowV2} from "../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../contracts/StakingRewardsV2.sol";

/// @title Script to migration from StakingV1 to StakingV2
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
contract Setup {
    function deploySystem(
        address _owner,
        address _kwenta,
        address _supplySchedule,
        address _stakingRewardsV1,
        bool _migrateToV2
    ) public returns (RewardEscrowV2 rewardEscrowV2, StakingRewardsV2 stakingRewardsV2) {
        rewardEscrowV2 = new RewardEscrowV2(_owner, _kwenta);
        stakingRewardsV2 = new StakingRewardsV2(
            _kwenta,
            address(rewardEscrowV2),
            _supplySchedule,
            address(_stakingRewardsV1)
        );

        console.log("Deployed StakingRewardsV2 at %s", address(stakingRewardsV2));
        console.log("Deployed RewardEscrowV2 at %s", address(rewardEscrowV2));

        if (_migrateToV2) {
            switchToStakingV2(
                _supplySchedule, address(stakingRewardsV2), address(rewardEscrowV2)
            );
        }
    }

    function switchToStakingV2(
        address _supplySchedule,
        address _stakingRewardsV2,
        address _rewardEscrowV2
    ) internal {
        SupplySchedule supplySchedule = SupplySchedule(_supplySchedule);
        RewardEscrowV2 rewardEscrowV2 = RewardEscrowV2(_rewardEscrowV2);

        // Update SupplySchedule to point to StakingV2
        supplySchedule.setStakingRewards(_stakingRewardsV2);
        rewardEscrowV2.setStakingRewardsV2(_stakingRewardsV2);
    }
}
