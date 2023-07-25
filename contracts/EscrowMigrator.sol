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
import {IRewardEscrow} from "./interfaces/IRewardEscrow.sol";
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

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // TODO: add these and think about global accounting
    // uint256 public totalRegistered;
    // uint256 public totalConfirmed;
    // uint256 public totalMigrated;

    mapping(address => mapping(uint256 => VestingEntry)) public registeredVestingSchedules;

    mapping(address => uint256) public totalVestedAccountBalanceAtRegistrationTime;

    mapping(address => uint256) public totalEscrowBalanceAtRegistrationTime;

    mapping(address => uint256) public totalRegisteredEscrow;

    mapping(address => MigrationStatus) public migrationStatus;

    mapping(address => uint256[]) public registeredEntryIDs;

    mapping(address => uint256) public numberOfConfirmedEntries;

    mapping(address => uint256) public numberOfMigratedEntries;

    /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @dev disable default constructor for disable implementation contract
    /// Actual contract construction will take place in the initialize function via proxy
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _kwenta, address _rewardEscrowV1, address _rewardEscrowV2) {
        if (_kwenta == address(0)) revert ZeroAddress();
        if (_rewardEscrowV1 == address(0)) revert ZeroAddress();
        if (_rewardEscrowV2 == address(0)) revert ZeroAddress();

        kwenta = IKwenta(_kwenta);
        rewardEscrowV1 = IRewardEscrow(_rewardEscrowV1);
        rewardEscrowV2 = IRewardEscrowV2(_rewardEscrowV2);

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
    function registerEntriesForVestingAndMigration(uint256[] calldata _entryIDs) external {
        _registerEntriesForVestingAndMigration(msg.sender, _entryIDs);
    }

    function _registerEntriesForVestingAndMigration(address account, uint256[] calldata _entryIDs)
        internal
    {
        if (migrationStatus[account] == MigrationStatus.NOT_STARTED) {
            if (rewardEscrowV1.balanceOf(account) == 0) revert NoEscrowBalanceToMigrate();

            migrationStatus[account] = MigrationStatus.INITIATED;
            totalVestedAccountBalanceAtRegistrationTime[account] =
                rewardEscrowV1.totalVestedAccountBalance(account);

            totalEscrowBalanceAtRegistrationTime[account] = rewardEscrowV1.balanceOf(account);
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

            // skip if entry does not exist
            if (endTime == 0) continue;
            // skip if entry is already vested
            if (escrowAmount == 0) continue;
            // skip if entry is already fully mature (hence no need to migrate)
            if (endTime <= block.timestamp) continue;

            registeredVestingSchedules[account][entryID] = VestingEntry({
                endTime: endTime,
                escrowAmount: escrowAmount,
                duration: duration,
                confirmed: false
            });

            registeredEntryIDs[account].push(entryID);
            registeredEscrow += escrowAmount;
        }

        totalRegisteredEscrow[account] += registeredEscrow;

        if (registeredEntryIDs[account].length > 0) {
            migrationStatus[account] = MigrationStatus.REGISTERED;
        }
    }

    // step 2: vest all entries and confirm
    // WARNING: After this step no more entries can be registered
    function confirmEntriesAreVested(uint256[] calldata _entryIDs) external {
        _confirmEntriesAreVested(msg.sender, _entryIDs);
    }

    function _confirmEntriesAreVested(address account, uint256[] calldata _entryIDs) internal {
        if (migrationStatus[account] != MigrationStatus.REGISTERED) {
            revert MustBeInRegisteredState();
        }

        uint256 expectedEscrowBalanceNow =
            totalEscrowBalanceAtRegistrationTime[account] - totalRegisteredEscrow[account];
        uint256 actualEscrowBalanceNow = rewardEscrowV1.balanceOf(account);

        if (actualEscrowBalanceNow > expectedEscrowBalanceNow) revert InsufficientEscrowVested();
        if (actualEscrowBalanceNow < expectedEscrowBalanceNow) revert TooMuchEscrowVested();

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
            migrationStatus[account] = MigrationStatus.VESTED;
        }
    }

    // TODO: how to prevent user footgun of vesting after confirming?
    // - could store totalVested at confirmation stage - if it has increased
    // we require them to register further entries?
    function _payForMigration(address account) internal {
        uint256 vestedAtRegistration = totalVestedAccountBalanceAtRegistrationTime[account];
        uint256 vestedNow = rewardEscrowV1.totalVestedAccountBalance(account);
        uint256 userDebt = vestedNow - vestedAtRegistration;
        kwenta.transferFrom(msg.sender, address(this), userDebt);

        migrationStatus[account] = MigrationStatus.PAID;
    }

    // step 3: pay liquid kwenta for migration & migrate all registered entries
    function migrateRegisteredEntries(address to, uint256[] calldata _entryIDs) external {
        _migrateRegisteredEntries(msg.sender, to, _entryIDs);
    }

    function _migrateRegisteredEntries(address account, address to, uint256[] calldata _entryIDs)
        internal
    {
        if (migrationStatus[account] == MigrationStatus.VESTED) {
            _payForMigration(account);
        }

        if (migrationStatus[account] != MigrationStatus.PAID) {
            revert MustBeInPaidState();
        }

        // TODO: update to query this value
        uint256 cooldownTime = 2 weeks;

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];

            VestingEntry storage registeredEntry = registeredVestingSchedules[account][entryID];
            uint256 originalEscrowAmount = registeredEntry.escrowAmount;

            // skip if not registered
            if (registeredEntry.endTime == 0) continue;
            // entry must have been confirmed before migrating
            if (!registeredEntry.confirmed) continue;

            IRewardEscrowV2.VestingEntry memory entry = IRewardEscrowV2.VestingEntry({
                escrowAmount: originalEscrowAmount,
                duration: max(registeredEntry.duration, cooldownTime),
                endTime: uint64(max(registeredEntry.endTime, block.timestamp + cooldownTime)),
                earlyVestingFee: 90
            });

            kwenta.transfer(address(rewardEscrowV2), originalEscrowAmount);
            rewardEscrowV2.importEscrowEntry(to, entry);

            numberOfMigratedEntries[account]++;

            // update this to zero so it cannot be migrated again
            registeredEntry.endTime = 0;
        }

        if (numberOfMigratedEntries[account] == numberOfRegisteredEntries(account)) {
            migrationStatus[account] = MigrationStatus.COMPLETED;
        }
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /*//////////////////////////////////////////////////////////////
                       INTEGRATOR MIGRATION STEPS
    //////////////////////////////////////////////////////////////*/

    // step 1: initiate & register entries for migration
    function registerEntriesForIntegratorMigration(
        address _integrator,
        uint256[] calldata _entryIDs
    ) external {
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
        _migrateRegisteredEntries(_integrator, to, _entryIDs);
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
