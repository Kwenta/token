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

    mapping(address => mapping(uint256 => VestingEntry)) public registeredVestingSchedules;

    mapping(address => uint256) public totalVestedAccountBalanceAtRegistrationTime;

    mapping(address => uint256) public totalUserEscrowToMigrate;

    mapping(address => MigrationStatus) public migrationStatus;

    mapping(address => uint256[]) public registeredEntryIDs;

    mapping(address => uint256) public numberOfMigratedEntries;

    mapping(address => uint256) public numberOfConfirmedEntries;

    mapping(address => mapping(uint256 => bool)) public isEntryConfirmed;

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
                          EOA MIGRATION STEPS
    //////////////////////////////////////////////////////////////*/

    // TODO: attempt to make atomic with step 2 a "initialized" check pattern
    // step 1: initiate migration
    function initiateMigration() external {
        _initiateMigration(msg.sender);
    }

    function _initiateMigration(address account) internal {
        if (migrationStatus[account] != MigrationStatus.NOT_STARTED) {
            revert MigrationAlreadyStarted();
        }
        if (rewardEscrowV1.balanceOf(account) == 0) revert NoEscrowBalanceToMigrate();

        migrationStatus[account] = MigrationStatus.INITIATED;
        totalVestedAccountBalanceAtRegistrationTime[account] =
            rewardEscrowV1.totalVestedAccountBalance(account);
    }

    // TODO: how to prevent user footgun of vesting before registering?
    // step 2: register entries for migration
    function registerEntriesForVestingAndMigration(uint256[] calldata _entryIDs) external {
        _registerEntriesForVestingAndMigration(msg.sender, _entryIDs);
    }

    function _registerEntriesForVestingAndMigration(address account, uint256[] calldata _entryIDs)
        internal
    {
        if (
            migrationStatus[account] != MigrationStatus.INITIATED
            // allow the state to be REGISTERED so that users can register entries in batches
            && migrationStatus[account] != MigrationStatus.REGISTERED
        ) {
            revert MustBeInitiatedOrRegistered();
        }

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
        }

        migrationStatus[account] = MigrationStatus.REGISTERED;
    }

    // step 3: vest all entries and confirm
    // WARNING: After this step no more entries can be registered
    function confirmEntriesAreVested(uint256[] calldata _entryIDs) external {
        _confirmEntriesAreVested(msg.sender, _entryIDs);
    }

    function _confirmEntriesAreVested(address account, uint256[] calldata _entryIDs) internal {
        if (migrationStatus[account] != MigrationStatus.REGISTERED) {
            revert MustBeInRegisteredState();
        }

        uint256 entriesToCheck = registeredEntryIDs[account].length;

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(account, entryID);

            // if it is not zero, it hasn't been vested
            if (escrowAmount != 0) continue;

            numberOfConfirmedEntries[account]++;
        }

        if (numberOfConfirmedEntries[account] == entriesToCheck) {
            migrationStatus[account] = MigrationStatus.VESTED;
        }
    }

    // TODO: how to prevent user footgun of vesting after confirming?
    // - could store totalVested at confirmation stage - if it has increased
    // we require them to register further entries?
    // step 4: pay liquid kwenta for migration
    function payForMigration() external {
        _payForMigration(msg.sender, msg.sender);
    }

    function _payForMigration(address account, address from) internal {
        if (migrationStatus[account] != MigrationStatus.VESTED) {
            revert MustBeInVestedState();
        }

        uint256 vestedAtRegistration = totalVestedAccountBalanceAtRegistrationTime[account];
        uint256 vestedNow = rewardEscrowV1.totalVestedAccountBalance(account);
        uint256 userDebt = vestedNow - vestedAtRegistration;
        kwenta.transferFrom(from, address(this), userDebt);

        migrationStatus[account] = MigrationStatus.PAID;
    }

    // step 5: migrate all registered entries
    function migrateRegisteredEntries(address to, uint256[] calldata _entryIDs) external {
        _migrateRegisteredEntries(msg.sender, to, _entryIDs);
    }

    function _migrateRegisteredEntries(address account, address to, uint256[] calldata _entryIDs)
        internal
    {
        if (migrationStatus[account] != MigrationStatus.PAID) {
            revert MustBeInPaidState();
        }

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];

            VestingEntry storage registeredEntry = registeredVestingSchedules[account][entryID];

            // skip if not registered
            if (registeredEntry.endTime == 0) continue;

            (uint64 endTime, uint256 escrowAmount, uint256 duration) =
                rewardEscrowV1.getVestingEntry(account, entryID);

            // skip if entry is not already vested
            if (escrowAmount != 0) continue;

            bool isFullyMature = endTime < block.timestamp;
            uint256 earlyVestingFee;
            uint256 newDuration;
            if (isFullyMature) {
                // set duration to 1 as 0 is not allowed
                newDuration = 1;
                // 50% is the minimum allowed earlyVestingFee
                earlyVestingFee = 50;
            } else {
                uint256 timeRemaining = endTime - block.timestamp;
                // max percentageLeft is 100 as timeRemaining cannot be larger than duration
                uint256 percentageLeft = timeRemaining * 100 / duration;
                // 90% is the fixed early vesting fee for V1 entries
                // reduce based on the percentage of time remaining
                earlyVestingFee = percentageLeft * 90 / 100;
                assert(earlyVestingFee <= 90);
                newDuration = timeRemaining;
            }

            kwenta.approve(address(rewardEscrowV2), escrowAmount);
            rewardEscrowV2.createEscrowEntry(
                to, registeredEntry.escrowAmount, newDuration, uint8(earlyVestingFee)
            );

            numberOfMigratedEntries[account]++;

            // update this to zero so it cannot be migrated again
            registeredEntry.endTime = 0;
        }

        if (numberOfMigratedEntries[account] == registeredEntryIDs[account].length) {
            migrationStatus[account] = MigrationStatus.COMPLETED;
        }
    }

    /*//////////////////////////////////////////////////////////////
                       INTEGRATOR MIGRATION STEPS
    //////////////////////////////////////////////////////////////*/

    // step 1: initiate migration
    function initiateIntegratorMigration(address _integrator) external {
        address beneficiary = IStakingRewardsV2Integrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _initiateMigration(_integrator);
    }

    // step 2: register entries for migration
    function registerEntriesForIntegratorMigration(
        address _integrator,
        uint256[] calldata _entryIDs
    ) external {
        address beneficiary = IStakingRewardsV2Integrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _registerEntriesForVestingAndMigration(_integrator, _entryIDs);
    }

    // step 3: vest all entries and confirm
    function confirmIntegratorEntriesAreVested(address _integrator, uint256[] calldata _entryIDs)
        external
    {
        address beneficiary = IStakingRewardsV2Integrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _confirmEntriesAreVested(_integrator, _entryIDs);
    }

    // step 4: pay liquid kwenta for migration
    function payForIntegratorMigration(address _integrator) external {
        address beneficiary = IStakingRewardsV2Integrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _payForMigration(_integrator, beneficiary);
    }

    // step 5: migrate all registered entries
    function migrateRegisteredIntegratorEntries(
        address _integrator,
        address to,
        uint256[] calldata _entryIDs
    ) external {
        address beneficiary = IStakingRewardsV2Integrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _migrateRegisteredEntries(to, _integrator, _entryIDs);
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
