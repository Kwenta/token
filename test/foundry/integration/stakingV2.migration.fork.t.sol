// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
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

        // set owners address code to trick the test into allowing onlyOwner functions to be called via script
        vm.etch(owner, address(new Migrate()).code);

        Migrate(owner).runCompleteMigrationProcess({
            _owner: owner,
            _kwenta: address(kwenta),
            _supplySchedule: address(supplySchedule),
            _stakingRewardsV1: address(stakingRewardsV1)
        });
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    // TODO: sort this out
    function test_Magic() public {
        assertTrue(true);
    }
}
