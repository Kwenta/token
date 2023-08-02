// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {VestingEntries} from "../../../contracts/interfaces/IRewardEscrow.sol";
import {IEscrowMigrator} from "../../../contracts/interfaces/IEscrowMigrator.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {EscrowMigrator} from "../../../contracts/EscrowMigrator.sol";
import "../utils/Constants.t.sol";
import {EscrowMigratorTestHelpers} from "../utils/helpers/EscrowMigratorTestHelpers.t.sol";
import {EscrowMigratorHandler} from "../handlers/EscrowMigratorHandler.t.sol";

// TODO: think - perhaps this can just inherit StakingV2Setup
contract EscrowMigratorInvariantTests is EscrowMigratorTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    EscrowMigratorHandler handler;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        switchToStakingV2();

        address[] memory migrators = new address[](5);

        migrators[0] = user1;
        migrators[1] = user2;
        migrators[2] = user3;
        migrators[3] = user4;
        migrators[4] = user5;

        handler = new EscrowMigratorHandler(
            treasury,
            owner,
            kwenta,
            rewardEscrowV1,
            supplySchedule,
            stakingRewardsV1,
            rewardEscrowV2,
            stakingRewardsV2,
            escrowMigrator,
            migrators
        );
        // set the handler contract as the target for our test
        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                               INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function invariant_TotalRegistered_Greater_Than_Migrated() public {
        // total migrated should never be greater than the total registered
        assertGe(escrowMigrator.totalRegistered(), escrowMigrator.totalMigrated());
    }
}
