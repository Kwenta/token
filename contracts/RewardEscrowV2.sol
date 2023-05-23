// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inheritance
import "./interfaces/IRewardEscrowV2.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Internal references
import "./interfaces/IKwenta.sol";
import "./interfaces/IStakingRewardsV2.sol";
import "./StakingAccount.sol";

contract RewardEscrowV2 is
    IRewardEscrowV2,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /* ========== CONSTANTS/IMMUTABLES ========== */

    /* Max escrow duration */
    uint256 public constant MAX_DURATION = 4 * 52 weeks; // Default max 4 years duration

    uint8 public constant DEFAULT_EARLY_VESTING_FEE = 90; // Default 90 percent

    IKwenta private kwenta;

    /// @notice staking account contract which abstracts users "accounts" for staking
    // TODO: update to IStakingAccount
    StakingAccount public stakingAccount;

    /* ========== STATE VARIABLES ========== */

    IStakingRewardsV2 public stakingRewardsV2;

    // mapping of entryIDs to vesting entries
    // entryID => VestingEntry
    mapping(uint256 => VestingEntries.VestingEntry) public vestingSchedules;

    // Counter for new vesting entry ids
    uint256 public nextEntryId;

    // An account's total escrowed KWENTA balance to save recomputing this for fee extraction purposes
    // accountId => totalEscrowedAccountBalance
    mapping(uint256 => uint256) public override totalEscrowedAccountBalance;

    // An account's total vested reward KWENTA
    // accountId => totalVestedAccountBalance
    mapping(uint256 => uint256) public override totalVestedAccountBalance;

    // The total remaining escrowed balance, for verifying the actual KWENTA balance of this contract against
    uint256 public totalEscrowedBalance;

    // notice treasury address may change
    address public treasuryDAO;

    // Mapping owner address to entry count
    // accountId => entryCount
    mapping(uint256 => uint256) private _entryBalances;

    // Mapping from owner to list of entryIDs
    // accountId => entryID[]
    mapping(uint256 => mapping(uint256 => uint256)) private _ownedEntries;

    // Mapping from entryID to index on the owner tokens list
    mapping(uint256 => uint256) private _ownedEntriesIndex;

    // Mapping of who owns which entries
    // entryID => accountId
    mapping(uint256 => uint256) private _entryOwners;

    /* ========== MODIFIERS ========== */
    modifier onlyStakingRewards() {
        require(
            msg.sender == address(stakingRewardsV2),
            "Only the StakingRewards can perform this action"
        );
        _;
    }

    /* ========== EVENTS ========== */
    event Vested(uint256 beneficiary, uint256 value);
    event VestingEntryCreated(
        uint256 beneficiary,
        uint256 value,
        uint256 duration,
        uint256 entryID
    );
    event StakingRewardsSet(address stakingRewardsV2);
    event TreasuryDAOSet(address treasuryDAO);
    event VestingEntryTransfer(uint256 from, uint256 to, uint256 entryID);

    /* ========== CONSTRUCTOR ========== */

    /// @dev disable default constructor for disable implementation contract
    /// Actual contract construction will take place in the initialize function via proxy
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _kwenta) external initializer {
        // Initialize inherited contracts
        __Ownable_init();
        __UUPSUpgradeable_init();

        // transfer ownership
        transferOwnership(_owner);

        // define variables
        nextEntryId = 1;
        kwenta = IKwenta(_kwenta);
    }

    /* ========== SETTERS ========== */

    /*
    * @notice Function used to define the StakingRewards to use
    */
    function setStakingRewardsV2(address _stakingRewardsV2) public onlyOwner {
        require(
            address(stakingRewardsV2) == address(0),
            "Staking Rewards already set"
        );
        stakingRewardsV2 = IStakingRewardsV2(_stakingRewardsV2);
        emit StakingRewardsSet(address(_stakingRewardsV2));
    }

    /// @notice set treasuryDAO address
    /// @dev only owner may change address
    function setTreasuryDAO(address _treasuryDAO) external onlyOwner {
        require(_treasuryDAO != address(0), "RewardEscrow: Zero Address");
        treasuryDAO = _treasuryDAO;
        emit TreasuryDAOSet(treasuryDAO);
    }

    /// @notice set StakingAccount address
    /// @dev only owner may change address
    function setStakingAccount(address _stakingAccount) external onlyOwner {
        require(_stakingAccount != address(0), "RewardEscrow: Zero Address");
        stakingAccount = StakingAccount(_stakingAccount);
        // TODO: emit event
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice helper function to return kwenta address
     */
    function getKwentaAddress() external view override returns (address) {
        return address(kwenta);
    }

    /**
     * @notice A simple alias to totalEscrowedAccountBalance: provides ERC20 balance integration.
     */
    function balanceOf(uint256 accountId)
        public
        view
        override
        returns (uint256)
    {
        return totalEscrowedAccountBalance[accountId];
    }

    /**
     * @notice Get the amount of escrowed kwenta that is not staked for a given account
     */
    function unstakedEscrowBalanceOf(uint256 accountId)
        public
        view
        override
        returns (uint256)
    {
        return totalEscrowedAccountBalance[accountId]
            - stakingRewardsV2.escrowedBalanceOf(accountId);
    }

    /**
     * @notice The number of vesting dates in an account's schedule.
     */
    function numVestingEntries(uint256 accountId)
        external
        view
        override
        returns (uint256)
    {
        return _entryBalances[accountId];
    }

    /**
     * @notice Get the details of a given vesting entry
     * @param entryID The id of the vesting entry.
     * @return endTime the vesting entry object
     * @return escrowAmount rate per second emission.
     */
    function getVestingEntry(uint256 entryID)
        external
        view
        override
        returns (
            uint64 endTime,
            uint256 escrowAmount,
            uint256 duration,
            uint8 earlyVestingFee
        )
    {
        endTime = vestingSchedules[entryID].endTime;
        escrowAmount = vestingSchedules[entryID].escrowAmount;
        duration = vestingSchedules[entryID].duration;
        earlyVestingFee = vestingSchedules[entryID].earlyVestingFee;
    }

    function getVestingSchedules(
        uint256 accountId,
        uint256 index,
        uint256 pageSize
    )
        external
        view
        override
        returns (VestingEntries.VestingEntryWithID[] memory)
    {
        uint256 endIndex = index + pageSize;

        // If index starts after the endIndex return no results
        if (endIndex <= index) {
            return new VestingEntries.VestingEntryWithID[](0);
        }

        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = _entryBalances[accountId];
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }

        uint256 n = endIndex - index;
        VestingEntries.VestingEntryWithID[] memory vestingEntries =
            new VestingEntries.VestingEntryWithID[](n);
        for (uint256 i; i < n; ) {
            uint256 entryID = _ownedEntries[accountId][i + index];

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

    function getAccountVestingEntryIDs(
        uint256 accountId,
        uint256 index,
        uint256 pageSize
    ) external view override returns (uint256[] memory) {
        uint256 endIndex = index + pageSize;

        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = _entryBalances[accountId];
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }
        if (endIndex <= index) {
            return new uint256[](0);
        }

        uint256 n = endIndex - index;
        uint256[] memory page = new uint256[](n);
        for (uint256 i; i < n; ) {
            page[i] = _ownedEntries[accountId][i + index];

            unchecked {
                ++i;
            }
        }
        return page;
    }

    function getVestingQuantity(uint256[] calldata entryIDs)
        external
        view
        override
        returns (uint256 total, uint256 totalFee)
    {
        uint256 entryIDsLength = entryIDs.length;
        for (uint256 i = 0; i < entryIDsLength; ) {
            VestingEntries.VestingEntry memory entry =
                vestingSchedules[entryIDs[i]];

            /* Skip entry if escrowAmount == 0 */
            if (entry.escrowAmount != 0) {
                (uint256 quantity, uint256 fee) = _claimableAmount(entry);

                /* add quantity to total */
                total += quantity;
                totalFee += fee;
            }

            unchecked {
                ++i;
            }
        }
    }

    function getVestingEntryClaimable(uint256 entryID)
        external
        view
        override
        returns (uint256 quantity, uint256 fee)
    {
        VestingEntries.VestingEntry memory entry = vestingSchedules[entryID];
        (quantity, fee) = _claimableAmount(entry);
    }

    function _claimableAmount(VestingEntries.VestingEntry memory _entry)
        internal
        view
        returns (uint256 quantity, uint256 fee)
    {
        uint256 escrowAmount = _entry.escrowAmount;

        if (escrowAmount != 0) {
            /* Full escrow amounts claimable if block.timestamp equal to or after entry endTime */
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
        // Fee starts at 90% and falls linearly
        uint256 initialFee = _entry.escrowAmount * _entry.earlyVestingFee / 100;
        earlyVestFee = initialFee * timeUntilVest / _entry.duration;
    }

    function _isEscrowStaked(uint256 _accountId) internal view returns (bool) {
        return stakingRewardsV2.escrowedBalanceOf(_accountId) > 0;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * Vest escrowed amounts that are claimable
     * Allows users to vest their vesting entries based on accountId
     */

    function vest(uint256 accountId, uint256[] calldata entryIDs) external override {
        uint256 total;
        uint256 totalFee;
        uint256 entryIDsLength = entryIDs.length;
        for (uint256 i = 0; i < entryIDsLength; ++i) {
            VestingEntries.VestingEntry storage entry =
                vestingSchedules[entryIDs[i]];
            if (_entryOwners[entryIDs[i]] != accountId) {
                continue;
            }

            /* Skip entry if escrowAmount == 0 already vested */
            if (entry.escrowAmount != 0) {
                (uint256 quantity, uint256 fee) = _claimableAmount(entry);

                /* update entry to remove escrowAmount */
                entry.escrowAmount = 0;

                /* add quantity to total */
                total += quantity;
                totalFee += fee;
            }
        }

        /* Transfer vested tokens. Will revert if total > totalEscrowedAccountBalance */
        if (total != 0) {
            // Withdraw staked escrowed kwenta if needed for reward
            if (_isEscrowStaked(accountId)) {
                uint256 totalWithFee = total + totalFee;
                uint256 unstakedEscrow = unstakedEscrowBalanceOf(accountId);
                if (totalWithFee > unstakedEscrow) {
                    uint256 amountToUnstake = totalWithFee - unstakedEscrow;
                    unstakeEscrow(accountId, amountToUnstake);
                }
            }

            // Send any fee to Treasury
            if (totalFee != 0) {
                _reduceAccountEscrowBalances(accountId, totalFee);
                require(
                    kwenta.transfer(treasuryDAO, totalFee),
                    "RewardEscrow: Token Transfer Failed"
                );
            }

            // Transfer kwenta
            _transferVestedTokens(accountId, total);
        }
    }

    /**
     * @notice Create an escrow entry to lock KWENTA for a given duration in seconds
     * @dev This call expects that the depositor (msg.sender) has already approved the Reward escrow contract
     * to spend the the amount being escrowed.
     */
    function createEscrowEntry(
        uint256 beneficiary,
        uint256 deposit,
        uint256 duration,
        uint8 earlyVestingFee
    ) external override {
        // TODO: improve this - ownerOf should revert if address(0) - hence require is useless
        require(
            stakingAccount.ownerOf(beneficiary) != address(0), "Cannot create escrow with address(0)"
        );

        /* Transfer KWENTA from msg.sender */
        require(
            kwenta.transferFrom(msg.sender, address(this), deposit),
            "Token transfer failed"
        );

        /* Append vesting entry for the beneficiary address */
        _appendVestingEntry(beneficiary, deposit, duration, earlyVestingFee);
    }

    /**
     * @notice Add a new vesting entry at a given time and quantity to an account's schedule.
     * @dev A call to this should accompany a previous successful call to kwenta.transfer(rewardEscrow, amount),
     * to ensure that when the funds are withdrawn, there is enough balance.
     * @param accountId The account to append a new vesting entry to.
     * @param quantity The quantity of KWENTA that will be escrowed.
     * @param duration The duration that KWENTA will be emitted.
     */
    function appendVestingEntry(
        uint256 accountId,
        uint256 quantity,
        uint256 duration
    ) external override onlyStakingRewards {
        _appendVestingEntry(
            accountId, quantity, duration, DEFAULT_EARLY_VESTING_FEE
        );
    }

    /**
     * @notice Stakes escrowed KWENTA.
     * @dev No tokens are transfered during this process, but the StakingRewards escrowed balance is updated.
     * @param _amount The amount of escrowed KWENTA to be staked.
     */
    function stakeEscrow(uint256 _accountId, uint256 _amount) external override {
        stakingRewardsV2.stakeEscrow(_accountId, _amount);
    }

    /**
     * @notice Unstakes escrowed KWENTA.
     * @dev No tokens are transfered during this process, but the StakingRewards escrowed balance is updated.
     * @param _amount The amount of escrowed KWENTA to be unstaked.
     */
    function unstakeEscrow(uint256 _accountId, uint256 _amount) public override {
        stakingRewardsV2.unstakeEscrow(_accountId, _amount);
    }

    /**
     * @notice Transfer a vested entry from one account to another
     *  Sufficient escrowed KWENTA must be unstaked for the transfer to succeed
     * @param from The account to transfer the vesting entry from
     * @param to The account to transfer the vesting entry to
     * @param entryID the id of the entry to transfer
     */
    function transferVestingEntry(uint256 from, uint256 to, uint256 entryID)
        external
        override
    {
        _transferVestingEntry(from, to, entryID);
    }

    /**
     * @notice Transfer multiple vested entries from one account to another
     *  Sufficient escrowed KWENTA must be unstaked for the transfer to succeed
     * @param from The account to transfer the vesting entries from
     * @param to The account to transfer the vesting entries to
     * @param entryIDs a list of the ids of the entries to transfer
     */
    function bulkTransferVestingEntries(
        uint256 from,
        uint256 to,
        uint256[] calldata entryIDs
    ) external override {
        uint256 entryIDsLength = entryIDs.length;
        for (uint256 i = 0; i < entryIDsLength; ) {
            _transferVestingEntry(from, to, entryIDs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /* ========== INTERNALS ========== */

    /* Transfer vested tokens and update totalEscrowedAccountBalance, totalVestedAccountBalance */
    function _transferVestedTokens(uint256 _accountId, uint256 _amount)
        internal
    {
        _reduceAccountEscrowBalances(_accountId, _amount);
        totalVestedAccountBalance[_accountId] += _amount;
        kwenta.transfer(stakingAccount.ownerOf(_accountId), _amount);
        emit Vested(_accountId, _amount);
    }

    function _reduceAccountEscrowBalances(uint256 _accountId, uint256 _amount)
        internal
    {
        // Reverts if amount being vested is greater than the account's existing totalEscrowedAccountBalance
        totalEscrowedBalance -= _amount;
        totalEscrowedAccountBalance[_accountId] -= _amount;
    }

    function _appendVestingEntry(
        uint256 accountId,
        uint256 quantity,
        uint256 duration,
        uint8 earlyVestingFee
    ) internal {
        /* No empty or already-passed vesting entries allowed. */
        require(quantity != 0, "Quantity cannot be zero");
        require(
            duration > 0 && duration <= MAX_DURATION,
            "Cannot escrow with 0 duration OR above max_duration"
        );
        if (earlyVestingFee > 100) revert MaxEarlyVestingFeeIs100();

        /* There must be enough balance in the contract to provide for the vesting entry. */
        totalEscrowedBalance += quantity;

        require(
            totalEscrowedBalance <= kwenta.balanceOf(address(this)),
            "Must be enough balance in the contract to provide for the vesting entry"
        );

        /* Escrow the tokens for duration. */
        uint256 endTime = block.timestamp + duration;

        /* Add quantity to account's escrowed balance */
        totalEscrowedAccountBalance[accountId] += quantity;

        uint256 entryID = nextEntryId;
        vestingSchedules[entryID] = VestingEntries.VestingEntry({
            endTime: uint64(endTime),
            escrowAmount: quantity,
            duration: duration,
            earlyVestingFee: earlyVestingFee
        });
        _entryOwners[entryID] = accountId;

        _addTokenToOwnerEnumeration(accountId, entryID);

        /* Increment the next entry id. */
        ++nextEntryId;

        emit VestingEntryCreated(accountId, quantity, duration, entryID);
    }

    function _addTokenToOwnerEnumeration(uint256 to, uint256 entryID) private {
        uint256 length = _entryBalances[to];
        _ownedEntries[to][length] = entryID;
        _ownedEntriesIndex[entryID] = length;
        _entryBalances[to] += 1;
    }

    function _removeTokenFromOwnerEnumeration(uint256 from, uint256 entryID)
        private
    {
        // To prevent a gap in from's entrys array, we store the last entry in the index of the entry to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastEntryIndex = _entryBalances[from] - 1;
        uint256 entryIndex = _ownedEntriesIndex[entryID];

        // When the entry to delete is the last entry, the swap operation is unnecessary
        if (entryIndex != lastEntryIndex) {
            uint256 lastEntryId = _ownedEntries[from][lastEntryIndex];

            _ownedEntries[from][entryIndex] = lastEntryId; // Move the last entry to the slot of the to-delete entry
            _ownedEntriesIndex[lastEntryId] = entryIndex; // Update the moved entry's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedEntriesIndex[entryID];
        delete _ownedEntries[from][lastEntryIndex];
        _entryBalances[from] -= 1;
    }

    function _transferVestingEntry(uint256 from, uint256 to, uint256 entryID) internal {
        if (entryID >= nextEntryId) revert InvalidEntry(entryID);
        VestingEntries.VestingEntry memory entry = vestingSchedules[entryID];
        if (_entryOwners[entryID] != from) revert NotYourEntry(entryID);

        uint256 unstakedEscrow = unstakedEscrowBalanceOf(from);
        if (unstakedEscrow < entry.escrowAmount) {
            revert InsufficientUnstakedBalance(
                entryID, entry.escrowAmount, unstakedEscrow
            );
        }

        delete vestingSchedules[entryID];
        vestingSchedules[entryID] = entry;
        _entryOwners[entryID] = to;

        totalEscrowedAccountBalance[from] -= entry.escrowAmount;
        totalEscrowedAccountBalance[to] += entry.escrowAmount;

        if (from != to) {
            _removeTokenFromOwnerEnumeration(from, entryID);
            _addTokenToOwnerEnumeration(to, entryID);
        }

        emit VestingEntryTransfer(from, to, entryID);
    }

    /* ========== UPGRADEABILITY ========== */

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}
