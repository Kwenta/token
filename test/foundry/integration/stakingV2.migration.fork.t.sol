// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {Setup} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";

contract StakingV2MigrationForkTests is Test {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Kwenta public kwenta;
    RewardEscrow public rewardEscrowV1;
    RewardEscrowV2 public rewardEscrowV2;
    SupplySchedule public supplySchedule;
    StakingRewards public stakingRewardsV1;
    StakingRewardsV2 public stakingRewardsV2;

    // main addresses
    address public owner;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        // define main contracts
        kwenta = Kwenta(KWENTA);
        rewardEscrowV1 = RewardEscrow(REWARD_ESCROW_V1);
        supplySchedule = SupplySchedule(SUPPLY_SCHEDULE);
        stakingRewardsV1 = StakingRewards(STAKING_REWARDS_V1);

        // define main addresses
        owner = KWENTA_OWNER;

        // define Setup contract used for deployments
        Setup setup = new Setup();

        // deploy system contracts
        (rewardEscrowV2, stakingRewardsV2) = setup.deploySystem({
            _owner: owner,
            _kwenta: address(kwenta),
            _supplySchedule: address(supplySchedule),
            _stakingRewardsV1: address(stakingRewardsV1),
            _pauseAndMigrate: false
        });

        pauseAndSwitchToStakingRewardsV2();
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testMagic() public {
        assertTrue(true);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function pauseAndSwitchToStakingRewardsV2() public {
        vm.startPrank(owner);

        // Pause StakingV1
        stakingRewardsV1.pauseStakingRewards();

        // Update SupplySchedule to point to StakingV2
        supplySchedule.setStakingRewards(address(stakingRewardsV2));
        rewardEscrowV2.setStakingRewards(address(stakingRewardsV2));

        // Unpause StakingV1
        stakingRewardsV1.unpauseStakingRewards();

        vm.stopPrank();
    }
}
