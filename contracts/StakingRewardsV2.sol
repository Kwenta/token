// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";
import {IStakingRewards} from "./interfaces/IStakingRewards.sol";
import {ISupplySchedule} from "./interfaces/ISupplySchedule.sol";
import {IRewardEscrowV2} from "./interfaces/IRewardEscrowV2.sol";

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
                        CONSTANTS/IMMUTABLES
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

    /*///////////////////////////////////////////////////////////////
                                STATE
    ///////////////////////////////////////////////////////////////*/

    /// @notice number of tokens staked by address
    /// @dev this includes escrowed tokens stake
    mapping(address => Checkpoint[]) public balances;

    /// @notice number of staked escrow tokens by address
    mapping(address => Checkpoint[]) public escrowedBalances;

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
    uint256 public cooldownPeriod;

    /// @notice represents the rewardPerToken
    /// value the last time the stake calculated earned() rewards
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice track rewards for a given user which changes when
    /// a user stakes, unstakes, or claims rewards
    mapping(address => uint256) public rewards;

    /// @notice tracks the last time staked for a given user
    mapping(address => uint256) public userLastStakeTime;

    /// @notice tracks all addresses approved to take actions on behalf of a given account
    mapping(address => mapping(address => bool)) public _operatorApprovals;

    /*///////////////////////////////////////////////////////////////
                                AUTH
    ///////////////////////////////////////////////////////////////*/

    /// @notice access control modifier for rewardEscrow
    modifier onlyRewardEscrow() {
        if (msg.sender != address(rewardEscrow)) revert OnlyRewardEscrow();
        _;
    }

    /// @notice access control modifier for rewardEscrow
    modifier onlySupplySchedule() {
        if (msg.sender != address(supplySchedule)) revert OnlySupplySchedule();
        _;
    }

    /// @notice access control modifier for approved operators
    modifier onlyOperator(address owner) {
        if (!_operatorApprovals[owner][msg.sender]) {
            revert NotApproved();
        }
        _;
    }

    /// @notice only allow execution after the unstaking cooldown period has elapsed
    modifier afterCooldown(address account) {
        uint256 canUnstakeAt = userLastStakeTime[account] + cooldownPeriod;
        if (canUnstakeAt > block.timestamp) {
            revert MustWaitForUnlock(canUnstakeAt);
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

    /// @inheritdoc IStakingRewardsV2
    function initialize(
        address _token,
        address _rewardEscrow,
        address _supplySchedule,
        address _stakingRewardsV1,
        address _owner
    ) external override initializer {
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
        cooldownPeriod = 2 weeks;
    }

    /*///////////////////////////////////////////////////////////////
                                VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function totalSupply() public view override returns (uint256) {
        return _totalSupply.length == 0 ? 0 : _totalSupply[_totalSupply.length - 1].value;
    }

    /// @inheritdoc IStakingRewardsV2
    function v1TotalSupply() public view override returns (uint256) {
        return stakingRewardsV1.totalSupply();
    }

    /// @inheritdoc IStakingRewardsV2
    function balanceOf(address account) public view override returns (uint256) {
        return balances[account].length == 0
            ? 0
            : balances[account][balances[account].length - 1].value;
    }

    /// @inheritdoc IStakingRewardsV2
    function v1BalanceOf(address account) public view override returns (uint256) {
        return stakingRewardsV1.balanceOf(account);
    }

    /// @inheritdoc IStakingRewardsV2
    function escrowedBalanceOf(address account) public view override returns (uint256) {
        return escrowedBalances[account].length == 0
            ? 0
            : escrowedBalances[account][escrowedBalances[account].length - 1].value;
    }

    /// @inheritdoc IStakingRewardsV2
    function nonEscrowedBalanceOf(address account) public view override returns (uint256) {
        return balanceOf(account) - escrowedBalanceOf(account);
    }

    /// @inheritdoc IStakingRewardsV2
    function unstakedEscrowedBalanceOf(address _account) public view override returns (uint256) {
        return rewardEscrow.totalEscrowedBalanceOf(_account) - escrowedBalanceOf(_account);
    }

    /*///////////////////////////////////////////////////////////////
                            STAKE/UNSTAKE
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function stake(uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        updateReward(msg.sender)
    {
        if (amount == 0) revert AmountZero();

        // update state
        userLastStakeTime[msg.sender] = block.timestamp;
        _addTotalSupplyCheckpoint(totalSupply() + amount);
        _addBalancesCheckpoint(msg.sender, balanceOf(msg.sender) + amount);

        // emit staking event and index msg.sender
        emit Staked(msg.sender, amount);

        // transfer token to this contract from the caller
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc IStakingRewardsV2
    function unstake(uint256 amount)
        public
        override
        nonReentrant
        updateReward(msg.sender)
        afterCooldown(msg.sender)
    {
        if (amount == 0) revert AmountZero();
        if (amount > nonEscrowedBalanceOf(msg.sender)) revert InsufficientBalance();

        // update state
        _addTotalSupplyCheckpoint(totalSupply() - amount);
        _addBalancesCheckpoint(msg.sender, balanceOf(msg.sender) - amount);

        // emit unstake event and index msg.sender
        emit Unstaked(msg.sender, amount);

        // transfer token from this contract to the caller
        token.safeTransfer(msg.sender, amount);
    }

    /// @inheritdoc IStakingRewardsV2
    function stakeEscrow(address account, uint256 amount) external override onlyRewardEscrow {
        _stakeEscrow(account, amount);
    }

    function _stakeEscrow(address account, uint256 amount)
        internal
        whenNotPaused
        updateReward(account)
    {
        if (amount == 0) revert AmountZero();
        uint256 unstakedEscrow = unstakedEscrowedBalanceOf(account);
        if (amount > unstakedEscrow) {
            revert InsufficientUnstakedEscrow(unstakedEscrow);
        }

        // update state
        userLastStakeTime[account] = block.timestamp;
        _addBalancesCheckpoint(account, balanceOf(account) + amount);
        _addEscrowedBalancesCheckpoint(account, escrowedBalanceOf(account) + amount);

        // updates total supply despite no new staking token being transfered.
        // escrowed tokens are locked in RewardEscrow
        _addTotalSupplyCheckpoint(totalSupply() + amount);

        // emit escrow staking event and index _account
        emit EscrowStaked(account, amount);
    }

    /// @inheritdoc IStakingRewardsV2
    function stakeEscrowOnBehalf(address account, uint256 amount)
        external
        override
        onlyOperator(account)
    {
        _stakeEscrow(account, amount);
    }

    /// @inheritdoc IStakingRewardsV2
    function unstakeEscrow(address account, uint256 amount)
        external
        override
        afterCooldown(account)
    {
        _unstakeEscrow(account, amount);
    }

    /// @inheritdoc IStakingRewardsV2
    function unstakeEscrowSkipCooldown(address account, uint256 amount) external override {
        _unstakeEscrow(account, amount);
    }

    function _unstakeEscrow(address account, uint256 amount)
        internal
        nonReentrant
        onlyRewardEscrow
        updateReward(account)
    {
        if (amount == 0) revert AmountZero();
        if (amount > escrowedBalanceOf(account)) revert InsufficientBalance();

        // update state
        _addBalancesCheckpoint(account, balanceOf(account) - amount);
        _addEscrowedBalancesCheckpoint(account, escrowedBalanceOf(account) - amount);

        // updates total supply despite no new staking token being transfered.
        // escrowed tokens are locked in RewardEscrow
        _addTotalSupplyCheckpoint(totalSupply() - amount);

        // emit escrow unstaked event and index account
        emit EscrowUnstaked(account, amount);
    }

    /// @inheritdoc IStakingRewardsV2
    // TODO: check for reentrancy via unstake()
    function exit() external override {
        unstake(nonEscrowedBalanceOf(msg.sender));
        getReward();
    }

    /*///////////////////////////////////////////////////////////////
                            CLAIM REWARDS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function getReward() public override {
        _getReward(msg.sender);
    }

    function _getReward(address account) internal nonReentrant updateReward(account) {
        uint256 reward = rewards[account];
        if (reward > 0) {
            // update state (first)
            rewards[account] = 0;

            // transfer token from this contract to the rewardEscrow
            // and create a vesting entry for the caller
            token.safeTransfer(address(rewardEscrow), reward);
            rewardEscrow.appendVestingEntry(account, reward, 52 weeks);

            // emit reward claimed event and index account
            emit RewardPaid(account, reward);
        }
    }

    /// @inheritdoc IStakingRewardsV2
    function getRewardOnBehalf(address account) external override onlyOperator(account) {
        _getReward(account);
    }

    /// @inheritdoc IStakingRewardsV2
    function compound() external override {
        _compound(msg.sender);
    }

    /// @dev internal helper to compound for a given account
    /// @param _account the account to compound for
    function _compound(address _account) internal {
        _getReward(_account);
        _stakeEscrow(_account, unstakedEscrowedBalanceOf(_account));
    }

    // /// @inheritdoc IStakingRewardsV2
    // function compoundOnBehalf(address account) external override onlyOperator(account) {
    //     _getReward(account);
    // }

    /*///////////////////////////////////////////////////////////////
                        REWARD UPDATE CALCULATIONS
    ///////////////////////////////////////////////////////////////*/

    /// @notice update reward state for the account and contract
    /// @param account: address of account which rewards are being updated for
    /// @dev contract state not specific to an account will be updated also
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            // update amount of rewards a user can claim
            rewards[account] = earned(account);

            // update reward per token staked AT this given time
            // (i.e. when this user is interacting with StakingRewards)
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /// @inheritdoc IStakingRewardsV2
    function getRewardForDuration() external view override returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /// @inheritdoc IStakingRewardsV2
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

    /// @inheritdoc IStakingRewardsV2
    function lastTimeRewardApplicable() public view override returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @inheritdoc IStakingRewardsV2
    function earned(address account) public view override returns (uint256) {
        uint256 v1Balance = v1BalanceOf(account);
        uint256 v2Balance = balanceOf(account);
        uint256 totalBalance = v1Balance + v2Balance;

        return ((totalBalance * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18)
            + rewards[account];
    }

    /*///////////////////////////////////////////////////////////////
                            CHECKPOINTING VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function balancesLength(address account) external view override returns (uint256) {
        return balances[account].length;
    }

    /// @inheritdoc IStakingRewardsV2
    function escrowedBalancesLength(address account) external view override returns (uint256) {
        return escrowedBalances[account].length;
    }

    /// @inheritdoc IStakingRewardsV2
    function totalSupplyLength() external view override returns (uint256) {
        return _totalSupply.length;
    }

    /// @inheritdoc IStakingRewardsV2
    function balanceAtTime(address account, uint256 _timestamp)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(balances[account], _timestamp);
    }

    /// @inheritdoc IStakingRewardsV2
    function escrowedbalanceAtTime(address account, uint256 _timestamp)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(escrowedBalances[account], _timestamp);
    }

    /// @inheritdoc IStakingRewardsV2
    function totalSupplyAtTime(uint256 _timestamp) external view override returns (uint256) {
        return _checkpointBinarySearch(_totalSupply, _timestamp);
    }

    /// @notice finds the value of the checkpoint at a given timestamp
    /// @param checkpoints: array of checkpoints to search
    /// @param _timestamp: timestamp to check
    /// @dev returns 0 if no checkpoints exist, uses iterative binary search
    function _checkpointBinarySearch(Checkpoint[] memory checkpoints, uint256 _timestamp)
        internal
        pure
        returns (uint256)
    {
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
    /// @param account: address of account to add checkpoint for
    /// @param value: value of checkpoint to add
    function _addBalancesCheckpoint(address account, uint256 value) internal {
        uint256 lastTimestamp =
            balances[account].length == 0 ? 0 : balances[account][balances[account].length - 1].ts;

        if (lastTimestamp != block.timestamp) {
            balances[account].push(Checkpoint(block.timestamp, value));
        } else {
            balances[account][balances[account].length - 1].value = value;
        }
    }

    /// @notice add a new escrowed balance checkpoint for an account
    /// @param account: address of account to add checkpoint for
    /// @param value: value of checkpoint to add
    function _addEscrowedBalancesCheckpoint(address account, uint256 value) internal {
        uint256 lastTimestamp = escrowedBalances[account].length == 0
            ? 0
            : escrowedBalances[account][escrowedBalances[account].length - 1].ts;

        if (lastTimestamp != block.timestamp) {
            escrowedBalances[account].push(Checkpoint(block.timestamp, value));
        } else {
            escrowedBalances[account][escrowedBalances[account].length - 1].value = value;
        }
    }

    /// @notice add a new total supply checkpoint
    /// @param value: value of checkpoint to add
    function _addTotalSupplyCheckpoint(uint256 value) internal {
        uint256 lastTimestamp =
            _totalSupply.length == 0 ? 0 : _totalSupply[_totalSupply.length - 1].ts;

        if (lastTimestamp != block.timestamp) {
            _totalSupply.push(Checkpoint(block.timestamp, value));
        } else {
            _totalSupply[_totalSupply.length - 1].value = value;
        }
    }

    /*///////////////////////////////////////////////////////////////
                                SETTINGS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function notifyRewardAmount(uint256 reward)
        external
        override
        onlySupplySchedule
        updateReward(address(0))
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

    /// @inheritdoc IStakingRewardsV2
    function setRewardsDuration(uint256 _rewardsDuration) external override onlyOwner {
        if (block.timestamp <= periodFinish) revert RewardsPeriodNotComplete();

        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /// @inheritdoc IStakingRewardsV2
    function setCooldownPeriod(uint256 _cooldownPeriod) external override onlyOwner {
        if (_cooldownPeriod < MIN_COOLDOWN_PERIOD) {
            revert CooldownPeriodTooLow(MIN_COOLDOWN_PERIOD);
        }
        if (_cooldownPeriod > MAX_COOLDOWN_PERIOD) {
            revert CooldownPeriodTooHigh(MAX_COOLDOWN_PERIOD);
        }

        cooldownPeriod = _cooldownPeriod;
        emit CooldownPeriodUpdated(cooldownPeriod);
    }

    /*///////////////////////////////////////////////////////////////
                                PAUSABLE
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function pauseStakingRewards() external override onlyOwner {
        _pause();
    }

    /// @inheritdoc IStakingRewardsV2
    function unpauseStakingRewards() external override onlyOwner {
        _unpause();
    }

    /*///////////////////////////////////////////////////////////////
                            MISCELLANEOUS
    ///////////////////////////////////////////////////////////////*/

    /// @dev this function is used by the proxy to set the access control for upgrading the implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @inheritdoc IStakingRewardsV2
    function approveOperator(address operator, bool approved) external override {
        if (operator == msg.sender) revert CannotApproveSelf();

        _operatorApprovals[msg.sender][operator] = approved;

        emit OperatorApproved(msg.sender, operator, approved);
    }

    /// @inheritdoc IStakingRewardsV2
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external override onlyOwner {
        if (tokenAddress == address(token)) revert CannotRecoverStakingToken();
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
