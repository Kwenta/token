// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Inheritance
import {IRewardEscrowV2} from "./interfaces/IRewardEscrowV2.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {Ownable2StepUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Internal references
import {IKwenta} from "./interfaces/IKwenta.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";
import {IEscrowMigrator} from "./interfaces/IEscrowMigrator.sol";

/// @title KWENTA Reward Escrow V2
/// @author SYNTHETIX, JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc), tommyrharper (zeroknowledgeltd@gmail.com)
/// @notice Updated version of Synthetix's RewardEscrow with new features specific to Kwenta
contract RewardEscrowV2 is
    IRewardEscrowV2,
    ERC721EnumerableUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /*///////////////////////////////////////////////////////////////
                        CONSTANTS/IMMUTABLES
    ///////////////////////////////////////////////////////////////*/

    /// @notice Max escrow duration
    /// @dev WARNING: updating this value to less than 2 years will allow this check to be bypassed
    /// via the escrow migrator contract, by creating V1 escrow entries and migrating them to V2
    uint256 public constant MAX_DURATION = 4 * 52 weeks; // Default max 4 years duration

    /// @notice Min escrow duration
    uint256 public constant DEFAULT_DURATION = 52 weeks; // Default 1 year duration

    /// @notice Default early vesting fee - used for new vesting entries from staking rewards
    uint8 public constant DEFAULT_EARLY_VESTING_FEE = 90; // Default 90 percent

    /// @notice Maximum early vesting fee - cannot be higher than 100%
    /// @dev WARNING: Updating this value to below 90 will be able to be bypassed via importEscrowEntry
    /// through the EscrowMigrator contract
    uint8 public constant MAXIMUM_EARLY_VESTING_FEE = 100;

    /// @inheritdoc IRewardEscrowV2
    /// @dev WARNING: see warning in IRewardEscrowV2 if planning on changing this value
    uint8 public constant MINIMUM_EARLY_VESTING_FEE = 50;

    /// @notice Contract for KWENTA ERC20 token
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IKwenta internal immutable kwenta;

    /*///////////////////////////////////////////////////////////////
                                STATE
    ///////////////////////////////////////////////////////////////*/

    /// @notice Contract for StakingRewardsV2
    IStakingRewardsV2 public stakingRewards;

    /// @notice Contract for EscrowMigrator
    IEscrowMigrator public escrowMigrator;

    /// @notice treasury address - this may change
    address public treasuryDAO;

    ///@notice mapping of entryIDs to vesting entries
    mapping(uint256 => VestingEntry) public vestingSchedules;

    /// @notice Counter for new vesting entry ids
    uint256 public nextEntryId;

    /// @notice An account's total escrowed KWENTA balance to save recomputing this for fee extraction purposes
    mapping(address => uint256) public totalEscrowedAccountBalance;

    /// @notice An account's total vested reward KWENTA
    mapping(address => uint256) public totalVestedAccountBalance;

    /// @notice The total remaining escrowed balance, for verifying the actual KWENTA balance of this contract against
    uint256 public totalEscrowedBalance;

    /// @notice RewardsNotifier address
    address public rewardsNotifier;

    /*///////////////////////////////////////////////////////////////
                                AUTH
    ///////////////////////////////////////////////////////////////*/

    /// @notice Restrict function to only the staking rewards contract
    modifier onlyStakingRewards() {
        _onlyStakingRewards();
        _;
    }

    function _onlyStakingRewards() internal view {
        if (msg.sender != address(stakingRewards)) revert OnlyStakingRewards();
    }

    /// @notice Restrict function to only the escrow migrator contract
    modifier onlyEscrowMigrator() {
        if (msg.sender != address(escrowMigrator)) revert OnlyEscrowMigrator();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @dev disable default constructor for disable implementation contract
    /// Actual contract construction will take place in the initialize function via proxy
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param _kwenta The address for the KWENTA ERC20 token
    constructor(address _kwenta) {
        if (_kwenta == address(0)) revert ZeroAddress();

        kwenta = IKwenta(_kwenta);

        _disableInitializers();
    }

    /// @inheritdoc IRewardEscrowV2
    function initialize(address _contractOwner) external initializer {
        if (_contractOwner == address(0)) revert ZeroAddress();

        // Initialize inherited contracts
        __ERC721_init("Kwenta Reward Escrow", "KRE");
        __Ownable2Step_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // transfer ownership
        _transferOwnership(_contractOwner);

        // define variables
        nextEntryId = 1;
    }

    /*///////////////////////////////////////////////////////////////
                                SETTERS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRewardEscrowV2
    function setStakingRewards(address _stakingRewards) external onlyOwner {
        if (_stakingRewards == address(0)) revert ZeroAddress();
        if (address(stakingRewards) != address(0)) revert StakingRewardsAlreadySet();

        stakingRewards = IStakingRewardsV2(_stakingRewards);
        emit StakingRewardsSet(_stakingRewards);
    }

    /// @inheritdoc IRewardEscrowV2
    function setEscrowMigrator(address _escrowMigrator) external onlyOwner {
        if (_escrowMigrator == address(0)) revert ZeroAddress();

        escrowMigrator = IEscrowMigrator(_escrowMigrator);
        emit EscrowMigratorSet(_escrowMigrator);
    }

    /// @inheritdoc IRewardEscrowV2
    function setTreasuryDAO(address _treasuryDAO) external onlyOwner {
        if (_treasuryDAO == address(0)) revert ZeroAddress();
        treasuryDAO = _treasuryDAO;
        emit TreasuryDAOSet(treasuryDAO);
    }

    // TODO: check if this can be set in the constructor
    /// @inheritdoc IRewardEscrowV2
    function setRewardsNotifier(address _rewardsNotifier)
        external
        onlyOwner
    {
        if (_rewardsNotifier == address(0)) revert ZeroAddress();
        rewardsNotifier = _rewardsNotifier;
        emit RewardsNotifierSet(rewardsNotifier);
    }

    /*///////////////////////////////////////////////////////////////
                                VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRewardEscrowV2
    function getKwentaAddress() external view returns (address) {
        return address(kwenta);
    }

    /// @inheritdoc IRewardEscrowV2
    function escrowedBalanceOf(address _account) external view returns (uint256) {
        return totalEscrowedAccountBalance[_account];
    }

    /// @inheritdoc IRewardEscrowV2
    function unstakedEscrowedBalanceOf(address _account) public view returns (uint256) {
        return totalEscrowedAccountBalance[_account] - stakingRewards.escrowedBalanceOf(_account);
    }

    /// @inheritdoc IRewardEscrowV2
    function getVestingEntry(uint256 _entryID)
        external
        view
        returns (uint64 endTime, uint256 escrowAmount, uint256 duration, uint8 earlyVestingFee)
    {
        VestingEntry storage entry = vestingSchedules[_entryID];
        endTime = entry.endTime;
        escrowAmount = entry.escrowAmount;
        duration = entry.duration;
        earlyVestingFee = entry.earlyVestingFee;
    }

    /// @inheritdoc IRewardEscrowV2
    function getVestingSchedules(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        returns (VestingEntryWithID[] memory)
    {
        if (_pageSize == 0) {
            return new VestingEntryWithID[](0);
        }

        uint256 endIndex = _index + _pageSize;

        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = balanceOf(_account);
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }

        if (endIndex < _index) return new VestingEntryWithID[](0);

        uint256 n;
        unchecked {
            n = endIndex - _index;
        }

        VestingEntryWithID[] memory vestingEntries = new VestingEntryWithID[](
            n
        );
        for (uint256 i; i < n;) {
            uint256 entryID;

            unchecked {
                entryID = tokenOfOwnerByIndex(_account, i + _index);
            }

            VestingEntry storage entry = vestingSchedules[entryID];

            vestingEntries[i] = VestingEntryWithID({
                endTime: entry.endTime,
                escrowAmount: entry.escrowAmount,
                entryID: entryID
            });

            unchecked {
                ++i;
            }
        }
        return vestingEntries;
    }

    /// @inheritdoc IRewardEscrowV2
    function getAccountVestingEntryIDs(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        returns (uint256[] memory)
    {
        uint256 endIndex = _index + _pageSize;

        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = balanceOf(_account);
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }
        if (endIndex <= _index) {
            return new uint256[](0);
        }

        uint256 n = endIndex - _index;
        uint256[] memory page = new uint256[](n);
        for (uint256 i; i < n;) {
            unchecked {
                page[i] = tokenOfOwnerByIndex(_account, i + _index);
            }

            unchecked {
                ++i;
            }
        }
        return page;
    }

    /// @inheritdoc IRewardEscrowV2
    function getVestingQuantity(uint256[] calldata _entryIDs)
        external
        view
        returns (uint256 total, uint256 totalFee)
    {
        uint256 entryIDsLength = _entryIDs.length;
        for (uint256 i = 0; i < entryIDsLength;) {
            VestingEntry memory entry = vestingSchedules[_entryIDs[i]];

            (uint256 quantity, uint256 fee) = _claimableAmount(entry);

            // add quantity to total
            total += quantity;
            totalFee += fee;

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IRewardEscrowV2
    function getVestingEntryClaimable(uint256 _entryID)
        external
        view
        returns (uint256 quantity, uint256 fee)
    {
        VestingEntry memory entry = vestingSchedules[_entryID];
        (quantity, fee) = _claimableAmount(entry);
    }

    function _claimableAmount(VestingEntry memory _entry)
        internal
        view
        returns (uint256 quantity, uint256 fee)
    {
        uint256 escrowAmount = _entry.escrowAmount;

        // Full escrow amounts claimable if block.timestamp equal to or after entry endTime
        if (block.timestamp >= _entry.endTime) {
            quantity = escrowAmount;
        } else {
            fee = _earlyVestFee(_entry);
            quantity = escrowAmount - fee;
        }
    }

    function _earlyVestFee(VestingEntry memory _entry)
        internal
        view
        returns (uint256 earlyVestFee)
    {
        uint256 timeUntilVest = _entry.endTime - block.timestamp;
        // Fee starts by default at 90% (but could be any percentage) and falls linearly
        earlyVestFee =
            (_entry.escrowAmount * _entry.earlyVestingFee * timeUntilVest) / (100 * _entry.duration);
    }

    /*///////////////////////////////////////////////////////////////
                            MUTATIVE FUNCTIONS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRewardEscrowV2
    function vest(uint256[] calldata _entryIDs) external whenNotPaused {
        uint256 total;
        uint256 totalFee;
        uint256 entryIDsLength = _entryIDs.length;
        for (uint256 i = 0; i < entryIDsLength; ++i) {
            VestingEntry storage entry = vestingSchedules[_entryIDs[i]];
            if (_ownerOf(_entryIDs[i]) != msg.sender) {
                continue;
            }

            (uint256 quantity, uint256 fee) = _claimableAmount(entry);

            // update entry to remove escrowAmount
            entry.escrowAmount = 0;
            _burn(_entryIDs[i]);

            // add quantity to total
            total += quantity;
            totalFee += fee;
        }

        // Transfer vested tokens
        uint256 totalWithFee = total + totalFee;
        if (totalWithFee != 0) {
            // Unstake staked escrowed kwenta if needed for reward/fee
            uint256 unstakedEscrow = unstakedEscrowedBalanceOf(msg.sender);
            if (totalWithFee > unstakedEscrow) {
                uint256 amountToUnstake;
                unchecked {
                    amountToUnstake = totalWithFee - unstakedEscrow;
                }
                stakingRewards.unstakeEscrowSkipCooldown(msg.sender, amountToUnstake);
            }

            // update balances
            totalEscrowedBalance -= totalWithFee;
            totalEscrowedAccountBalance[msg.sender] -= totalWithFee;
            totalVestedAccountBalance[msg.sender] += total;

            // Send 50% any fee to Treasury and
            // 50% to RewardsNotifier
            // UNLESS Distributor isn't set
            // then send all funds to Treasury
            if (totalFee != 0) {
                if (rewardsNotifier == address(0)) {
                    kwenta.transfer(treasuryDAO, totalFee);
                    emit EarlyVestFeeSentToTreasury(totalFee);
                } else {
                    /// @dev this will revert if the kwenta token transfer fails
                    uint256 proportionalFee = totalFee / 2;
                    uint256 proportionaFeeWithDust = totalFee - proportionalFee;
                    kwenta.transfer(treasuryDAO, proportionalFee);
                    kwenta.transfer(rewardsNotifier, proportionaFeeWithDust);
                    // TODO: consolidate these events into one
                    emit EarlyVestFeeSentToTreasury(proportionalFee);
                    emit EarlyVestFeeSentToNotifier(proportionaFeeWithDust);
                }
            }

            if (total != 0) {
                // Transfer kwenta
                /// @dev this will revert if the kwenta token transfer fails
                kwenta.transfer(msg.sender, total);
            }

            // trigger event
            emit Vested(msg.sender, total);
        }
    }

    /// @inheritdoc IRewardEscrowV2
    function importEscrowEntry(address _account, VestingEntry memory _entry)
        external
        onlyEscrowMigrator
    {
        _mint(
            _account, _entry.endTime, _entry.escrowAmount, _entry.duration, _entry.earlyVestingFee
        );
    }

    /// @inheritdoc IRewardEscrowV2
    function createEscrowEntry(
        address _beneficiary,
        uint256 _deposit,
        uint256 _duration,
        uint8 _earlyVestingFee
    ) external {
        if (_beneficiary == address(0)) revert ZeroAddress();
        if (_earlyVestingFee > MAXIMUM_EARLY_VESTING_FEE) revert EarlyVestingFeeTooHigh();
        if (_earlyVestingFee < MINIMUM_EARLY_VESTING_FEE) revert EarlyVestingFeeTooLow();
        if (_deposit == 0) revert ZeroAmount();
        uint256 minimumDuration = stakingRewards.cooldownPeriod();
        if (_duration < minimumDuration || _duration > MAX_DURATION) revert InvalidDuration();

        /// @dev this will revert if the kwenta token transfer fails
        kwenta.transferFrom(msg.sender, address(this), _deposit);

        // Escrow the tokens for duration.
        uint256 endTime = block.timestamp + _duration;

        // Append vesting entry for the beneficiary address
        _mint(_beneficiary, uint64(endTime), _deposit, _duration, _earlyVestingFee);
    }

    /// @inheritdoc IRewardEscrowV2
    function appendVestingEntry(address _account, uint256 _quantity) external onlyStakingRewards {
        // Escrow the tokens for duration.
        uint256 endTime = block.timestamp + DEFAULT_DURATION;

        _mint(_account, uint64(endTime), _quantity, DEFAULT_DURATION, DEFAULT_EARLY_VESTING_FEE);
    }

    /// @inheritdoc IRewardEscrowV2
    function bulkTransferFrom(address _from, address _to, uint256[] calldata _entryIDs)
        external
        whenNotPaused
    {
        if (_from == _to) revert CannotTransferToSelf();

        uint256 totalEscrowTransferred;
        uint256 entryIDsLength = _entryIDs.length;
        for (uint256 i = 0; i < entryIDsLength;) {
            // sum totalEscrowTransferred so that _applyTransferBalanceUpdates can be applied only once to save gas
            totalEscrowTransferred += vestingSchedules[_entryIDs[i]].escrowAmount;

            _checkApproved(_entryIDs[i]);
            // use super._transfer to avoid double updating of balances
            super._transfer(_from, _to, _entryIDs[i]);
            unchecked {
                ++i;
            }
        }

        // update balances all at once
        _applyTransferBalanceUpdates(_from, _to, totalEscrowTransferred);
    }

    /*///////////////////////////////////////////////////////////////
                                INTERNALS
    ///////////////////////////////////////////////////////////////*/

    /// @dev override the internal _transfer function to ensure vestingSchedules and account balances are updated
    /// and that there is sufficient unstaked escrow for a transfer when transferFrom and safeTransferFrom are called
    function _transfer(address _from, address _to, uint256 _entryID)
        internal
        override
        whenNotPaused
    {
        uint256 escrowAmount = vestingSchedules[_entryID].escrowAmount;

        _applyTransferBalanceUpdates(_from, _to, escrowAmount);

        super._transfer(_from, _to, _entryID);
    }

    function _applyTransferBalanceUpdates(address _from, address _to, uint256 _escrowAmount)
        internal
    {
        uint256 unstakedEscrow = unstakedEscrowedBalanceOf(_from);
        if (unstakedEscrow < _escrowAmount) {
            revert InsufficientUnstakedBalance(_escrowAmount, unstakedEscrow);
        }

        unchecked {
            totalEscrowedAccountBalance[_from] -= _escrowAmount;
        }
        totalEscrowedAccountBalance[_to] += _escrowAmount;
    }

    function _checkApproved(uint256 _entryID) internal view {
        /// @dev not using a custom error to keep consistency with OpenZeppelin errors
        require(
            _isApprovedOrOwner(_msgSender(), _entryID),
            "ERC721: caller is not token owner or approved"
        );
    }

    function _mint(
        address _account,
        uint64 _endTime,
        uint256 _quantity,
        uint256 _duration,
        uint8 _earlyVestingFee
    ) internal whenNotPaused {
        // There must be enough balance in the contract to provide for the vesting entry.
        totalEscrowedBalance += _quantity;
        assert(kwenta.balanceOf(address(this)) >= totalEscrowedBalance);

        // Add quantity to account's escrowed balance
        totalEscrowedAccountBalance[_account] += _quantity;

        uint256 entryID = nextEntryId;
        vestingSchedules[entryID] = VestingEntry({
            endTime: _endTime,
            escrowAmount: _quantity,
            duration: _duration,
            earlyVestingFee: _earlyVestingFee
        });

        // Increment the next entry id.
        unchecked {
            ++nextEntryId;
        }

        emit VestingEntryCreated(_account, _quantity, _duration, entryID, _earlyVestingFee);

        super._mint(_account, entryID);
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}

    /*///////////////////////////////////////////////////////////////
                                PAUSABLE
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRewardEscrowV2
    function pauseRewardEscrow() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IRewardEscrowV2
    function unpauseRewardEscrow() external onlyOwner {
        _unpause();
    }
}
