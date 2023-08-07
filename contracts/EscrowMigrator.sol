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

// TODO: add events???

/*//////////////////////////////////////////////////////////////
                        ESCROW MIGRATOR
//////////////////////////////////////////////////////////////*/

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

    uint256 public totalRegistered;

    uint256 public totalMigrated;

    mapping(address => mapping(uint256 => VestingEntry)) public registeredVestingSchedules;

    mapping(address => bool) public initiated;

    mapping(address => uint256) public escrowVestedAtStart;

    mapping(address => uint256) public paidSoFar;

    // OPT: consider just storing numberOfRegisterdEntries intead of the array
    // TODO: add view function to return this data as a memory array, and to query individual entries
    mapping(address => uint256[]) public registeredEntryIDs;

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

    /// @inheritdoc IEscrowMigrator
    function numberOfRegisteredEntries(address account) public view override returns (uint256) {
        return registeredEntryIDs[account].length;
    }

    /// @inheritdoc IEscrowMigrator
    function numberOfMigratedEntries(address account) external view override returns (uint256 total) {
        uint256 length = numberOfRegisteredEntries(account);

        for (uint256 i = 0; i < length; i++) {
            if (registeredVestingSchedules[account][registeredEntryIDs[account][i]].migrated) {
                total++;
            }
        }
    }

    /// @inheritdoc IEscrowMigrator
    function totalEscrowRegistered(address account) external view override returns (uint256 total) {
        uint256 length = numberOfRegisteredEntries(account);

        for (uint256 i = 0; i < length; i++) {
            total +=
                registeredVestingSchedules[account][registeredEntryIDs[account][i]].escrowAmount;
        }
    }

    /// @inheritdoc IEscrowMigrator
    function totalEscrowMigrated(address account) external view override returns (uint256 total) {
        uint256 length = numberOfRegisteredEntries(account);

        for (uint256 i = 0; i < length; i++) {
            if (registeredVestingSchedules[account][registeredEntryIDs[account][i]].migrated) {
                total +=
                    registeredVestingSchedules[account][registeredEntryIDs[account][i]].escrowAmount;
            }
        }
    }

    /// @inheritdoc IEscrowMigrator
    function toPay(address account) public view override returns (uint256) {
        uint256 totalPaymentRequired =
            rewardEscrowV1.totalVestedAccountBalance(account) - escrowVestedAtStart[account];
        return totalPaymentRequired - paidSoFar[account];
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
    function registerEntries(uint256[] calldata _entryIDs) external override {
        _registerEntries(msg.sender, _entryIDs);
    }

    function _registerEntries(address account, uint256[] calldata _entryIDs)
        internal
        whenNotPaused
    {
        if (!initiated[account]) {
            if (stakingRewardsV1.earned(account) != 0) revert MustClaimStakingRewards();
            if (rewardEscrowV1.balanceOf(account) == 0) revert NoEscrowBalanceToMigrate();

            initiated[account] = true;
            escrowVestedAtStart[account] = rewardEscrowV1.totalVestedAccountBalance(account);
        }

        // OPT: update to use getVestingSchedules to save gas from all the message calls
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
                migrated: false
            });

            /// @dev A counter of numberOfRegisteredEntries would do, but this allows easier inspection
            registeredEntryIDs[account].push(entryID);
            registeredEscrow += escrowAmount;
        }

        /// @dev Simlarly this value is not needed, but just added for easier on-chain inspection
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
    function migrateEntries(address to, uint256[] calldata _entryIDs) external {
        _migrateEntries(msg.sender, to, _entryIDs);
    }

    function _migrateEntries(address account, address to, uint256[] calldata _entryIDs)
        internal
        whenNotPaused
    {
        if (!initiated[account]) revert MustBeInitiated();
        _payForMigration(account);

        uint256 migratedEscrow;
        uint256 cooldown = stakingRewardsV2.cooldownPeriod();

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];

            (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(account, entryID);
            VestingEntry storage registeredEntry = registeredVestingSchedules[account][entryID];
            uint256 originalEscrowAmount = registeredEntry.escrowAmount;

            // if it is not zero, it hasn't been vested
            if (escrowAmount != 0) continue;
            // entry must have been registered
            if (registeredEntry.endTime == 0) continue;
            // skip if already migrated
            if (registeredEntry.migrated) continue;

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

            // OPT: think if this transfer can be done once in advance (could pass in total via calldata args)
            // then check it at the end to ensure it is correct
            kwenta.transfer(address(rewardEscrowV2), originalEscrowAmount);
            rewardEscrowV2.importEscrowEntry(to, entry);

            // OPT: think - could remove `migrated` as a gas optimization and just set endTime to 0
            // update this so it cannot be migrated again
            registeredEntry.migrated = true;

            migratedEscrow += originalEscrowAmount;
        }

        /// @dev This value is not needed, but just added for easier on-chain inspection
        totalMigrated += migratedEscrow;
    }

    function _payForMigration(address account) internal {
        uint256 toPayNow = toPay(account);
        if (toPayNow > 0) {
            kwenta.transferFrom(msg.sender, address(this), toPayNow);
            paidSoFar[account] += toPayNow;
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

    // step 1: initiate & register entries for migration
    function registerIntegratorEntries(address _integrator, uint256[] calldata _entryIDs)
        external
        onlyBeneficiary(_integrator)
    {
        _registerEntries(_integrator, _entryIDs);
    }

    // step 2: vest all entries, then pay liquid kwenta for migration & migrate registered entries
    function migrateIntegratorEntries(address _integrator, address to, uint256[] calldata _entryIDs)
        external
        onlyBeneficiary(_integrator)
    {
        _migrateEntries(_integrator, to, _entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                             UPGRADEABILITY
    //////////////////////////////////////////////////////////////*/

    // TODO: test onlyOwner and test upgradeability
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}

    /*///////////////////////////////////////////////////////////////
                                PAUSABLE
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IEscrowMigrator
    function pauseEscrowMigrator() external override onlyOwner {
        _pause();
    }

    /// @inheritdoc IEscrowMigrator
    function unpauseEscrowMigrator() external override onlyOwner {
        _unpause();
    }
}
