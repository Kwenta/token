// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingV2Setup} from "../utils/setup/StakingV2Setup.t.sol";
import {EscrowMigratorHandler} from "../handlers/EscrowMigratorHandler.t.sol";

contract EscrowMigratorInvariantTests is StakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    EscrowMigratorHandler handler;
    address[] migrators;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        switchToStakingV2();

        migrators.push(user1);
        migrators.push(user2);
        migrators.push(user3);
        migrators.push(user4);
        migrators.push(user5);

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
                            FULL INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function invariant_Cannot_Migrate_Total_More_Than_Registered() public {
        assertGe(escrowMigrator.totalRegistered(), escrowMigrator.totalMigrated());
    }

    function invariant_Cannot_Register_More_Entries_Than_Created() public {
        for (uint256 i = 0; i < migrators.length; i++) {
            address migrator = migrators[i];
            assertGe(
                rewardEscrowV1.numVestingEntries(migrator),
                escrowMigrator.numberOfRegisteredEntries(migrator)
            );
        }
    }

    function invariant_Cannot_Migrate_More_Entries_Than_Created() public {
        for (uint256 i = 0; i < migrators.length; i++) {
            address migrator = migrators[i];
            assertGe(
                rewardEscrowV1.numVestingEntries(migrator),
                escrowMigrator.numberOfMigratedEntries(migrator)
            );
        }
    }

    function invariant_Cannot_Migrate_More_Entries_Than_Registerd() public {
        for (uint256 i = 0; i < migrators.length; i++) {
            address migrator = migrators[i];
            assertGe(
                escrowMigrator.numberOfRegisteredEntries(migrator),
                escrowMigrator.numberOfMigratedEntries(migrator)
            );
        }
    }

    function invariant_Cannot_Have_More_Migrated_And_Locked_Than_Registered() public {
        assertGe(
            escrowMigrator.totalRegistered(),
            escrowMigrator.totalLocked() + escrowMigrator.totalMigrated()
        );
    }

    function invariant_Recover_Always_Any_Excess_Funds() public {
        handler.recoverExcessFunds();
        assertLe(
            kwenta.balanceOf(address(escrowMigrator)),
            escrowMigrator.totalRegistered() - escrowMigrator.totalLocked()
                - escrowMigrator.totalMigrated()
        );
    }

    function invariant_Registered_Equals_Migrated_Plus_Unmigrated() public {
        for (uint256 i = 0; i < migrators.length; i++) {
            address migrator = migrators[i];
            assertEq(
                escrowMigrator.totalEscrowRegistered(migrator),
                escrowMigrator.totalEscrowUnmigrated(migrator)
                    + escrowMigrator.totalEscrowMigrated(migrator)
            );
        }
    }

    function invariant_Escrow_Vested_At_Start_Cannot_Be_Greater_Than_Vested_Account_Balance()
        public
    {
        for (uint256 i = 0; i < migrators.length; i++) {
            address migrator = migrators[i];
            assertGe(
                rewardEscrowV1.totalVestedAccountBalance(migrator),
                escrowMigrator.escrowVestedAtStart(migrator)
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                           PARTIAL INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev: WARNING - these "partial" invariants only hold due to the limitations of the
    /// handler contract. Updating the handler contract can cause these invariants to break.
    /// This is because these invariants hold given the fact that certain actions are not taken.
    /// The relevant actions that are not being taken for an invariant to hold will be mentioned
    /// at the top of each invariant test

    /// @custom:condition no creating v2 escrow entries
    /// @custom:condition no claiming rewards on staking rewards v2
    /// @custom:condition no vesting in reward escrow v2
    function invariant_RewardEscrowV2_Gets_Exactly_How_Much_Is_Migrated() public {
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowMigrator.totalMigrated());
    }

    /// @custom:condition no creating v2 escrow entries
    /// @custom:condition no claiming rewards on staking rewards v2
    /// @custom:condition no vesting in reward escrow v2
    function invariant_RewardEscrowV2_Cannot_Get_More_Than_Is_Registered() public {
        assertLe(rewardEscrowV2.totalEscrowedBalance(), escrowMigrator.totalRegistered());
    }

    /// @custom:condition no creating v2 escrow entries
    /// @custom:condition no claiming rewards on staking rewards v2
    /// @custom:condition no vesting in reward escrow v2
    /// @custom:condition no transferring escrow in reward escrow v2
    function invariant_RewardEscrowV2_Gets_Exactly_How_Much_Is_Migrated_Per_Migrator() public {
        for (uint256 i = 0; i < migrators.length; i++) {
            address migrator = migrators[i];
            assertEq(
                rewardEscrowV2.totalEscrowedAccountBalance(migrator),
                escrowMigrator.totalEscrowMigrated(migrator)
            );
        }
    }
}
