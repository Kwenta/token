// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// TODO: remove
import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./utils/Owned.sol";
import "./interfaces/IStakingRewardsV2.sol";
import "./interfaces/IStakingRewards.sol";
import "./interfaces/ISupplySchedule.sol";
import "./interfaces/IRewardEscrowV2.sol";
import "./StakingAccount.sol";

/// @title KWENTA Staking Rewards
/// @author SYNTHETIX, JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc), tommyrharper (zeroknowledgeltd@gmail.com)
/// @notice Updated version of Synthetix's StakingRewards with new features specific to Kwenta
contract StakingRewardsV2 is
    Initializable,
    IStakingRewardsV2,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                                CONSTANTS
    ///////////////////////////////////////////////////////////////*/

    /// @notice minimum time length of the unstaking cooldown period
    uint256 public constant MIN_COOLDOWN_PERIOD = 1 weeks;

    /// @notice maximum time length of the unstaking cooldown period
    uint256 public constant MAX_COOLDOWN_PERIOD = 52 weeks;

    /// @notice token used for BOTH staking and rewards
    IERC20 public token;

    /// @notice escrow contract which holds (and may stake) reward tokens
    IRewardEscrowV2 public rewardEscrow;

    /// @notice handles reward token minting logic
    ISupplySchedule public supplySchedule;

    /// @notice previous version of staking rewards contract - used for migration
    IStakingRewards public stakingRewardsV1;

    /// @notice staking account contract which abstracts users "accounts" for staking
    // TODO: update to IStakingAccount
    StakingAccount public stakingAccount;

    /*///////////////////////////////////////////////////////////////
                                STATE
    ///////////////////////////////////////////////////////////////*/

    /// @notice number of tokens staked by an account
    /// @dev this includes escrowed tokens stake
    /// accountId => balance checkpoint
    mapping(uint256 => Checkpoint[]) public balances;

    /// @notice number of staked escrow tokens by address
    /// accountId => escrowed balance checkpoint
    mapping(uint256 => Checkpoint[]) public escrowedBalances;

    /// @notice total number of tokens staked in this contract
    Checkpoint[] public _totalSupply;

    /// @notice marks applicable reward period finish time
    uint256 public periodFinish;

    /// @notice amount of tokens minted per second
    uint256 public rewardRate;

    /// @notice period for rewards
    uint256 public rewardsDuration;

    /// @notice track last time the rewards were updated
    uint256 public lastUpdateTime;

    /// @notice summation of rewardRate divided by total staked tokens
    uint256 public rewardPerTokenStored;

    /// @notice the period of time a user has to wait after staking to unstake
    uint256 public unstakingCooldownPeriod;

    /// @notice represents the rewardPerToken
    /// value the last time the stake calculated earned() rewards
    /// accountId => rewardPerTokenPaid
    mapping(uint256 => uint256) public userRewardPerTokenPaid;

    /// @notice track rewards for a given user which changes when
    /// a user stakes, unstakes, or claims rewards
    /// accountId => rewards
    mapping(uint256 => uint256) public rewards;

    /// @notice tracks the last time staked for a given user
    /// accountId => lastStakeTime
    mapping(uint256 => uint256) public userLastStakeTime;

    /// @notice tracks all addresses approved to take actions on behalf of a given account
    /// accountId => operator => approved
    mapping(uint256 => mapping(address => bool)) public _operatorApprovals;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    ///////////////////////////////////////////////////////////////*/

    /// @notice update reward rate
    /// @param reward: amount to be distributed over applicable rewards duration
    event RewardAdded(uint256 reward);

    /// @notice emitted when user stakes tokens
    /// @param accountId: staker accountId
    /// @param amount: amount staked
    event Staked(uint256 indexed accountId, uint256 amount);

    /// @notice emitted when user unstakes tokens
    /// @param accountId: accountId of user unstaking
    /// @param amount: amount unstaked
    event Unstaked(uint256 indexed accountId, uint256 amount);

    /// @notice emitted when escrow staked
    /// @param accountId: owner of escrowed tokens accountId
    /// @param amount: amount staked
    event EscrowStaked(uint256 indexed accountId, uint256 amount);

    /// @notice emitted when staked escrow tokens are unstaked
    /// @param accountId: owner of escrowed tokens accountId
    /// @param amount: amount unstaked
    event EscrowUnstaked(uint256 accountId, uint256 amount);

    /// @notice emitted when user claims rewards
    /// @param accountId: accountId of user claiming rewards
    /// @param reward: amount of reward token claimed
    event RewardPaid(uint256 indexed accountId, uint256 reward);

    /// @notice emitted when rewards duration changes
    /// @param newDuration: denoted in seconds
    event RewardsDurationUpdated(uint256 newDuration);

    /// @notice emitted when tokens are recovered from this contract
    /// @param token: address of token recovered
    /// @param amount: amount of token recovered
    event Recovered(address token, uint256 amount);

    /// @notice emitted when the unstaking cooldown period is updated
    /// @param unstakingCooldownPeriod: the new unstaking cooldown period
    event UnstakingCooldownPeriodUpdated(uint256 unstakingCooldownPeriod);

    /// @notice emitted when an operator is approved
    /// @param owner: owner of tokens
    /// @param operator: address of operator
    /// @param approved: whether or not operator is approved
    event OperatorApproved(uint256 owner, address operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice error when user tries unstake during the cooldown period
    /// @param canUnstakeAt timestamp when user can unstake
    error CannotUnstakeDuringCooldown(uint256 canUnstakeAt);

    /// @notice error when trying to set a cooldown period below the minimum
    /// @param MIN_COOLDOWN_PERIOD minimum cooldown period
    error CooldownPeriodTooLow(uint256 MIN_COOLDOWN_PERIOD);

    /// @notice error when trying to set a cooldown period above the maximum
    /// @param MAX_COOLDOWN_PERIOD maximum cooldown period
    error CooldownPeriodTooHigh(uint256 MAX_COOLDOWN_PERIOD);

    /// @notice error when trying to stakeEscrow more than the unstakedEscrow available
    /// @param unstakedEscrow amount of unstaked escrow
    error InsufficientUnstakedEscrow(uint256 unstakedEscrow);

    /// @notice the caller is not approved to take this action
    error NotApprovedOperator();

    /*///////////////////////////////////////////////////////////////
                                AUTH
    ///////////////////////////////////////////////////////////////*/

    /// @notice access control modifier for rewardEscrow
    modifier onlyRewardEscrow() {
        require(
            msg.sender == address(rewardEscrow),
            "StakingRewards: Only Reward Escrow"
        );
        _;
    }

    /// @notice access control modifier for rewardEscrow
    modifier onlySupplySchedule() {
        require(
            msg.sender == address(supplySchedule),
            "StakingRewards: Only Supply Schedule"
        );
        _;
    }

    /// @notice access control modifier for approved operators
    modifier onlyApprovedOperator(uint256 owner) {
        if (!_operatorApprovals[owner][msg.sender]) {
            revert NotApprovedOperator();
        }
        _;
    }

    /// @notice only allow execution after the unstaking cooldown period has elapsed
    modifier afterCooldown(uint256 accountId) {
        uint256 canUnstakeAt =
            userLastStakeTime[accountId] + unstakingCooldownPeriod;
        if (canUnstakeAt > block.timestamp) {
            revert CannotUnstakeDuringCooldown(canUnstakeAt);
        }
        _;
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

    /// @notice configure StakingRewards state
    /// @dev owner set to address that deployed StakingRewards
    /// @param _token: token used for staking and for rewards
    /// @param _rewardEscrow: escrow contract which holds (and may stake) reward tokens
    /// @param _supplySchedule: handles reward token minting logic
    /// @dev this function should be called via proxy, not via direct contract interaction
    function initialize(
        address _token,
        address _rewardEscrow,
        address _supplySchedule,
        address _stakingRewardsV1,
        address _owner
    ) public initializer {
        // initialize owner
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // transfer ownership
        transferOwnership(_owner);

        // define reward/staking token
        token = IERC20(_token);

        // define contracts which will interact with StakingRewards
        rewardEscrow = IRewardEscrowV2(_rewardEscrow);
        supplySchedule = ISupplySchedule(_supplySchedule);
        stakingRewardsV1 = IStakingRewards(_stakingRewardsV1);

        // define values
        rewardsDuration = 1 weeks;
        unstakingCooldownPeriod = 2 weeks;
    }

    /*///////////////////////////////////////////////////////////////
                                VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @dev returns staked tokens which will likely not be equal to total tokens
    /// in the contract since reward and staking tokens are the same
    /// @return total amount of tokens that are being staked
    function totalSupply() public view override returns (uint256) {
        return _totalSupply.length == 0
            ? 0
            : _totalSupply[_totalSupply.length - 1].value;
    }

    /// @notice Returns the total number of staked tokens for a user
    /// the sum of all escrowed and non-escrowed tokens
    /// @param accountId: accountId of potential staker
    /// @return amount of tokens staked by account
    function balanceOf(uint256 accountId)
        public
        view
        override
        returns (uint256)
    {
        return balances[accountId].length == 0
            ? 0
            : balances[accountId][balances[accountId].length - 1].value;
    }

    /// @notice Getter function for number of staked escrow tokens
    /// @param accountId account to check the escrowed tokens staked
    /// @return amount of escrowed tokens staked
    function escrowedBalanceOf(uint256 accountId)
        public
        view
        override
        returns (uint256)
    {
        return escrowedBalances[accountId].length == 0
            ? 0
            : escrowedBalances[accountId][escrowedBalances[accountId].length - 1].value;
    }

    /// @notice Getter function for the total number of v1 staked tokens
    /// @return amount of tokens staked in v1
    function v1TotalSupply() public view override returns (uint256) {
        return stakingRewardsV1.totalSupply();
    }

    /// @notice Getter function for the number of v1 staked tokens
    /// @param accountId account to check the tokens staked
    /// @return amount of tokens staked
    function v1BalanceOf(uint256 accountId)
        public
        view
        override
        returns (uint256)
    {
        // TODO: think - is this legit???
        return stakingRewardsV1.balanceOf(stakingAccount.ownerOf(accountId));
    }

    /// @return rewards for the duration specified by rewardsDuration
    function getRewardForDuration() external view override returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /// @notice Getter function for number of staked non-escrow tokens
    /// @param accountId account to check the non-escrowed tokens staked
    /// @return amount of non-escrowed tokens staked
    function nonEscrowedBalanceOf(uint256 accountId)
        public
        view
        override
        returns (uint256)
    {
        return balanceOf(accountId) - escrowedBalanceOf(accountId);
    }

    /*///////////////////////////////////////////////////////////////
                            STAKE/UNSTAKE
    ///////////////////////////////////////////////////////////////*/

    /// @notice stake token
    /// @param accountId: account to stake tokens for
    /// @param amount: amount to stake
    /// @dev updateReward() called prior to function logic
    function stake(uint256 accountId, uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        updateReward(accountId)
    {
        require(amount > 0, "StakingRewards: Cannot stake 0");

        // update state
        userLastStakeTime[accountId] = block.timestamp;
        _addTotalSupplyCheckpoint(totalSupply() + amount);
        _addBalancesCheckpoint(accountId, balanceOf(accountId) + amount);

        // transfer token to this contract from the caller
        // TODO: think if this is legit
        token.safeTransferFrom(stakingAccount.ownerOf(accountId), address(this), amount);

        // emit staking event and index accountId
        emit Staked(accountId, amount);
    }

    /// @notice unstake token
    /// @param amount: amount to unstake
    /// @dev updateReward() called prior to function logic
    function unstake(uint256 accountId, uint256 amount)
        public
        override
        nonReentrant
        updateReward(accountId)
        afterCooldown(accountId)
    {
        require(amount > 0, "StakingRewards: Cannot Unstake 0");
        require(
            amount <= nonEscrowedBalanceOf(accountId),
            "StakingRewards: Invalid Amount"
        );

        // update state
        _addTotalSupplyCheckpoint(totalSupply() - amount);
        _addBalancesCheckpoint(accountId, balanceOf(accountId) - amount);

        // transfer token from this contract to the caller
        token.safeTransfer(stakingAccount.ownerOf(accountId), amount);

        // emit unstake event and index accountId
        emit Unstaked(accountId, amount);
    }

    /// @notice stake escrowed token
    /// @param accountId: account which owns token
    /// @param amount: amount to stake
    /// @dev updateReward() called prior to function logic
    function stakeEscrow(uint256 accountId, uint256 amount)
        external
        override
        onlyRewardEscrow
    {
        _stakeEscrow(accountId, amount);
    }

    function _stakeEscrow(uint256 accountId, uint256 amount)
        internal
        whenNotPaused
        updateReward(accountId)
    {
        require(amount > 0, "StakingRewards: Cannot stake 0");
        // TODO: think if there I could do calc just querying rewardEscrow.totalEscrowedAccountBalance to save gas
        uint256 unstakedEscrow = rewardEscrow.unstakedEscrowBalanceOf(accountId);
        if (amount > unstakedEscrow) {
            revert InsufficientUnstakedEscrow(unstakedEscrow);
        }

        // update state
        userLastStakeTime[accountId] = block.timestamp;
        _addBalancesCheckpoint(accountId, balanceOf(accountId) + amount);
        _addEscrowedBalancesCheckpoint(
            accountId, escrowedBalanceOf(accountId) + amount
        );

        // updates total supply despite no new staking token being transfered.
        // escrowed tokens are locked in RewardEscrow
        _addTotalSupplyCheckpoint(totalSupply() + amount);

        // emit escrow staking event and index accountId
        emit EscrowStaked(accountId, amount);
    }

    /// @notice stake escrowed token on behalf of another account
    /// @param accountId: account which owns token
    /// @param amount: amount to stake
    function stakeEscrowOnBehalf(uint256 accountId, uint256 amount)
        external
        override
        onlyApprovedOperator(accountId)
    {
        _stakeEscrow(accountId, amount);
    }

    /// @notice unstake escrowed token
    /// @param accountId: account which owns token
    /// @param amount: amount to unstake
    /// @dev updateReward() called prior to function logic
    /// @dev msg.sender NOT used (account is used)
    function unstakeEscrow(uint256 accountId, uint256 amount)
        external
        override
        nonReentrant
        onlyRewardEscrow
        updateReward(accountId)
        afterCooldown(accountId)
    {
        require(amount > 0, "StakingRewards: Cannot Unstake 0");
        require(
            escrowedBalanceOf(accountId) >= amount,
            "StakingRewards: Invalid Amount"
        );

        // update state
        _addBalancesCheckpoint(accountId, balanceOf(accountId) - amount);
        _addEscrowedBalancesCheckpoint(
            accountId, escrowedBalanceOf(accountId) - amount
        );

        // updates total supply despite no new staking token being transfered.
        // escrowed tokens are locked in RewardEscrow
        _addTotalSupplyCheckpoint(totalSupply() - amount);

        // emit escrow unstaked event and index accountId
        emit EscrowUnstaked(accountId, amount);
    }

    /// @notice unstake all available staked non-escrowed tokens and
    /// claim any rewards
    /// @param accountId: account to exit staking for
    // TODO: check for reentrancy via unstake()
    function exit(uint256 accountId) external override {
        unstake(accountId, nonEscrowedBalanceOf(accountId));
        getReward(accountId);
    }

    /*///////////////////////////////////////////////////////////////
                            CLAIM REWARDS
    ///////////////////////////////////////////////////////////////*/

    /// @notice caller claims any rewards generated from staking
    /// @param accountId: account to claim rewards for
    /// @dev rewards are escrowed in RewardEscrow
    /// @dev updateReward() called prior to function logic
    function getReward(uint256 accountId) public override {
        _getReward(accountId);
    }

    function _getReward(uint256 accountId)
        internal
        nonReentrant
        updateReward(accountId)
    {
        uint256 reward = rewards[accountId];
        if (reward > 0) {
            // update state (first)
            rewards[accountId] = 0;

            // transfer token from this contract to the rewardEscrow
            // and create a vesting entry for the caller
            token.safeTransfer(address(rewardEscrow), reward);
            rewardEscrow.appendVestingEntry(accountId, reward, 52 weeks);

            // emit reward claimed event and index accountId
            emit RewardPaid(accountId, reward);
        }
    }

    /// @notice caller claims any rewards generated from staking on behalf of another account
    /// The rewards will be escrowed in RewardEscrow with the account as the beneficiary
    /// @param accountId: account which owns token
    function getRewardOnBehalf(uint256 accountId)
        external
        override
        onlyApprovedOperator(accountId)
    {
        _getReward(accountId);
    }

    /*///////////////////////////////////////////////////////////////
                        REWARD UPDATE CALCULATIONS
    ///////////////////////////////////////////////////////////////*/

    /// @notice update reward state for the account and contract
    /// @param accountId: accountId of account which rewards are being updated for
    /// @dev contract state not specific to an account will be updated also
    modifier updateReward(uint256 accountId) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (accountId != 0) {
            // update amount of rewards a user can claim
            rewards[accountId] = earned(accountId);

            // update reward per token staked AT this given time
            // (i.e. when this user is interacting with StakingRewards)
            userRewardPerTokenPaid[accountId] = rewardPerTokenStored;
        }
        _;
    }

    /// @notice calculate running sum of reward per total tokens staked
    /// at this specific time
    /// @return running sum of reward per total tokens staked
    function rewardPerToken() public view override returns (uint256) {
        uint256 sumOfAllStakedTokens = totalSupply() + v1TotalSupply();

        if (sumOfAllStakedTokens == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored
            + (
                ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18)
                    / (sumOfAllStakedTokens)
            );
    }

    /// @return timestamp of the last time rewards are applicable
    function lastTimeRewardApplicable()
        public
        view
        override
        returns (uint256)
    {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice determine how much reward token an account has earned thus far
    /// @param accountId: accountId of account earned amount is being calculated for
    function earned(uint256 accountId) public view override returns (uint256) {
        uint256 v1Balance = v1BalanceOf(accountId);
        uint256 v2Balance = balanceOf(accountId);
        uint256 totalBalance = v1Balance + v2Balance;

        return (
            (
                totalBalance
                    * (rewardPerToken() - userRewardPerTokenPaid[accountId])
            ) / 1e18
        ) + rewards[accountId];
    }

    /*///////////////////////////////////////////////////////////////
                            CHECKPOINTING VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @notice get the number of balances checkpoints for an account
    /// @param accountId: accountId of account to check
    /// @return number of balances checkpoints
    function balancesLength(uint256 accountId)
        external
        view
        override
        returns (uint256)
    {
        return balances[accountId].length;
    }

    /// @notice get the number of escrowed balance checkpoints for an account
    /// @param accountId: accountId of account to check
    /// @return number of escrowed balance checkpoints
    function escrowedBalancesLength(uint256 accountId)
        external
        view
        override
        returns (uint256)
    {
        return escrowedBalances[accountId].length;
    }

    /// @notice get the number of total supply checkpoints
    /// @return number of total supply checkpoints
    function totalSupplyLength() external view override returns (uint256) {
        return _totalSupply.length;
    }

    /// @notice get a users balance at a given timestamp
    /// @param accountId: accountId of account to check
    /// @param _timestamp: timestamp to check
    /// @return balance at given timestamp
    function balanceAtTime(uint256 accountId, uint256 _timestamp)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(balances[accountId], _timestamp);
    }

    /// @notice get a users escrowed balance at a given timestamp
    /// @param accountId: accountId of account to check
    /// @param _timestamp: timestamp to check
    /// @return escrowed balance at given timestamp
    function escrowedbalanceAtTime(uint256 accountId, uint256 _timestamp)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(escrowedBalances[accountId], _timestamp);
    }

    /// @notice get the total supply at a given timestamp
    /// @param _timestamp: timestamp to check
    /// @return total supply at given timestamp
    function totalSupplyAtTime(uint256 _timestamp)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(_totalSupply, _timestamp);
    }

    /// @notice finds the value of the checkpoint at a given timestamp
    /// @param checkpoints: array of checkpoints to search
    /// @param _timestamp: timestamp to check
    /// @dev returns 0 if no checkpoints exist, uses iterative binary search
    function _checkpointBinarySearch(
        Checkpoint[] memory checkpoints,
        uint256 _timestamp
    ) internal pure returns (uint256) {
        uint256 length = checkpoints.length;
        if (length == 0) return 0;

        uint256 min = 0;
        uint256 max = length - 1;

        if (checkpoints[min].ts > _timestamp) return 0;
        if (checkpoints[max].ts <= _timestamp) return checkpoints[max].value;

        while (max > min) {
            uint256 midpoint = (max + min + 1) / 2;
            if (checkpoints[midpoint].ts <= _timestamp) min = midpoint;
            else max = midpoint - 1;
        }

        assert(min == max);

        return checkpoints[min].value;
    }

    /*///////////////////////////////////////////////////////////////
                            UPDATE CHECKPOINTS
    ///////////////////////////////////////////////////////////////*/

    /// @notice add a new balance checkpoint for an account
    /// @param accountId: accountId of account to add checkpoint for
    /// @param value: value of checkpoint to add
    function _addBalancesCheckpoint(uint256 accountId, uint256 value) internal {
        uint256 lastTimestamp = balances[accountId].length == 0
            ? 0
            : balances[accountId][balances[accountId].length - 1].ts;

        if (lastTimestamp != block.timestamp) {
            balances[accountId].push(Checkpoint(block.timestamp, value));
        } else {
            balances[accountId][balances[accountId].length - 1].value = value;
        }
    }

    /// @notice add a new escrowed balance checkpoint for an account
    /// @param accountId: accountId of account to add checkpoint for
    /// @param value: value of checkpoint to add
    function _addEscrowedBalancesCheckpoint(uint256 accountId, uint256 value)
        internal
    {
        uint256 lastTimestamp = escrowedBalances[accountId].length == 0
            ? 0
            : escrowedBalances[accountId][escrowedBalances[accountId].length - 1].ts;

        if (lastTimestamp != block.timestamp) {
            escrowedBalances[accountId].push(Checkpoint(block.timestamp, value));
        } else {
            escrowedBalances[accountId][escrowedBalances[accountId].length - 1]
                .value = value;
        }
    }

    /// @notice add a new total supply checkpoint
    /// @param value: value of checkpoint to add
    function _addTotalSupplyCheckpoint(uint256 value) internal {
        uint256 lastTimestamp = _totalSupply.length == 0
            ? 0
            : _totalSupply[_totalSupply.length - 1].ts;

        if (lastTimestamp != block.timestamp) {
            _totalSupply.push(Checkpoint(block.timestamp, value));
        } else {
            _totalSupply[_totalSupply.length - 1].value = value;
        }
    }

    /*///////////////////////////////////////////////////////////////
                                SETTINGS
    ///////////////////////////////////////////////////////////////*/

    /// @notice configure reward rate
    /// @param reward: amount of token to be distributed over a period
    /// @dev updateReward() called prior to function logic (with zero address)
    function notifyRewardAmount(uint256 reward)
        external
        override
        onlySupplySchedule
        updateReward(0)
    {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    /// @notice set rewards duration
    /// @param _rewardsDuration: denoted in seconds
    function setRewardsDuration(uint256 _rewardsDuration)
        external
        override
        onlyOwner
    {
        require(
            block.timestamp > periodFinish,
            "StakingRewards: Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /// @notice set unstaking cooldown period
    /// @param _unstakingCooldownPeriod: denoted in seconds
    function setUnstakingCooldownPeriod(uint256 _unstakingCooldownPeriod)
        external
        override
        onlyOwner
    {
        if (_unstakingCooldownPeriod < MIN_COOLDOWN_PERIOD) {
            revert CooldownPeriodTooLow(MIN_COOLDOWN_PERIOD);
        }
        if (_unstakingCooldownPeriod > MAX_COOLDOWN_PERIOD) {
            revert CooldownPeriodTooHigh(MAX_COOLDOWN_PERIOD);
        }

        unstakingCooldownPeriod = _unstakingCooldownPeriod;
        emit UnstakingCooldownPeriodUpdated(unstakingCooldownPeriod);
    }

    /// @notice set StakingAccount address
    /// @dev only owner may change address
    function setStakingAccount(address _stakingAccount) external onlyOwner {
        require(_stakingAccount != address(0), "RewardEscrow: Zero Address");
        stakingAccount = StakingAccount(_stakingAccount);
        // TODO: emit event
    }

    /*///////////////////////////////////////////////////////////////
                                PAUSABLE
    ///////////////////////////////////////////////////////////////*/

    /// @dev Triggers stopped state
    function pauseStakingRewards() external override onlyOwner {
        _pause();
    }

    /// @dev Returns to normal state.
    function unpauseStakingRewards() external override onlyOwner {
        _unpause();
    }

    /*///////////////////////////////////////////////////////////////
                            MISCELLANEOUS
    ///////////////////////////////////////////////////////////////*/

    /// @dev this function is used by the proxy to set the access control for upgrading the implementation contract
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /// @notice approve an operator to collect rewards and stake escrow on behalf of the sender
    /// @param accountId: accountId of account to approve operator for
    /// @param operator: address of operator to approve
    /// @param approved: whether or not to approve the operator
    function approveOperator(uint256 accountId, address operator, bool approved)
        external
        override
    {
        _operatorApprovals[accountId][operator] = approved;

        emit OperatorApproved(accountId, operator, approved);
    }

    /// @notice added to support recovering LP Rewards from other systems
    /// such as BAL to be distributed to holders
    /// @param tokenAddress: address of token to be recovered
    /// @param tokenAmount: amount of token to be recovered
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        override
        onlyOwner
    {
        require(
            tokenAddress != address(token),
            "StakingRewards: Cannot unstake the staking token"
        );
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
