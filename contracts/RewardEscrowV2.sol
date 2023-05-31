// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inheritance
import {IRewardEscrowV2, VestingEntries} from "./interfaces/IRewardEscrowV2.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Internal references
import {IKwenta} from "./interfaces/IKwenta.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";

/// @title KWENTA Reward Escrow
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

    /// @notice Contract for KWENTA ERC20 token
    IKwenta public kwenta;

    /// @notice Contract for StakingRewardsV2
    IStakingRewardsV2 public stakingRewards;

    /*///////////////////////////////////////////////////////////////
                                STATE
    ///////////////////////////////////////////////////////////////*/

    ///@notice mapping of entryIDs to vesting entries
    mapping(uint256 => VestingEntries.VestingEntry) public vestingSchedules;

    /// @notice Counter for new vesting entry ids
    uint256 public nextEntryId;

    /// @notice An account's total escrowed KWENTA balance to save recomputing this for fee extraction purposes
    mapping(address => uint256) public totalEscrowedAccountBalance;

    /// @notice An account's total vested reward KWENTA
    mapping(address => uint256) public totalVestedAccountBalance;

    /// @notice The total remaining escrowed balance, for verifying the actual KWENTA balance of this contract against
    uint256 public totalEscrowedBalance;

    /// @notice treasury address - this may change
    address public treasuryDAO;

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
    function initialize(address _owner, address _kwenta) external override initializer {
        // Initialize inherited contracts
        __Ownable_init();
        __UUPSUpgradeable_init();
        __UUPSUpgradeable_init();
        __ERC721_init("Kwenta Reward Escrow", "KRE");

        // transfer ownership
        transferOwnership(_owner);

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
        emit StakingRewardsSet(address(_stakingRewards));
    }

    /// @inheritdoc IRewardEscrowV2
    function setTreasuryDAO(address _treasuryDAO) external override onlyOwner {
        if (_treasuryDAO == address(0)) revert ZeroAddress();
        treasuryDAO = _treasuryDAO;
        emit TreasuryDAOSet(treasuryDAO);
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
        endTime = vestingSchedules[_entryID].endTime;
        escrowAmount = vestingSchedules[_entryID].escrowAmount;
        duration = vestingSchedules[_entryID].duration;
        earlyVestingFee = vestingSchedules[_entryID].earlyVestingFee;
    }

    /// @inheritdoc IRewardEscrowV2
    function getVestingSchedules(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        override
        returns (VestingEntries.VestingEntryWithID[] memory)
    {
        uint256 endIndex = _index + _pageSize;

        // If index starts after the endIndex return no results
        if (endIndex <= _index) {
            return new VestingEntries.VestingEntryWithID[](0);
        }

        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = balanceOf(_account);
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }

        uint256 n = endIndex - _index;
        VestingEntries.VestingEntryWithID[] memory vestingEntries =
            new VestingEntries.VestingEntryWithID[](n);
        for (uint256 i; i < n;) {
            uint256 entryID = tokenOfOwnerByIndex(_account, i + _index);

            VestingEntries.VestingEntry memory entry = vestingSchedules[entryID];

            vestingEntries[i] = VestingEntries.VestingEntryWithID({
                endTime: uint64(entry.endTime),
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
            page[i] = tokenOfOwnerByIndex(_account, i + _index);

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
            VestingEntries.VestingEntry memory entry = vestingSchedules[_entryIDs[i]];

            // Skip entry if escrowAmount == 0
            if (entry.escrowAmount != 0) {
                (uint256 quantity, uint256 fee) = _claimableAmount(entry);

                // add quantity to total
                total += quantity;
                totalFee += fee;
            }

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
        VestingEntries.VestingEntry memory entry = vestingSchedules[_entryID];
        (quantity, fee) = _claimableAmount(entry);
    }

    function _claimableAmount(VestingEntries.VestingEntry memory _entry)
        internal
        view
        returns (uint256 quantity, uint256 fee)
    {
        uint256 escrowAmount = _entry.escrowAmount;

        if (escrowAmount != 0) {
            // Full escrow amounts claimable if block.timestamp equal to or after entry endTime
            if (block.timestamp >= _entry.endTime) {
                quantity = escrowAmount;
            } else {
                fee = _earlyVestFee(_entry);
                quantity = escrowAmount - fee;
            }
        }
    }

    function _earlyVestFee(VestingEntries.VestingEntry memory _entry)
        internal
        view
        returns (uint256 earlyVestFee)
    {
        uint256 timeUntilVest = _entry.endTime - block.timestamp;
        // Fee starts by default at 90% (but could be any percentage) and falls linearly
        earlyVestFee = _entry.escrowAmount * _entry.earlyVestingFee * timeUntilVest /
            (100 * _entry.duration);
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
            VestingEntries.VestingEntry storage entry = vestingSchedules[_entryIDs[i]];
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

        // Transfer vested tokens. Will revert if total > totalEscrowedAccountBalance
        if (total != 0) {
            uint256 totalWithFee = total + totalFee;

            // Withdraw staked escrowed kwenta if needed for reward
            uint256 stakedEscrow = stakingRewards.escrowedBalanceOf(msg.sender);
            if (stakedEscrow > 0) {
                uint256 unstakedEscrow = totalEscrowedAccountBalance[msg.sender] - stakedEscrow;
                if (totalWithFee > unstakedEscrow) {
                    uint256 amountToUnstake = totalWithFee - unstakedEscrow;
                    stakingRewards.unstakeEscrowSkipCooldown(msg.sender, amountToUnstake);
                }
            }

            // update balances
            totalEscrowedBalance -= totalWithFee;
            totalEscrowedAccountBalance[msg.sender] -= totalWithFee;
            totalVestedAccountBalance[msg.sender] += total;

            // trigger event
            emit Vested(msg.sender, total);

            // Send any fee to Treasury
            if (totalFee != 0) {
                /// @dev this will revert if the kwenta token transfer fails
                kwenta.transfer(treasuryDAO, totalFee);
            }

            // Transfer kwenta
            /// @dev this will revert if the kwenta token transfer fails
            kwenta.transfer(msg.sender, total);
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
        uint256 totalEscrowTransferred;
        uint256 entryIDsLength = _entryIDs.length;
        for (uint256 i = 0; i < entryIDsLength;) {
            totalEscrowTransferred += vestingSchedules[_entryIDs[i]].escrowAmount;
            require(
                _isApprovedOrOwner(_msgSender(), _entryIDs[i]),
                "ERC721: caller is not token owner or approved"
            );
            super._transfer(_from, _to, _entryIDs[i]);
            unchecked {
                ++i;
            }
        }

        _checkIfSufficientUnstakedBalance(_from, totalEscrowTransferred);

        totalEscrowedAccountBalance[_from] -= totalEscrowTransferred;
        totalEscrowedAccountBalance[_to] += totalEscrowTransferred;
    }

    /*///////////////////////////////////////////////////////////////
                                INTERNALS
    ///////////////////////////////////////////////////////////////*/

    /// @dev override the internal _transfer function to ensure vestingSchedules and account balances are updated
    /// and that there is sufficient unstaked escrow for a transfer
    function _transfer(address _from, address _to, uint256 _entryID) internal override {
        uint256 escrowAmount = vestingSchedules[_entryID].escrowAmount;

        _checkIfSufficientUnstakedBalance(_from, escrowAmount);

        totalEscrowedAccountBalance[_from] -= escrowAmount;
        totalEscrowedAccountBalance[_to] += escrowAmount;

        super._transfer(_from, _to, _entryID);
    }

    function _burn(uint256 _entryID) internal override {
        delete vestingSchedules[_entryID];
        super._burn(_entryID);
    }

    function _mint(address _account, uint256 _quantity, uint256 _duration, uint8 _earlyVestingFee)
        internal
    {
        // There must be enough balance in the contract to provide for the vesting entry.
        totalEscrowedBalance += _quantity;
        if (kwenta.balanceOf(address(this)) < totalEscrowedBalance) revert InsufficientBalance();

        // Escrow the tokens for duration.
        uint256 endTime = block.timestamp + _duration;

        // Add quantity to account's escrowed balance
        totalEscrowedAccountBalance[_account] += _quantity;

        uint256 entryID = nextEntryId;
        vestingSchedules[entryID] = VestingEntries.VestingEntry({
            endTime: uint64(endTime),
            escrowAmount: _quantity,
            duration: _duration,
            earlyVestingFee: _earlyVestingFee
        });

        // Increment the next entry id.
        ++nextEntryId;

        emit VestingEntryCreated(_account, _quantity, _duration, entryID, _earlyVestingFee);

        super._mint(_account, entryID);
    }

    function _checkIfSufficientUnstakedBalance(address _account, uint256 _amount) internal view {
        uint256 unstakedEscrow = unstakedEscrowedBalanceOf(_account);
        if (unstakedEscrow < _amount) revert InsufficientUnstakedBalance(_amount, unstakedEscrow);
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
