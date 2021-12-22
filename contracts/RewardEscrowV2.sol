// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

// Inheritance
import "./Owned.sol";
import "./interfaces/IRewardEscrowV2.sol";

// Libraries
import "./SafeDecimalMath.sol";

// Internal references
import "./interfaces/IERC20.sol";
import "./interfaces/IStakingRewards.sol";
import "./interfaces/IKwenta.sol";

contract RewardEscrowV2 is Owned, IRewardEscrowV2 {
    using SafeMath for uint;
    using SafeDecimalMath for uint;

    IKwenta public kwenta;

    IStakingRewards public stakingRewards;

    mapping(address => mapping(uint256 => VestingEntries.VestingEntry)) public vestingSchedules;

    mapping(address => uint256[]) public accountVestingEntryIDs;

    /*Counter for new vesting entry ids. */
    uint256 public nextEntryId;

    /* An account's total escrowed synthetix balance to save recomputing this for fee extraction purposes. */
    mapping(address => uint256) public totalEscrowedAccountBalance;

    /* An account's total vested reward synthetix. */
    mapping(address => uint256) public totalVestedAccountBalance;

    /* The total remaining escrowed balance, for verifying the actual synthetix balance of this contract against. */
    uint256 public totalEscrowedBalance;

    /* Max escrow duration */
    uint public max_duration = 2 * 52 weeks; // Default max 2 years duration

    /* ========== CONSTRUCTOR ========== */

    constructor(address _owner, address _kwenta, address _stakingRewards) Owned(_owner) {
        nextEntryId = 1;
        setKwenta(_kwenta);
        setStakingRewards(_stakingRewards);
    }

    /* ========== SETTERS ========== */

    /**
     * @notice set the Kwenta contract address as we need to transfer KWENTA when the user vests
     */
    function setKwenta(address _kwenta) public onlyOwner {
        kwenta = IKwenta(_kwenta);
        emit KwentaUpdated(address(_kwenta));
    }

    /*
    * @notice Function used to define the StakingRewards to use
    */
    function setStakingRewards(address _stakingRewards) public onlyOwner {
        stakingRewards = IStakingRewards(_stakingRewards);
        emit StakingRewardsUpdated(address(_stakingRewards));
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice A simple alias to totalEscrowedAccountBalance: provides ERC20 balance integration.
     */
    function balanceOf(address account) public view returns (uint) {
        return totalEscrowedAccountBalance[account];
    }

    /**
     * @notice The number of vesting dates in an account's schedule.
     */
    function numVestingEntries(address account) external view returns (uint) {
        return accountVestingEntryIDs[account].length;
    }

    /**
     * @notice Get a particular schedule entry for an account.
     * @return endTime the vesting entry object 
     * @return escrowAmount rate per second emission.
     */
    function getVestingEntry(address account, uint256 entryID) external view returns (uint64 endTime, uint256 escrowAmount) {
        endTime = vestingSchedules[account][entryID].endTime;
        escrowAmount = vestingSchedules[account][entryID].escrowAmount;
    }

    function getVestingSchedules(
        address account,
        uint256 index,
        uint256 pageSize
    ) external view returns (VestingEntries.VestingEntryWithID[] memory) {
        uint256 endIndex = index + pageSize;

        // If index starts after the endIndex return no results
        if (endIndex <= index) {
            return new VestingEntries.VestingEntryWithID[](0);
        }

        // If the page extends past the end of the accountVestingEntryIDs, truncate it.
        if (endIndex > accountVestingEntryIDs[account].length) {
            endIndex = accountVestingEntryIDs[account].length;
        }

        uint256 n = endIndex - index;
        VestingEntries.VestingEntryWithID[] memory vestingEntries = new VestingEntries.VestingEntryWithID[](n);
        for (uint256 i; i < n; i++) {
            uint256 entryID = accountVestingEntryIDs[account][i + index];

            VestingEntries.VestingEntry memory entry = vestingSchedules[account][entryID];

            vestingEntries[i] = VestingEntries.VestingEntryWithID({
                endTime: uint64(entry.endTime),
                escrowAmount: entry.escrowAmount,
                entryID: entryID
            });
        }
        return vestingEntries;
    }

    function getAccountVestingEntryIDs(
        address account,
        uint256 index,
        uint256 pageSize
    ) external view returns (uint256[] memory) {
        uint256 endIndex = index + pageSize;

        // If the page extends past the end of the accountVestingEntryIDs, truncate it.
        if (endIndex > accountVestingEntryIDs[account].length) {
            endIndex = accountVestingEntryIDs[account].length;
        }
        if (endIndex <= index) {
            return new uint256[](0);
        }

        uint256 n = endIndex - index;
        uint256[] memory page = new uint256[](n);
        for (uint256 i; i < n; i++) {
            page[i] = accountVestingEntryIDs[account][i + index];
        }
        return page;
    }

    function getVestingQuantity(address account, uint256[] calldata entryIDs) external view returns (uint total) {
        for (uint i = 0; i < entryIDs.length; i++) {
            VestingEntries.VestingEntry memory entry = vestingSchedules[account][entryIDs[i]];

            /* Skip entry if escrowAmount == 0 */
            if (entry.escrowAmount != 0) {
                uint256 quantity = _claimableAmount(entry);

                /* add quantity to total */
                total = total.add(quantity);
            }
        }
    }

    function getVestingEntryClaimable(address account, uint256 entryID) external view returns (uint) {
        VestingEntries.VestingEntry memory entry = vestingSchedules[account][entryID];
        return _claimableAmount(entry);
    }

    function _claimableAmount(VestingEntries.VestingEntry memory _entry) internal view returns (uint256) {
        uint256 quantity;
        if (_entry.escrowAmount != 0) {
            /* Escrow amounts claimable if block.timestamp equal to or after entry endTime */
            quantity = block.timestamp >= _entry.endTime ? _entry.escrowAmount : 0;
        }
        return quantity;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * Vest escrowed amounts that are claimable
     * Allows users to vest their vesting entries based on msg.sender
     */

    function vest(uint256[] calldata entryIDs) external {
        uint256 total;
        for (uint i = 0; i < entryIDs.length; i++) {
            VestingEntries.VestingEntry storage entry = vestingSchedules[msg.sender][entryIDs[i]];

            /* Skip entry if escrowAmount == 0 already vested */
            if (entry.escrowAmount != 0) {
                uint256 quantity = _claimableAmount(entry);

                /* update entry to remove escrowAmount */
                if (quantity > 0) {
                    entry.escrowAmount = 0;
                }

                /* add quantity to total */
                total = total.add(quantity);
            }
        }

        /* Transfer vested tokens. Will revert if total > totalEscrowedAccountBalance */
        if (total != 0) {
            _transferVestedTokens(msg.sender, total);
        }
    }

    /**
     * @notice Create an escrow entry to lock SNX for a given duration in seconds
     * @dev This call expects that the depositor (msg.sender) has already approved the Reward escrow contract
     to spend the the amount being escrowed.
     */
    function createEscrowEntry(
        address beneficiary,
        uint256 deposit,
        uint256 duration
    ) external {
        require(beneficiary != address(0), "Cannot create escrow with address(0)");

        /* Transfer SNX from msg.sender */
        require(IERC20(kwenta).transferFrom(msg.sender, address(this), deposit), "token transfer failed");

        /* Append vesting entry for the beneficiary address */
        _appendVestingEntry(beneficiary, deposit, duration);
    }

    /**
     * @notice Add a new vesting entry at a given time and quantity to an account's schedule.
     * @dev A call to this should accompany a previous successful call to synthetix.transfer(rewardEscrow, amount),
     * to ensure that when the funds are withdrawn, there is enough balance.
     * @param account The account to append a new vesting entry to.
     * @param quantity The quantity of SNX that will be escrowed.
     * @param duration The duration that SNX will be emitted.
     */
    function appendVestingEntry(
        address account,
        uint256 quantity,
        uint256 duration
    ) external onlyStakingRewards {
        _appendVestingEntry(account, quantity, duration);
    }

    /* Transfer vested tokens and update totalEscrowedAccountBalance, totalVestedAccountBalance */
    function _transferVestedTokens(address _account, uint256 _amount) internal {
        _reduceAccountEscrowBalances(_account, _amount);
        totalVestedAccountBalance[_account] = totalVestedAccountBalance[_account].add(_amount);
        IERC20(address(kwenta)).transfer(_account, _amount);
        emit Vested(_account, block.timestamp, _amount);
    }

    function _reduceAccountEscrowBalances(address _account, uint256 _amount) internal {
        // Reverts if amount being vested is greater than the account's existing totalEscrowedAccountBalance
        totalEscrowedBalance = totalEscrowedBalance.sub(_amount);
        totalEscrowedAccountBalance[_account] = totalEscrowedAccountBalance[_account].sub(_amount);
    }

    /* ========== INTERNALS ========== */

    function _appendVestingEntry(
        address account,
        uint256 quantity,
        uint256 duration
    ) internal {
        /* No empty or already-passed vesting entries allowed. */
        require(quantity != 0, "Quantity cannot be zero");
        require(duration > 0 && duration <= max_duration, "Cannot escrow with 0 duration OR above max_duration");

        /* There must be enough balance in the contract to provide for the vesting entry. */
        totalEscrowedBalance = totalEscrowedBalance.add(quantity);

        require(
            totalEscrowedBalance <= IERC20(address(kwenta)).balanceOf(address(this)),
            "Must be enough balance in the contract to provide for the vesting entry"
        );

        /* Escrow the tokens for duration. */
        uint endTime = block.timestamp + duration;

        /* Add quantity to account's escrowed balance */
        totalEscrowedAccountBalance[account] = totalEscrowedAccountBalance[account].add(quantity);

        uint entryID = nextEntryId;
        vestingSchedules[account][entryID] = VestingEntries.VestingEntry({endTime: uint64(endTime), escrowAmount: quantity});

        accountVestingEntryIDs[account].push(entryID);

        /* Increment the next entry id. */
        nextEntryId = nextEntryId.add(1);

        emit VestingEntryCreated(account, block.timestamp, quantity, duration, entryID);
    }

    /* ========== MODIFIERS ========== */
    modifier onlyStakingRewards() {
        require(msg.sender == address(stakingRewards), "Only the StakingRewards contract can perform this action");
        _;
    }

    /* ========== EVENTS ========== */
    event Vested(address indexed beneficiary, uint time, uint value);
    event VestingEntryCreated(address indexed beneficiary, uint time, uint value, uint duration, uint entryID);
    event KwentaUpdated(address newkwenta);
    event StakingRewardsUpdated(address rewardEscrow);
}
