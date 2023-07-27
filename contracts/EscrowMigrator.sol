// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// TODO: see if I can add a way to restart the process for a user

// Inheritance
import {IEscrowMigrator} from "./interfaces/IEscrowMigrator.sol";
import {Ownable2StepUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Internal references
import {IKwenta} from "./interfaces/IKwenta.sol";
import {IRewardEscrowV2} from "./interfaces/IRewardEscrowV2.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";
import {IRewardEscrow} from "./interfaces/IRewardEscrow.sol";
import {IStakingRewards} from "./interfaces/IStakingRewards.sol";
import {IStakingRewardsV2Integrator} from "./interfaces/IStakingRewardsV2Integrator.sol";

contract EscrowMigrator is
    IEscrowMigrator,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /*///////////////////////////////////////////////////////////////
                        CONSTANTS/IMMUTABLES
    ///////////////////////////////////////////////////////////////*/

    /// @notice Contract for KWENTA ERC20 token
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IKwenta public immutable kwenta;

    /// @notice Contract for RewardEscrowV1
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRewardEscrow public immutable rewardEscrowV1;

    /// @notice Contract for RewardEscrowV1
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRewardEscrowV2 public immutable rewardEscrowV2;

    /// @notice Contract for StakingRewardsV1
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IStakingRewards public immutable stakingRewardsV1;

    /// @notice Contract for StakingRewardsV2
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IStakingRewardsV2 public immutable stakingRewardsV2;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // TODO: add these and think about global accounting
    // uint256 public totalConfirmed;
    // uint256 public totalMigrated;
    // TODO: add this value to state check tests
    uint256 public totalRegistered;

    mapping(address => mapping(uint256 => VestingEntry)) public registeredVestingSchedules;

    mapping(address => MigrationStatus) public migrationStatus;

    mapping(address => uint256) public escrowVestedAtStart;

    mapping(address => uint256) public toPayForMigration;

    // TODO: consider just storing numberOfRegisterdEntries intead of the array
    mapping(address => uint256[]) public registeredEntryIDs;

    mapping(address => uint256) public numberOfConfirmedEntries;

    mapping(address => uint256) public numberOfMigratedEntries;

    /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @dev disable default constructor for disable implementation contract
    /// Actual contract construction will take place in the initialize function via proxy
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _kwenta,
        address _rewardEscrowV1,
        address _rewardEscrowV2,
        address _stakingRewardsV1,
        address _stakingRewardsV2
    ) {
        if (_kwenta == address(0)) revert ZeroAddress();
        if (_rewardEscrowV1 == address(0)) revert ZeroAddress();
        if (_rewardEscrowV2 == address(0)) revert ZeroAddress();

        kwenta = IKwenta(_kwenta);
        rewardEscrowV1 = IRewardEscrow(_rewardEscrowV1);
        rewardEscrowV2 = IRewardEscrowV2(_rewardEscrowV2);
        stakingRewardsV1 = IStakingRewards(_stakingRewardsV1);
        stakingRewardsV2 = IStakingRewardsV2(_stakingRewardsV2);

        _disableInitializers();
    }

    /// @inheritdoc IEscrowMigrator
    function initialize(address _contractOwner) external override initializer {
        if (_contractOwner == address(0)) revert ZeroAddress();

        // Initialize inherited contracts
        __Ownable2Step_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // transfer ownership
        _transferOwnership(_contractOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/
    function numberOfRegisteredEntries(address account) public view returns (uint256) {
        return registeredEntryIDs[account].length;
    }

    /*//////////////////////////////////////////////////////////////
                          EOA MIGRATION STEPS
    //////////////////////////////////////////////////////////////*/

    // step 1: initiate & register entries for migration
    /// @dev WARNING: If the user vests non-registerd entries after this step (and before reaching the VESTING_CONFIRMED state)
    /// they will have to pay extra to migrate. The user should register all entries they want to migrate BEFORE vesting, otherwise it will not be
    /// possible to migrate them.
    /// @dev WARNING: To reiterate, if the user vests any entries that are not registered before reaching the VESTING_CONFIRMED state, they will have
    /// to pay extra for the migration. This is because the user will have to pay for the migration based on the total vested balance at the time of
    /// migration - but only registered entries will be created for them on V2
    function registerEntriesForVestingAndMigration(uint256[] calldata _entryIDs) external {
        _registerEntriesForVestingAndMigration(msg.sender, _entryIDs);
    }

    function _registerEntriesForVestingAndMigration(address account, uint256[] calldata _entryIDs)
        internal
    {
        if (stakingRewardsV1.earned(account) != 0) revert MustClaimStakingRewards();

        if (migrationStatus[account] == MigrationStatus.NOT_STARTED) {
            if (rewardEscrowV1.balanceOf(account) == 0) revert NoEscrowBalanceToMigrate();

            migrationStatus[account] = MigrationStatus.INITIATED;
            escrowVestedAtStart[account] = rewardEscrowV1.totalVestedAccountBalance(account);
        }

        if (
            migrationStatus[account] != MigrationStatus.INITIATED
            // allow the state to be REGISTERED so that users can register entries in batches
            && migrationStatus[account] != MigrationStatus.REGISTERED
        ) {
            revert MustBeInitiatedOrRegistered();
        }

        uint256 registeredEscrow;

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];

            // skip if already registered
            if (registeredVestingSchedules[account][entryID].endTime != 0) continue;

            (uint64 endTime, uint256 escrowAmount, uint256 duration) =
                rewardEscrowV1.getVestingEntry(account, entryID);

            // skip if entry is already vested or does not exist
            if (escrowAmount == 0) continue;
            // skip if entry is already fully mature (hence no need to migrate)
            if (endTime <= block.timestamp) continue;

            registeredVestingSchedules[account][entryID] = VestingEntry({
                endTime: endTime,
                escrowAmount: escrowAmount,
                duration: duration,
                confirmed: false,
                migrated: false
            });

            /// @dev A counter of numberOfRegisteredEntries would do, but this allows easier inspection
            registeredEntryIDs[account].push(entryID);
            registeredEscrow += escrowAmount;
        }

        /// @dev Simlarly this value is not needed, but just added for easier on-chain inspection
        totalRegistered += registeredEscrow;

        if (
            migrationStatus[account] != MigrationStatus.REGISTERED
                && registeredEntryIDs[account].length > 0
        ) {
            migrationStatus[account] = MigrationStatus.REGISTERED;
        }
    }

    // step 2: vest all entries and confirm
    /// @dev WARNING: After reaching the VESTING_CONFIRMED state, no further entries can be registered
    function confirmEntriesAreVested(uint256[] calldata _entryIDs) external {
        _confirmEntriesAreVested(msg.sender, _entryIDs);
    }

    function _confirmEntriesAreVested(address account, uint256[] calldata _entryIDs) internal {
        if (migrationStatus[account] != MigrationStatus.REGISTERED) {
            revert MustBeInRegisteredState();
        }

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(account, entryID);
            VestingEntry storage registeredEntry = registeredVestingSchedules[account][entryID];

            // entry must have been registered
            if (registeredEntry.endTime == 0) continue;
            // cannot confirm twice
            if (registeredEntry.confirmed) continue;
            // if it is not zero, it hasn't been vested
            if (escrowAmount != 0) continue;

            registeredEntry.confirmed = true;
            numberOfConfirmedEntries[account]++;
        }

        if (numberOfConfirmedEntries[account] == numberOfRegisteredEntries(account)) {
            migrationStatus[account] = MigrationStatus.VESTING_CONFIRMED;
            /// @dev We do this calculation now and store it (rather than at the migrate step) to remove further possibility of the
            /// user doing the foot-gun of vesting unregistered entries after confirming - and hence having to pay extra to migrate
            toPayForMigration[account] =
                rewardEscrowV1.totalVestedAccountBalance(account) - escrowVestedAtStart[account];
        }
    }

    // TODO: how to prevent user footgun of vesting after confirming?
    // - could store totalVested at confirmation stage - if it has increased
    // we require them to register further entries?
    function _payForMigration(address account) internal {
        kwenta.transferFrom(msg.sender, address(this), toPayForMigration[account]);
        migrationStatus[account] = MigrationStatus.PAID;
    }

    // step 3: pay liquid kwenta for migration & migrate all registered entries
    function migrateConfirmedEntries(address to, uint256[] calldata _entryIDs) external {
        _migrateConfirmedEntries(msg.sender, to, _entryIDs);
    }

    function _migrateConfirmedEntries(address account, address to, uint256[] calldata _entryIDs)
        internal
    {
        if (migrationStatus[account] == MigrationStatus.VESTING_CONFIRMED) {
            _payForMigration(account);
        }

        if (migrationStatus[account] != MigrationStatus.PAID) {
            revert MustBeInPaidState();
        }

        uint256 cooldown = stakingRewardsV2.cooldownPeriod();

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];

            VestingEntry storage registeredEntry = registeredVestingSchedules[account][entryID];
            uint256 originalEscrowAmount = registeredEntry.escrowAmount;

            // skip if already migrated
            if (registeredEntry.migrated) continue;
            // entry must have been confirmed before migrating
            if (!registeredEntry.confirmed) continue;

            uint256 duration;
            uint64 endTime;
            /// @dev it essential for security that the duration is not less than the cooldown period,
            /// otherwise the user could do a governance attack by bypassing the unstaking cooldown lock
            /// by migrating their escrow then staking, voting, and vesting immediately
            if (registeredEntry.duration < cooldown) {
                uint256 timeCreated = registeredEntry.endTime - registeredEntry.duration;
                duration = cooldown;
                endTime = uint64(timeCreated + cooldown);
            } else {
                duration = registeredEntry.duration;
                endTime = registeredEntry.endTime;
            }

            IRewardEscrowV2.VestingEntry memory entry = IRewardEscrowV2.VestingEntry({
                escrowAmount: originalEscrowAmount,
                duration: duration,
                endTime: endTime,
                earlyVestingFee: 90
            });

            kwenta.transfer(address(rewardEscrowV2), originalEscrowAmount);
            rewardEscrowV2.importEscrowEntry(to, entry);

            numberOfMigratedEntries[account]++;

            // update this so it cannot be migrated again
            registeredEntry.migrated = true;
        }

        if (numberOfMigratedEntries[account] == numberOfRegisteredEntries(account)) {
            migrationStatus[account] = MigrationStatus.COMPLETED;
        }
    }

    /*//////////////////////////////////////////////////////////////
                       INTEGRATOR MIGRATION STEPS
    //////////////////////////////////////////////////////////////*/

    // step 1: initiate & register entries for migration
    function registerEntriesForIntegratorMigration(
        address _integrator,
        uint256[] calldata _entryIDs
    ) external {
        // TODO: create onlyBeneficiary modifier
        address beneficiary = IStakingRewardsV2Integrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _registerEntriesForVestingAndMigration(_integrator, _entryIDs);
    }

    // step 2: vest all entries and confirm
    function confirmIntegratorEntriesAreVested(address _integrator, uint256[] calldata _entryIDs)
        external
    {
        address beneficiary = IStakingRewardsV2Integrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _confirmEntriesAreVested(_integrator, _entryIDs);
    }

    // step 3: pay liquid kwenta for migration & migrate all registered entries
    function migrateRegisteredIntegratorEntries(
        address _integrator,
        address to,
        uint256[] calldata _entryIDs
    ) external {
        address beneficiary = IStakingRewardsV2Integrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _migrateConfirmedEntries(_integrator, to, _entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                             UPGRADEABILITY
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}

    /*///////////////////////////////////////////////////////////////
                                PAUSABLE
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowMigrator
    function pauseRewardEscrow() external override onlyOwner {
        _pause();
    }

    /// @inheritdoc IEscrowMigrator
    function unpauseRewardEscrow() external override onlyOwner {
        _unpause();
    }
}
