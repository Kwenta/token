// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// Inheritance
import {IRewardEscrowV2} from "./interfaces/IRewardEscrowV2.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Internal references
import {IKwenta} from "./interfaces/IKwenta.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";

/// @title KWENTA Reward Escrow V2
/// @author SYNTHETIX, JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc), tommyrharper (zeroknowledgeltd@gmail.com)
/// @notice Updated version of Synthetix's RewardEscrow with new features specific to Kwenta
contract RewardEscrowV2 is
    IRewardEscrowV2,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /*///////////////////////////////////////////////////////////////
                        CONSTANTS/IMMUTABLES
    ///////////////////////////////////////////////////////////////*/

    /// @notice Max escrow duration
    uint256 public constant MAX_DURATION = 4 * 52 weeks; // Default max 4 years duration

    uint256 public constant DEFAULT_DURATION = 52 weeks; // Default 1 year duration

    /// @notice Default early vesting fee - used for new vesting entries from staking rewards
    uint8 public constant DEFAULT_EARLY_VESTING_FEE = 90; // Default 90 percent

    /// @notice Maximum early vesting fee - cannot be higher than 100%
    uint8 public constant MAXIMUM_EARLY_VESTING_FEE = 100;

    /// @notice Minimum early vesting fee
    uint8 public constant MINIMUM_EARLY_VESTING_FEE = 50;

    /*///////////////////////////////////////////////////////////////
                                STATE
    ///////////////////////////////////////////////////////////////*/

    /// @notice Contract for KWENTA ERC20 token
    IKwenta internal kwenta;

    /// @notice Contract for StakingRewardsV2
    IStakingRewardsV2 public stakingRewards;

    /// @notice treasury address - this may change
    address public treasuryDAO;

    /// @notice EarlyVestFeeDistributor address
    address public earlyVestFeeDistributor;

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

    /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @dev disable default constructor for disable implementation contract
    /// Actual contract construction will take place in the initialize function via proxy
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IRewardEscrowV2
    function initialize(address _contractOwner, address _kwenta) external override initializer {
        if (_contractOwner == address(0) || _kwenta == address(0)) revert ZeroAddress();

        // Initialize inherited contracts
        __ERC721_init("Kwenta Reward Escrow", "KRE");
        __Ownable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // transfer ownership
        _transferOwnership(_contractOwner);

        // define variables
        nextEntryId = 1;
        kwenta = IKwenta(_kwenta);
    }

    /*///////////////////////////////////////////////////////////////
                                SETTERS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRewardEscrowV2
    function setStakingRewards(address _stakingRewards) external override onlyOwner {
        if (_stakingRewards == address(0)) revert ZeroAddress();
        if (address(stakingRewards) != address(0)) revert StakingRewardsAlreadySet();

        stakingRewards = IStakingRewardsV2(_stakingRewards);
        emit StakingRewardsSet(_stakingRewards);
    }

    /// @inheritdoc IRewardEscrowV2
    function setTreasuryDAO(address _treasuryDAO) external override onlyOwner {
        if (_treasuryDAO == address(0)) revert ZeroAddress();
        treasuryDAO = _treasuryDAO;
        emit TreasuryDAOSet(treasuryDAO);
    }

    /// @inheritdoc IRewardEscrowV2
    function setEarlyVestFeeDistributor(address _earlyVestFeeDistributor) external override onlyOwner {
        if (_earlyVestFeeDistributor == address(0)) revert ZeroAddress();
        earlyVestFeeDistributor = _earlyVestFeeDistributor;
        emit EarlyVestFeeDistributorSet(earlyVestFeeDistributor);
    }

    /*///////////////////////////////////////////////////////////////
                                VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRewardEscrowV2
    function getKwentaAddress() external view override returns (address) {
        return address(kwenta);
    }

    /// @inheritdoc IRewardEscrowV2
    function escrowedBalanceOf(address _account) external view override returns (uint256) {
        return totalEscrowedAccountBalance[_account];
    }

    /// @inheritdoc IRewardEscrowV2
    function unstakedEscrowedBalanceOf(address _account) public view override returns (uint256) {
        return totalEscrowedAccountBalance[_account] - stakingRewards.escrowedBalanceOf(_account);
    }

    /// @inheritdoc IRewardEscrowV2
    function getVestingEntry(uint256 _entryID)
        external
        view
        override
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
        override
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

        if (endIndex < _index) revert InvalidIndex();

        uint256 n;
        unchecked {
            n = endIndex - _index;
        }

        VestingEntryWithID[] memory vestingEntries = new VestingEntryWithID[](n);
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
        override
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
        override
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
        override
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
            _entry.escrowAmount * _entry.earlyVestingFee * timeUntilVest / (100 * _entry.duration);
    }

    /*///////////////////////////////////////////////////////////////
                            MUTATIVE FUNCTIONS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRewardEscrowV2
    function vest(uint256[] calldata _entryIDs) external override whenNotPaused {
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

            // trigger event
            emit Vested(msg.sender, total);

            // Send 50% any fee to Treasury and
            // 50% to EarlyVestFeeDistributor
            if (totalFee != 0) {
                /// @dev this will revert if the kwenta token transfer fails
                uint256 proportionalFee = totalFee * 50 / 100;
                kwenta.transfer(treasuryDAO, proportionalFee);
                kwenta.transfer(earlyVestFeeDistributor, proportionalFee);
            }

            if (total != 0) {
                // Transfer kwenta
                /// @dev this will revert if the kwenta token transfer fails
                kwenta.transfer(msg.sender, total);
            }
        }
    }

    /// @inheritdoc IRewardEscrowV2
    function createEscrowEntry(
        address _beneficiary,
        uint256 _deposit,
        uint256 _duration,
        uint8 _earlyVestingFee
    ) external override whenNotPaused {
        if (_beneficiary == address(0)) revert ZeroAddress();
        if (_earlyVestingFee > MAXIMUM_EARLY_VESTING_FEE) revert EarlyVestingFeeTooHigh();
        if (_earlyVestingFee < MINIMUM_EARLY_VESTING_FEE) revert EarlyVestingFeeTooLow();
        if (_deposit == 0) revert ZeroAmount();
        if (_duration == 0 || _duration > MAX_DURATION) revert InvalidDuration();

        /// @dev this will revert if the kwenta token transfer fails
        kwenta.transferFrom(msg.sender, address(this), _deposit);

        // Append vesting entry for the beneficiary address
        _mint(_beneficiary, _deposit, _duration, _earlyVestingFee);
    }

    /// @inheritdoc IRewardEscrowV2
    function appendVestingEntry(address _account, uint256 _quantity)
        external
        override
        onlyStakingRewards
    {
        _mint(_account, _quantity, DEFAULT_DURATION, DEFAULT_EARLY_VESTING_FEE);
    }

    /// @inheritdoc IRewardEscrowV2
    function bulkTransferFrom(address _from, address _to, uint256[] calldata _entryIDs)
        external
        override
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
    function _transfer(address _from, address _to, uint256 _entryID) internal override {
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

    function _mint(address _account, uint256 _quantity, uint256 _duration, uint8 _earlyVestingFee)
        internal
    {
        // There must be enough balance in the contract to provide for the vesting entry.
        totalEscrowedBalance += _quantity;
        assert(kwenta.balanceOf(address(this)) >= totalEscrowedBalance);

        // Escrow the tokens for duration.
        uint256 endTime = block.timestamp + _duration;

        // Add quantity to account's escrowed balance
        totalEscrowedAccountBalance[_account] += _quantity;

        uint256 entryID = nextEntryId;
        vestingSchedules[entryID] = VestingEntry({
            endTime: uint64(endTime),
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
    function pauseRewardEscrow() external override onlyOwner {
        _pause();
    }

    /// @inheritdoc IRewardEscrowV2
    function unpauseRewardEscrow() external override onlyOwner {
        _unpause();
    }
}
