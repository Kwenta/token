// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inheritance
import "./interfaces/IRewardEscrowV2.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Internal references
import "./interfaces/IKwenta.sol";
import "./interfaces/IStakingRewardsV2.sol";

// TODO: replace notion of an entry completely with a token
// TODO: think about safeTransfer, safeMint etc.
// TODO: Think about what functions could be "approved for" with lower risk - such that they can be delegated from a hardware wallet to a hot wallet

contract RewardEscrowV2 is
    IRewardEscrowV2,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /* ========== CONSTANTS/IMMUTABLES ========== */

    /* Max escrow duration */
    uint256 public constant MAX_DURATION = 4 * 52 weeks; // Default max 4 years duration

    uint8 public constant DEFAULT_EARLY_VESTING_FEE = 90; // Default 90 percent

    IKwenta private kwenta;

    /* ========== STATE VARIABLES ========== */

    IStakingRewardsV2 public stakingRewardsV2;

    // mapping of entryIDs to vesting entries
    mapping(uint256 => VestingEntries.VestingEntry) public vestingSchedules;

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

    /* ========== MODIFIERS ========== */
    modifier onlyStakingRewards() {
        require(
            msg.sender == address(stakingRewardsV2),
            "Only the StakingRewards can perform this action"
        );
        _;
    }

    /* ========== EVENTS ========== */
    event Vested(address indexed beneficiary, uint256 value);
    event VestingEntryCreated(
        address indexed beneficiary,
        uint256 value,
        uint256 duration,
        uint256 entryID
    );
    event StakingRewardsSet(address stakingRewardsV2);
    event TreasuryDAOSet(address treasuryDAO);

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
        // TODO: what should these names be?
        __ERC721_init("Kwenta Reward Escrow", "KRE");

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

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice helper function to return kwenta address
     */
    function getKwentaAddress() external view override returns (address) {
        return address(kwenta);
    }

    /**
     * @notice A simple alias to totalEscrowedAccountBalance
     */
    function totalEscrowBalanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        return totalEscrowedAccountBalance[account];
    }

    /**
     * @notice Get the amount of escrowed kwenta that is not staked for a given account
     */
    function unstakedEscrowBalanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        return totalEscrowedAccountBalance[account]
            - stakingRewardsV2.escrowedBalanceOf(account);
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
        address account,
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
        uint256 numEntries = balanceOf(account);
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }

        uint256 n = endIndex - index;
        VestingEntries.VestingEntryWithID[] memory vestingEntries =
            new VestingEntries.VestingEntryWithID[](n);
        for (uint256 i; i < n; ) {
            uint256 entryID = tokenOfOwnerByIndex(account, i + index);

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
        address account,
        uint256 index,
        uint256 pageSize
    ) external view override returns (uint256[] memory) {
        uint256 endIndex = index + pageSize;

        // If the page extends past the end of the list, truncate it.
        uint256 numEntries = balanceOf(account);
        if (endIndex > numEntries) {
            endIndex = numEntries;
        }
        if (endIndex <= index) {
            return new uint256[](0);
        }

        uint256 n = endIndex - index;
        uint256[] memory page = new uint256[](n);
        for (uint256 i; i < n; ) {
            page[i] = tokenOfOwnerByIndex(account, i + index);

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

    function _isEscrowStaked(address _account) internal view returns (bool) {
        return stakingRewardsV2.escrowedBalanceOf(_account) > 0;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // TODO: burn entries after they are vested?
    /**
     * Vest escrowed amounts that are claimable
     * Allows users to vest their vesting entries based on msg.sender
     */
    function vest(uint256[] calldata entryIDs) external override {
        uint256 total;
        uint256 totalFee;
        uint256 entryIDsLength = entryIDs.length;
        for (uint256 i = 0; i < entryIDsLength; ++i) {
            VestingEntries.VestingEntry storage entry =
                vestingSchedules[entryIDs[i]];
            if (_ownerOf(entryIDs[i]) != msg.sender) {
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
            if (_isEscrowStaked(msg.sender)) {
                uint256 totalWithFee = total + totalFee;
                uint256 unstakedEscrow = unstakedEscrowBalanceOf(msg.sender);
                if (totalWithFee > unstakedEscrow) {
                    uint256 amountToUnstake = totalWithFee - unstakedEscrow;
                    unstakeEscrow(amountToUnstake);
                }
            }

            // Send any fee to Treasury
            if (totalFee != 0) {
                _reduceAccountEscrowBalances(msg.sender, totalFee);
                require(
                    kwenta.transfer(treasuryDAO, totalFee),
                    "RewardEscrow: Token Transfer Failed"
                );
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
    function createEscrowEntry(
        address beneficiary,
        uint256 deposit,
        uint256 duration,
        uint8 earlyVestingFee
    ) external override {
        require(
            beneficiary != address(0), "Cannot create escrow with address(0)"
        );

        /* Transfer KWENTA from msg.sender */
        require(
            kwenta.transferFrom(msg.sender, address(this), deposit),
            "Token transfer failed"
        );

        /* Append vesting entry for the beneficiary address */
        _mint(beneficiary, deposit, duration, earlyVestingFee);
    }

    /**
     * @notice Add a new vesting entry at a given time and quantity to an account's schedule.
     * @dev A call to this should accompany a previous successful call to kwenta.transfer(rewardEscrow, amount),
     * to ensure that when the funds are withdrawn, there is enough balance.
     * @param account The account to append a new vesting entry to.
     * @param quantity The quantity of KWENTA that will be escrowed.
     * @param duration The duration that KWENTA will be emitted.
     */
    function appendVestingEntry(
        address account,
        uint256 quantity,
        uint256 duration
    ) external override onlyStakingRewards {
        _mint(
            account, quantity, duration, DEFAULT_EARLY_VESTING_FEE
        );
    }

    /**
     * @notice Stakes escrowed KWENTA.
     * @dev No tokens are transfered during this process, but the StakingRewards escrowed balance is updated.
     * @param _amount The amount of escrowed KWENTA to be staked.
     */
    function stakeEscrow(uint256 _amount) external override {
        stakingRewardsV2.stakeEscrow(msg.sender, _amount);
    }

    /**
     * @notice Unstakes escrowed KWENTA.
     * @dev No tokens are transfered during this process, but the StakingRewards escrowed balance is updated.
     * @param _amount The amount of escrowed KWENTA to be unstaked.
     */
    function unstakeEscrow(uint256 _amount) public override {
        stakingRewardsV2.unstakeEscrow(msg.sender, _amount);
    }

    /**
     * @notice Transfer multiple tokens from one account to another
     *  Sufficient escrowed KWENTA must be unstaked for the transfer to succeed
     * @param from The account to transfer the tokens from
     * @param to The account to transfer the tokens to
     * @param entryIDs a list of the ids of the entries to transfer
     */
    function bulkTransferFrom(
        address from,
        address to,
        uint256[] calldata entryIDs
    ) external override {
        uint256 entryIDsLength = entryIDs.length;
        for (uint256 i = 0; i < entryIDsLength; ) {
            transferFrom(from, to, entryIDs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /* ========== INTERNALS ========== */

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        VestingEntries.VestingEntry memory entry = vestingSchedules[tokenId];

        uint256 unstakedEscrow = unstakedEscrowBalanceOf(from);
        // TODO: think about ways around this - can tokens be staked and transferrable? - could an entry either be staked or unstaked?
        if (unstakedEscrow < entry.escrowAmount) {
            revert InsufficientUnstakedBalance(
                tokenId, entry.escrowAmount, unstakedEscrow
            );
        }

        super._transfer(from, to, tokenId);

        totalEscrowedAccountBalance[from] -= entry.escrowAmount;
        totalEscrowedAccountBalance[to] += entry.escrowAmount;
    }

    // TODO: rethink this function
    // TODO: rethink wording => token vs entry => what is a token in this context, make clear distinction between erc20 (kwenta) and erc721 (KRE)
    /* Transfer vested tokens and update totalEscrowedAccountBalance, totalVestedAccountBalance */
    function _transferVestedTokens(address _account, uint256 _amount)
        internal
    {
        _reduceAccountEscrowBalances(_account, _amount);
        totalVestedAccountBalance[_account] += _amount;
        kwenta.transfer(_account, _amount);
        emit Vested(_account, _amount);
    }

    // TODO: rethink this function - could go in a burn function
    function _reduceAccountEscrowBalances(address _account, uint256 _amount)
        internal
    {
        // Reverts if amount being vested is greater than the account's existing totalEscrowedAccountBalance
        totalEscrowedBalance -= _amount;
        totalEscrowedAccountBalance[_account] -= _amount;
    }

    function _mint(
        address account,
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
        totalEscrowedAccountBalance[account] += quantity;

        uint256 entryID = nextEntryId;
        vestingSchedules[entryID] = VestingEntries.VestingEntry({
            endTime: uint64(endTime),
            escrowAmount: quantity,
            duration: duration,
            earlyVestingFee: earlyVestingFee
        });

        // TODO: think - should safeMint? - could use nonReentrant
        _mint(account, entryID);

        /* Increment the next entry id. */
        ++nextEntryId;

        emit VestingEntryCreated(account, quantity, duration, entryID);
    }

    /* ========== UPGRADEABILITY ========== */

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}
