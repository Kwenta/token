// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

// Inheritance
import "./utils/Owned.sol";
import "./interfaces/IRewardEscrowV2.sol";

// Libraries
import "./libraries/SafeDecimalMath.sol";

// Internal references
import "./interfaces/IKwenta.sol";
import "./interfaces/IStakingRewards.sol";

contract RewardEscrowV2 is Owned, IRewardEscrowV2 {
    using SafeDecimalMath for uint256;

    /* ========== CONSTANTS/IMMUTABLES ========== */

    /* Max escrow duration */
    uint256 public constant MAX_DURATION = 2 * 52 weeks; // Default max 2 years duration

    IKwenta private immutable kwenta;

    /* ========== STATE VARIABLES ========== */

    IStakingRewards public stakingRewards;

    // TODO: remove account from this mapping and just use: entryID => VestingEntry / mapping(uint256 => VestingEntries.VestingEntry)
    // mapping of account addresses to entryID => VestingEntry pairs
    mapping(address => mapping(uint256 => VestingEntries.VestingEntry)) public vestingSchedules;

    // Counter for new vesting entry ids
    uint256 public nextEntryId;

    // An account's total escrowed KWENTA balance to save recomputing this for fee extraction purposes
    mapping(address => uint256) public override totalEscrowedAccountBalance;

    // An account's total vested reward KWENTA
    mapping(address => uint256) public override totalVestedAccountBalance;

    // The total remaining escrowed balance, for verifying the actual KWENTA balance of this contract against
    uint256 public totalEscrowedBalance;

    // notice treasury address may change
    address public treasuryDAO;

    // Mapping owner address to entry count
    mapping(address => uint256) private _entryBalances;

    // Mapping from owner to list of entryIDs
    mapping(address => mapping(uint256 => uint256)) private _ownedEntries;

    // Mapping from entryID to index on the owner tokens list
    mapping(uint256 => uint256) private _ownedEntriesIndex;

    /* ========== MODIFIERS ========== */
    modifier onlyStakingRewards() {
        require(msg.sender == address(stakingRewards), "Only the StakingRewards can perform this action");
        _;
    }

    /* ========== EVENTS ========== */
    event Vested(address indexed beneficiary, uint256 value);
    event VestingEntryCreated(address indexed beneficiary, uint256 value, uint256 duration, uint256 entryID);
    event StakingRewardsSet(address stakingRewards);
    event TreasuryDAOSet(address treasuryDAO);

    /* ========== CONSTRUCTOR ========== */

    constructor(address _owner, address _kwenta) Owned(_owner) {
        nextEntryId = 1;

        // set the Kwenta contract address as we need to transfer KWENTA when the user vests
        kwenta = IKwenta(_kwenta);
    }

    /* ========== SETTERS ========== */

    /*
    * @notice Function used to define the StakingRewards to use
    */
    function setStakingRewards(address _stakingRewards) public onlyOwner {
        require(address(stakingRewards) == address(0), "Staking Rewards already set");
        stakingRewards = IStakingRewards(_stakingRewards);
        emit StakingRewardsSet(address(_stakingRewards));
    }

    /// @notice set treasuryDAO address
    /// @dev only owner may change address
    function setTreasuryDAO(address _treasuryDAO) external onlyOwner {
        require(_treasuryDAO != address(0), "RewardEscrow: Zero Address");
        treasuryDAO = _treasuryDAO;
        emit TreasuryDAOSet(treasuryDAO);
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
    function balanceOf(address account) public view override returns (uint256) {
        return totalEscrowedAccountBalance[account];
    }

    /**
     * @notice The number of vesting dates in an account's schedule.
     */
    function numVestingEntries(address account) external view override returns (uint256) {
        return _entryBalances[account];
    }

    /**
     * @notice Get a particular schedule entry for an account.
     * @return endTime the vesting entry object
     * @return escrowAmount rate per second emission.
     */
    function getVestingEntry(address account, uint256 entryID)
        external
        view
        override
        returns (uint64 endTime, uint256 escrowAmount, uint256 duration)
    {
        endTime = vestingSchedules[account][entryID].endTime;
        escrowAmount = vestingSchedules[account][entryID].escrowAmount;
        duration = vestingSchedules[account][entryID].duration;
    }

    function getVestingSchedules(address account, uint256 index, uint256 pageSize)
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

        // TODO: extract logic into helper as reused in getAccountVestingEntryIDs
        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = _entryBalances[account];
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }

        uint256 n = endIndex - index;
        VestingEntries.VestingEntryWithID[] memory vestingEntries = new VestingEntries.VestingEntryWithID[](n);
        for (uint256 i; i < n; i++) {
            uint256 entryID = _ownedEntries[account][i + index];

            VestingEntries.VestingEntry memory entry = vestingSchedules[account][entryID];

            vestingEntries[i] = VestingEntries.VestingEntryWithID({
                endTime: uint64(entry.endTime),
                escrowAmount: entry.escrowAmount,
                entryID: entryID
            });
        }
        return vestingEntries;
    }

    function getAccountVestingEntryIDs(address account, uint256 index, uint256 pageSize)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256 endIndex = index + pageSize;

        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = _entryBalances[account];
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }
        if (endIndex <= index) {
            return new uint256[](0);
        }

        uint256 n = endIndex - index;
        uint256[] memory page = new uint256[](n);
        for (uint256 i; i < n; i++) {
            page[i] = _ownedEntries[account][i + index];
        }
        return page;
    }

    function getVestingQuantity(address account, uint256[] calldata entryIDs)
        external
        view
        override
        returns (uint256 total, uint256 totalFee)
    {
        for (uint256 i = 0; i < entryIDs.length; i++) {
            VestingEntries.VestingEntry memory entry = vestingSchedules[account][entryIDs[i]];

            /* Skip entry if escrowAmount == 0 */
            if (entry.escrowAmount != 0) {
                (uint256 quantity, uint256 fee) = _claimableAmount(entry);

                /* add quantity to total */
                total += quantity;
                totalFee += fee;
            }
        }
    }

    function getVestingEntryClaimable(address account, uint256 entryID)
        external
        view
        override
        returns (uint256 quantity, uint256 fee)
    {
        VestingEntries.VestingEntry memory entry = vestingSchedules[account][entryID];
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

    function _earlyVestFee(VestingEntries.VestingEntry memory _entry) internal view returns (uint256 earlyVestFee) {
        uint256 timeUntilVest = _entry.endTime - block.timestamp;
        // Fee starts at 90% and falls linearly
        uint256 initialFee = _entry.escrowAmount * 9 / 10;
        earlyVestFee = initialFee * timeUntilVest / _entry.duration;
    }

    function _isEscrowStaked(address _account) internal view returns (bool) {
        return stakingRewards.escrowedBalanceOf(_account) > 0;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * Vest escrowed amounts that are claimable
     * Allows users to vest their vesting entries based on msg.sender
     */

    function vest(uint256[] calldata entryIDs) external override {
        uint256 total;
        uint256 totalFee;
        for (uint256 i = 0; i < entryIDs.length; i++) {
            VestingEntries.VestingEntry storage entry = vestingSchedules[msg.sender][entryIDs[i]];

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
            if (_isEscrowStaked(msg.sender)) {
                uint256 totalWithFee = total + totalFee;
                uint256 unstakedEscrow =
                    totalEscrowedAccountBalance[msg.sender] - stakingRewards.escrowedBalanceOf(msg.sender);
                if (totalWithFee > unstakedEscrow) {
                    uint256 amountToUnstake = totalWithFee - unstakedEscrow;
                    unstakeEscrow(amountToUnstake);
                }
            }

            // Send any fee to Treasury
            if (totalFee != 0) {
                _reduceAccountEscrowBalances(msg.sender, totalFee);
                require(IKwenta(address(kwenta)).transfer(treasuryDAO, totalFee), "RewardEscrow: Token Transfer Failed");
            }

            // Transfer kwenta
            _transferVestedTokens(msg.sender, total);
        }
    }

    /**
     * @notice Create an escrow entry to lock KWENTA for a given duration in seconds
     * @dev This call expects that the depositor (msg.sender) has already approved the Reward escrow contract
     * to spend the the amount being escrowed.
     */
    function createEscrowEntry(address beneficiary, uint256 deposit, uint256 duration) external override {
        require(beneficiary != address(0), "Cannot create escrow with address(0)");

        /* Transfer KWENTA from msg.sender */
        require(kwenta.transferFrom(msg.sender, address(this), deposit), "Token transfer failed");

        /* Append vesting entry for the beneficiary address */
        _appendVestingEntry(beneficiary, deposit, duration);
    }

    /**
     * @notice Add a new vesting entry at a given time and quantity to an account's schedule.
     * @dev A call to this should accompany a previous successful call to kwenta.transfer(rewardEscrow, amount),
     * to ensure that when the funds are withdrawn, there is enough balance.
     * @param account The account to append a new vesting entry to.
     * @param quantity The quantity of KWENTA that will be escrowed.
     * @param duration The duration that KWENTA will be emitted.
     */
    function appendVestingEntry(address account, uint256 quantity, uint256 duration)
        external
        override
        onlyStakingRewards
    {
        _appendVestingEntry(account, quantity, duration);
    }

    /**
     * @notice Stakes escrowed KWENTA.
     * @dev No tokens are transfered during this process, but the StakingRewards escrowed balance is updated.
     * @param _amount The amount of escrowed KWENTA to be staked.
     */
    function stakeEscrow(uint256 _amount) external override {
        require(
            _amount + stakingRewards.escrowedBalanceOf(msg.sender) <= totalEscrowedAccountBalance[msg.sender],
            "Insufficient unstaked escrow"
        );
        stakingRewards.stakeEscrow(msg.sender, _amount);
    }

    /**
     * @notice Unstakes escrowed KWENTA.
     * @dev No tokens are transfered during this process, but the StakingRewards escrowed balance is updated.
     * @param _amount The amount of escrowed KWENTA to be unstaked.
     */
    function unstakeEscrow(uint256 _amount) public override {
        stakingRewards.unstakeEscrow(msg.sender, _amount);
    }

    /**
     * @notice Transfer a vested entry from one account to another
     *  Sufficient escrowed KWENTA must be unstaked for the transfer to succeed
     * @param entryID the id of the entry to transfer
     * @param account The account to transfer the vesting entry to
     */
    function transferVestingEntry(uint256 entryID, address account) external override {
        _transferVestingEntry(entryID, account);
    }

    /**
     * @notice Transfer multiple vested entries from one account to another
     *  Sufficient escrowed KWENTA must be unstaked for the transfer to succeed
     * @param entryIDs a list of the ids of the entries to transfer
     * @param account The account to transfer the vesting entries to
     */
    function bulkTransferVestingEntries(uint256[] calldata entryIDs, address account) external {
        uint256 length = entryIDs.length;
        for (uint256 i = 0; i < length; ++i) {
            _transferVestingEntry(entryIDs[i], account);
        }
    }

    /* ========== INTERNALS ========== */

    /* Transfer vested tokens and update totalEscrowedAccountBalance, totalVestedAccountBalance */
    function _transferVestedTokens(address _account, uint256 _amount) internal {
        _reduceAccountEscrowBalances(_account, _amount);
        totalVestedAccountBalance[_account] += _amount;
        kwenta.transfer(_account, _amount);
        emit Vested(_account, _amount);
    }

    function _reduceAccountEscrowBalances(address _account, uint256 _amount) internal {
        // Reverts if amount being vested is greater than the account's existing totalEscrowedAccountBalance
        totalEscrowedBalance -= _amount;
        totalEscrowedAccountBalance[_account] -= _amount;
    }

    function _appendVestingEntry(address account, uint256 quantity, uint256 duration) internal {
        /* No empty or already-passed vesting entries allowed. */
        require(quantity != 0, "Quantity cannot be zero");
        require(duration > 0 && duration <= MAX_DURATION, "Cannot escrow with 0 duration OR above max_duration");

        /* There must be enough balance in the contract to provide for the vesting entry. */
        totalEscrowedBalance += quantity;

        require(
            totalEscrowedBalance <= kwenta.balanceOf(address(this)),
            "Must be enough balance in the contract to provide for the vesting entry"
        );

        /* Escrow the tokens for duration. */
        uint256 endTime = block.timestamp + duration;

        /* Add quantity to account's escrowed balance */
        totalEscrowedAccountBalance[account] += quantity;

        uint256 entryID = nextEntryId;
        vestingSchedules[account][entryID] =
            VestingEntries.VestingEntry({endTime: uint64(endTime), escrowAmount: quantity, duration: duration});

        _addTokenToOwnerEnumeration(account, entryID);

        /* Increment the next entry id. */
        nextEntryId++;

        emit VestingEntryCreated(account, quantity, duration, entryID);
    }

    function _addTokenToOwnerEnumeration(address to, uint256 entryID) private {
        uint256 length = _entryBalances[to];
        _ownedEntries[to][length] = entryID;
        _ownedEntriesIndex[entryID] = length;
        _entryBalances[to] += 1;
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 entryID) private {
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

    function _transferVestingEntry(uint256 entryID, address account) internal {
        if (entryID >= nextEntryId) revert InvalidEntry(entryID);
        VestingEntries.VestingEntry memory entry = vestingSchedules[msg.sender][entryID];
        if (entry.endTime == 0) revert NotYourEntry(entryID);

        uint256 escrowedBalance = totalEscrowedAccountBalance[msg.sender];
        uint256 stakedBalance = stakingRewards.escrowedBalanceOf(msg.sender);
        uint256 unstakedBalance = escrowedBalance - stakedBalance;

        if (unstakedBalance < entry.escrowAmount) {
            revert InsufficientUnstakedBalance(entryID, entry.escrowAmount, unstakedBalance);
        }

        delete vestingSchedules[msg.sender][entryID];
        vestingSchedules[account][entryID] = entry;

        totalEscrowedAccountBalance[msg.sender] -= entry.escrowAmount;
        totalEscrowedAccountBalance[account] += entry.escrowAmount;

        if (msg.sender != account) {
            _removeTokenFromOwnerEnumeration(msg.sender, entryID);
            _addTokenToOwnerEnumeration(account, entryID);
        }
    }
}