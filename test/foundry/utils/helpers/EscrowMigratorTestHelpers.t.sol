// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "./StakingTestHelpers.t.sol";
import {Migrate} from "../../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../../contracts/RewardEscrow.sol";
import {VestingEntries} from "../../../../contracts/interfaces/IRewardEscrow.sol";
import {IEscrowMigrator} from "../../../../contracts/interfaces/IEscrowMigrator.sol";
import {SupplySchedule} from "../../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../../contracts/StakingRewards.sol";
import {EscrowMigrator} from "../../../../contracts/EscrowMigrator.sol";
import "../../utils/Constants.t.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EscrowMigratorTestHelpers is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public owner;
    EscrowMigrator public escrowMigrator;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        vm.rollFork(106_878_447);

        // define main contracts
        kwenta = Kwenta(OPTIMISM_KWENTA_TOKEN);
        rewardEscrowV1 = RewardEscrow(OPTIMISM_REWARD_ESCROW_V1);
        supplySchedule = SupplySchedule(OPTIMISM_SUPPLY_SCHEDULE);
        stakingRewardsV1 = StakingRewards(OPTIMISM_STAKING_REWARDS_V1);

        // define main addresses
        owner = OPTIMISM_PDAO;
        treasury = OPTIMISM_TREASURY_DAO;
        user1 = OPTIMISM_RANDOM_STAKING_USER;
        user2 = createUser();

        // set owners address code to trick the test into allowing onlyOwner functions to be called via script
        vm.etch(owner, address(new Migrate()).code);

        (rewardEscrowV2, stakingRewardsV2,,) = Migrate(owner).runCompleteMigrationProcess({
            _owner: owner,
            _kwenta: address(kwenta),
            _supplySchedule: address(supplySchedule),
            _stakingRewardsV1: address(stakingRewardsV1),
            _treasuryDAO: treasury,
            _printLogs: false
        });

        // deploy migrator
        address migratorImpl = address(
            new EscrowMigrator(
            address(kwenta),
            address(rewardEscrowV1),
            address(rewardEscrowV2)
            )
        );

        escrowMigrator = EscrowMigrator(
            address(
                new ERC1967Proxy(
                    migratorImpl,
                    abi.encodeWithSignature("initialize(address)", owner)
                )
            )
        );

        vm.prank(owner);
        rewardEscrowV1.setTreasuryDAO(address(escrowMigrator));
    }

    /*//////////////////////////////////////////////////////////////
                             STEP 1 HELPERS
    //////////////////////////////////////////////////////////////*/

    function checkStateBeforeStepOne(
        address account,
        uint256 expectedV1BalanceBefore,
        uint256 expectedNumVestingEntries
    ) internal returns (uint256[] memory _entryIDs, uint256 numVestingEntries) {
        uint256 v2BalanceBefore = rewardEscrowV2.escrowedBalanceOf(account);
        uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(account);
        assertEq(v1BalanceBefore, expectedV1BalanceBefore);
        assertEq(v2BalanceBefore, 0);

        numVestingEntries = rewardEscrowV1.numVestingEntries(account);
        assertEq(numVestingEntries, expectedNumVestingEntries);

        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(account, 0, numVestingEntries);
        assertEq(_entryIDs.length, numVestingEntries);

        assertEq(uint256(escrowMigrator.migrationStatus(account)), 0);
        assertEq(escrowMigrator.totalVestedAccountBalanceAtRegistrationTime(account), 0);
        assertEq(escrowMigrator.numberOfConfirmedEntries(account), 0);
        assertEq(escrowMigrator.numberOfMigratedEntries(account), 0);
        assertEq(escrowMigrator.numberOfRegisteredEntries(account), 0);

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            (uint256 escrowAmount, uint256 duration, uint64 endTime, bool confirmed) =
                escrowMigrator.registeredVestingSchedules(account, entryID);
            assertEq(escrowAmount, 0);
            assertEq(duration, 0);
            assertEq(endTime, 0);
            assertEq(confirmed, false);
        }
    }

    function checkStateAfterStepOne(address account, uint256[] memory _entryIDs, bool didRegister)
        internal
    {
        if (!didRegister && _entryIDs.length == 0) {
            // didn't register
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 0);
        } else if (_entryIDs.length == 0) {
            // initiated but didn't register any entries
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 1);
        } else {
            // initiated and registerd entries
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 2);
        }

        assertEq(
            escrowMigrator.totalVestedAccountBalanceAtRegistrationTime(account),
            rewardEscrowV2.totalVestedAccountBalance(account)
        );
        assertEq(escrowMigrator.numberOfRegisteredEntries(account), _entryIDs.length);
        assertEq(escrowMigrator.numberOfConfirmedEntries(account), 0);
        assertEq(escrowMigrator.numberOfMigratedEntries(account), 0);

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            assertEq(escrowMigrator.registeredEntryIDs(account, i), entryID);
            (uint256 escrowAmount, uint256 duration, uint64 endTime, bool confirmed) =
                escrowMigrator.registeredVestingSchedules(account, entryID);
            (uint64 endTimeOriginal, uint256 escrowAmountOriginal, uint256 durationOriginal) =
                rewardEscrowV1.getVestingEntry(account, entryID);
            assertEq(escrowAmount, escrowAmountOriginal);
            assertEq(duration, durationOriginal);
            assertEq(endTime, endTimeOriginal);
            assertEq(confirmed, false);
        }
    }
}
