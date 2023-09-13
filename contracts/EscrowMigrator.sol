// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
import {IStakingRewardsIntegrator} from "./interfaces/IStakingRewardsIntegrator.sol";

/*//////////////////////////////////////////////////////////////
                            WARNING
//////////////////////////////////////////////////////////////*/

/// @dev WARNING: There is a footgun when using this contract
/// Once a user is initiated, any entries they vest BEFORE registering, they will have to pay extra for
/// Once again:
/// If a user vests an entry after initiating without registering it first, they will have to pay extra for it

/*//////////////////////////////////////////////////////////////
                        ESCROW MIGRATOR
//////////////////////////////////////////////////////////////*/

/// @title KWENTA Escrow Migrator
/// Used to migrate escrow entries from RewardEscrowV1 to RewardEscrowV2
/// @author tommyrharper (tom@zkconsulting.xyz)
contract EscrowMigrator is
    IEscrowMigrator,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /*///////////////////////////////////////////////////////////////
                        CONSTANTS/IMMUTABLES
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowMigrator
    uint256 public constant MIGRATION_DEADLINE = 2 weeks;

    /// @notice Contract for KWENTA ERC20 token
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IKwenta public immutable kwenta;

    /// @notice Contract for RewardEscrowV1
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRewardEscrow public immutable rewardEscrowV1;

    /// @notice Contract for RewardEscrowV2
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRewardEscrowV2 public immutable rewardEscrowV2;

    /// @notice Contract for StakingRewardsV2
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IStakingRewardsV2 public immutable stakingRewardsV2;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the treasury DAO
    address public treasuryDAO;

    /// @notice Total amount of escrow registered
    uint256 public totalRegistered;

    /// @notice Total amount of escrow migrated
    uint256 public totalMigrated;

    /// @notice Total amount of escrow locked due to migration deadline
    uint256 public totalLocked;

    /// @notice Mapping of acount to entryID to registered vesting entry data
    mapping(address => mapping(uint256 => VestingEntry)) public registeredVestingSchedules;

    /// @notice Mapping of initialization time for each account
    mapping(address => uint256) public initializationTime;

    /// @notice Mapping of whether an account's funds are locked due to migration deadline
    mapping(address => bool) public lockedFundsAccountedFor;

    /// @notice Mapping of escrow already vested at start for each account
    mapping(address => uint256) public escrowVestedAtStart;

    /// @notice Mapping of $KWENTA paid so far for the migration for each account
    mapping(address => uint256) public paidSoFar;

    /// @notice Mapping of registered entry IDs for each account
    mapping(address => uint256[]) public registeredEntryIDs;

    /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @dev disable default constructor for disable implementation contract
    /// Actual contract construction will take place in the initialize function via proxy
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param _kwenta The address for the KWENTA ERC20 token
    /// @param _rewardEscrowV1 The address for the RewardEscrowV1 contract
    /// @param _rewardEscrowV2 The address for the RewardEscrowV2 contract
    /// @param _stakingRewardsV2 The address for the StakingRewardsV2 contract
    constructor(
        address _kwenta,
        address _rewardEscrowV1,
        address _rewardEscrowV2,
        address _stakingRewardsV2
    ) {
        if (_kwenta == address(0)) revert ZeroAddress();
        if (_rewardEscrowV1 == address(0)) revert ZeroAddress();
        if (_rewardEscrowV2 == address(0)) revert ZeroAddress();
        if (_stakingRewardsV2 == address(0)) revert ZeroAddress();

        kwenta = IKwenta(_kwenta);
        rewardEscrowV1 = IRewardEscrow(_rewardEscrowV1);
        rewardEscrowV2 = IRewardEscrowV2(_rewardEscrowV2);
        stakingRewardsV2 = IStakingRewardsV2(_stakingRewardsV2);

        _disableInitializers();
    }

    /// @inheritdoc IEscrowMigrator
    function initialize(address _contractOwner, address _treasuryDAO) external initializer {
        if (_contractOwner == address(0) || _treasuryDAO == address(0)) revert ZeroAddress();

        // Initialize inherited contracts
        __Ownable2Step_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // transfer ownership
        _transferOwnership(_contractOwner);

        // set treasuryDAO
        treasuryDAO = _treasuryDAO;

        /// @dev Start contract as paused so that users cannot begin migrating funds before
        /// rewardEscrowV1.setTreasuryDAO(escrowMigrator) and rewardEscrowV2.setEscrowMigrator(escrowMigrator)
        /// are called, as this could lead to expected early vest fees not being sent to the escrow migrator.
        /// Once these functions are called, then the escrow migrator can be unpaused.
        _pause();
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowMigrator
    function numberOfRegisteredEntries(address _account) public view returns (uint256) {
        return registeredEntryIDs[_account].length;
    }

    /// @inheritdoc IEscrowMigrator
    /// @dev WARNING: this loop is potentially limitless - could revert with out of gas error if called on-chain
    function numberOfMigratedEntries(address _account) external view returns (uint256 total) {
        uint256[] storage entries = registeredEntryIDs[_account];
        uint256 length = entries.length;

        mapping(uint256 => VestingEntry) storage userEntries = registeredVestingSchedules[_account];
        for (uint256 i = 0; i < length;) {
            uint256 entryID = entries[i];
            VestingEntry storage entry = userEntries[entryID];
            if (entry.migrated) total++;

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IEscrowMigrator
    /// @dev WARNING: this loop is potentially limitless - could revert with out of gas error if called on-chain
    function totalEscrowRegistered(address _account) public view returns (uint256 total) {
        uint256[] storage entries = registeredEntryIDs[_account];
        uint256 length = entries.length;

        mapping(uint256 => VestingEntry) storage userEntries = registeredVestingSchedules[_account];
        for (uint256 i = 0; i < length;) {
            uint256 entryID = entries[i];
            VestingEntry storage entry = userEntries[entryID];
            total += uint256(entry.escrowAmount);

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IEscrowMigrator
    /// @dev WARNING: this loop is potentially limitless - could revert with out of gas error if called on-chain
    function totalEscrowMigrated(address _account) public view returns (uint256 total) {
        uint256[] storage entries = registeredEntryIDs[_account];
        uint256 length = entries.length;

        mapping(uint256 => VestingEntry) storage userEntries = registeredVestingSchedules[_account];
        for (uint256 i = 0; i < length;) {
            uint256 entryID = entries[i];
            VestingEntry storage entry = userEntries[entryID];
            if (entry.migrated) total += uint256(entry.escrowAmount);

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IEscrowMigrator
    /// @dev WARNING: this loop is potentially limitless - could revert with out of gas error if called on-chain
    function totalEscrowUnmigrated(address _account) public view returns (uint256 total) {
        uint256[] storage entries = registeredEntryIDs[_account];
        uint256 length = entries.length;

        mapping(uint256 => VestingEntry) storage userEntries = registeredVestingSchedules[_account];
        for (uint256 i = 0; i < length;) {
            uint256 entryID = entries[i];
            VestingEntry storage entry = userEntries[entryID];
            if (!entry.migrated) total += uint256(entry.escrowAmount);

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IEscrowMigrator
    function toPay(address _account) public view returns (uint256) {
        uint256 totalPaymentRequired =
            rewardEscrowV1.totalVestedAccountBalance(_account) - escrowVestedAtStart[_account];
        return totalPaymentRequired - paidSoFar[_account];
    }

    /// @inheritdoc IEscrowMigrator
    function getRegisteredVestingEntry(address _account, uint256 _entryID)
        external
        view
        returns (uint256 escrowAmount, bool migrated)
    {
        VestingEntry storage entry = registeredVestingSchedules[_account][_entryID];
        escrowAmount = entry.escrowAmount;
        migrated = entry.migrated;
    }

    /// @inheritdoc IEscrowMigrator
    function getRegisteredVestingSchedules(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        returns (VestingEntryWithID[] memory)
    {
        if (_pageSize == 0) {
            return new VestingEntryWithID[](0);
        }

        uint256 endIndex = _index + _pageSize;

        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = numberOfRegisteredEntries(_account);
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }

        if (endIndex <= _index) return new VestingEntryWithID[](0);

        uint256 n;
        unchecked {
            n = endIndex - _index;
        }

        mapping(uint256 => VestingEntry) storage userEntries = registeredVestingSchedules[_account];
        uint256[] storage entryIDs = registeredEntryIDs[_account];

        VestingEntryWithID[] memory vestingEntries = new VestingEntryWithID[](n);
        for (uint256 i; i < n;) {
            uint256 entryID;
            unchecked {
                entryID = entryIDs[i + _index];
            }

            VestingEntry storage entry = userEntries[entryID];

            vestingEntries[i] = VestingEntryWithID({
                entryID: entryID,
                escrowAmount: entry.escrowAmount,
                migrated: entry.migrated
            });

            unchecked {
                ++i;
            }
        }
        return vestingEntries;
    }

    /// @inheritdoc IEscrowMigrator
    function getRegisteredVestingEntryIDs(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        returns (uint256[] memory)
    {
        uint256 endIndex = _index + _pageSize;

        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = numberOfRegisteredEntries(_account);
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }
        if (endIndex <= _index) {
            return new uint256[](0);
        }

        uint256[] storage entryIDs = registeredEntryIDs[_account];

        uint256 n = endIndex - _index;
        uint256[] memory page = new uint256[](n);
        for (uint256 i; i < n;) {
            unchecked {
                page[i] = entryIDs[i + _index];
            }

            unchecked {
                ++i;
            }
        }
        return page;
    }

    /*//////////////////////////////////////////////////////////////
                                 STEP 0
    //////////////////////////////////////////////////////////////*/

    /// @notice claim any remaining StakingRewards V1 rewards
    /// This must be done before the migration process can begin

    /*//////////////////////////////////////////////////////////////
                                 STEP 1
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowMigrator
    function registerEntries(uint256[] calldata _entryIDs) external {
        _registerEntries(msg.sender, _entryIDs);
    }

    function _registerEntries(address _account, uint256[] calldata _entryIDs)
        internal
        whenNotPaused
    {
        uint256 initializedAt = initializationTime[_account];
        if (initializedAt == 0) {
            if (rewardEscrowV1.balanceOf(_account) == 0) revert NoEscrowBalanceToMigrate();

            initializationTime[_account] = block.timestamp;
            escrowVestedAtStart[_account] = rewardEscrowV1.totalVestedAccountBalance(_account);
        } else if (_deadlinePassed(initializedAt)) {
            revert DeadlinePassed();
        }

        uint256[] storage userEntryIDs = registeredEntryIDs[_account];
        mapping(uint256 => VestingEntry) storage userEntries = registeredVestingSchedules[_account];

        uint256 registeredEscrow;
        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];

            // skip if already registered
            if (userEntries[entryID].escrowAmount != 0) continue;

            (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(_account, entryID);

            // skip if entry is already vested or does not exist
            if (escrowAmount == 0) continue;

            userEntries[entryID] =
                VestingEntry({escrowAmount: uint248(escrowAmount), migrated: false});

            userEntryIDs.push(entryID);
            registeredEscrow += escrowAmount;
        }

        totalRegistered += registeredEscrow;
    }

    /*//////////////////////////////////////////////////////////////
                                 STEP 2
    //////////////////////////////////////////////////////////////*/

    /// @notice The user must vest any registered entries and approve this contract to spend `toPay` amount of liquid $KWENTA
    /// before proceeding to step 3
    /// @notice The user MUST NOT vest any non-registered entries at this point (or they will have to pay extra)

    /*//////////////////////////////////////////////////////////////
                                 STEP 3
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowMigrator
    function migrateEntries(address _to, uint256[] calldata _entryIDs) external {
        _migrateEntries(msg.sender, _to, _entryIDs);
    }

    function _migrateEntries(address _account, address _to, uint256[] calldata _entryIDs)
        internal
        whenNotPaused
    {
        _checkIfMigrationAllowed(_account);
        _payForMigration(_account);

        uint256 migratedEscrow;
        uint256 cooldown = stakingRewardsV2.cooldownPeriod();
        mapping(uint256 => VestingEntry) storage userEntries = registeredVestingSchedules[_account];

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];

            (uint256 endTime, uint256 escrowAmount, uint256 duration) =
                rewardEscrowV1.getVestingEntry(_account, entryID);
            VestingEntry storage registeredEntry = userEntries[entryID];
            uint256 originalEscrowAmount = registeredEntry.escrowAmount;

            // if it is not zero, it hasn't been vested
            if (escrowAmount != 0) continue;
            // entry must have been registered
            if (originalEscrowAmount == 0) continue;
            // skip if already migrated
            if (registeredEntry.migrated) continue;

            // update state
            registeredEntry.migrated = true;
            migratedEscrow += originalEscrowAmount;

            /// @dev it essential for security that the duration is not less than the cooldown period,
            /// otherwise the user could do a governance attack by bypassing the unstaking cooldown lock
            /// by migrating their escrow then staking, voting, and vesting immediately
            if (duration < cooldown) {
                uint256 timeCreated = endTime - duration;
                duration = cooldown;
                endTime = timeCreated + cooldown;
            }

            IRewardEscrowV2.VestingEntry memory entry = IRewardEscrowV2.VestingEntry({
                escrowAmount: originalEscrowAmount,
                duration: duration,
                endTime: endTime,
                earlyVestingFee: 90
            });

            // create duplicate vesting entry on v2
            kwenta.transfer(address(rewardEscrowV2), originalEscrowAmount);
            rewardEscrowV2.importEscrowEntry(_to, entry);
        }

        totalMigrated += migratedEscrow;
    }

    function _checkIfMigrationAllowed(address _account) internal view {
        uint256 initiatedAt = initializationTime[_account];
        if (initiatedAt == 0) revert MustBeInitiated();
        if (_deadlinePassed(initiatedAt)) revert DeadlinePassed();
    }

    function _deadlinePassed(uint256 _initiatedAt) internal view returns (bool) {
        return block.timestamp > _initiatedAt + MIGRATION_DEADLINE;
    }

    function _payForMigration(address _account) internal {
        uint256 toPayNow = toPay(_account);
        if (toPayNow > 0) {
            kwenta.transferFrom(msg.sender, address(this), toPayNow);
            paidSoFar[_account] += toPayNow;
        }
    }

    /*//////////////////////////////////////////////////////////////
                       INTEGRATOR MIGRATION STEPS
    //////////////////////////////////////////////////////////////*/

    /// @dev These functions will only be used by a few V1 smart contract users who set the
    /// recipient of their V1 staked escrow to the "beneficiary" stored on the smart contract

    /// @dev check the msg.sender is the "beneficiary" stored on the integrator smart contract
    modifier onlyBeneficiary(address _integrator) {
        address beneficiary = IStakingRewardsIntegrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _;
    }

    /// @inheritdoc IEscrowMigrator
    function registerIntegratorEntries(address _integrator, uint256[] calldata _entryIDs)
        external
        onlyBeneficiary(_integrator)
    {
        _registerEntries(_integrator, _entryIDs);
    }

    /// @inheritdoc IEscrowMigrator
    function migrateIntegratorEntries(
        address _integrator,
        address _to,
        uint256[] calldata _entryIDs
    ) external onlyBeneficiary(_integrator) {
        _migrateEntries(_integrator, _to, _entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                             FUND RECOVERY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowMigrator
    function setTreasuryDAO(address _newTreasuryDAO) external onlyOwner {
        if (_newTreasuryDAO == address(0)) revert ZeroAddress();
        treasuryDAO = _newTreasuryDAO;
    }

    /// @inheritdoc IEscrowMigrator
    /// @dev warning - may fail due to unbounded loop for certain users
    function updateTotalLocked(address[] memory _expiredMigrators) external {
        for (uint256 i = 0; i < _expiredMigrators.length;) {
            updateTotalLocked(_expiredMigrators[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IEscrowMigrator
    /// @dev warning - may fail due to unbounded loop for certain users
    function updateTotalLocked(address _expiredMigrator) public {
        uint256 initiatedAt = initializationTime[_expiredMigrator];
        if (
            initiatedAt != 0 && !lockedFundsAccountedFor[_expiredMigrator]
                && _deadlinePassed(initiatedAt)
        ) {
            lockedFundsAccountedFor[_expiredMigrator] = true;
            totalLocked += totalEscrowUnmigrated(_expiredMigrator);
        }
    }

    /// @inheritdoc IEscrowMigrator
    function recoverExcessFunds() external onlyOwner {
        uint256 leaveInContract = totalRegistered - totalMigrated - totalLocked;
        uint256 balance = kwenta.balanceOf(address(this));
        if (balance > leaveInContract) {
            kwenta.transfer(treasuryDAO, balance - leaveInContract);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             UPGRADEABILITY
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}

    /*///////////////////////////////////////////////////////////////
                                PAUSABLE
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowMigrator
    function pauseEscrowMigrator() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IEscrowMigrator
    function unpauseEscrowMigrator() external onlyOwner {
        _unpause();
    }
}
