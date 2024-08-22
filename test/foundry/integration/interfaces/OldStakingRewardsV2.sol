// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Ownable2StepUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IKwenta} from "../../../../contracts/interfaces/IKwenta.sol";
import {IOldStakingRewardsV2} from "./IOldStakingRewardsV2.sol";
import {IOldStakingRewardsNotifier} from "./IOldStakingRewardsNotifier.sol";
import {IRewardEscrowV2} from "../../../../contracts/interfaces/IRewardEscrowV2.sol";

/// @title KWENTA Staking Rewards V2
/// @author Originally inspired by SYNTHETIX StakingRewards
/// @author Kwenta's StakingRewards V1 by JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @author StakingRewardsV2 (this) by tommyrharper (tom@zkconsulting.xyz)
/// @notice Updated version of Synthetix's StakingRewards with new features specific to Kwenta
contract OldStakingRewardsV2 is
    IOldStakingRewardsV2,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /*///////////////////////////////////////////////////////////////
                        CONSTANTS/IMMUTABLES
    ///////////////////////////////////////////////////////////////*/

    /// @notice minimum time length of the unstaking cooldown period
    uint256 public constant MIN_COOLDOWN_PERIOD = 1 weeks;

    /// @notice maximum time length of the unstaking cooldown period
    uint256 public constant MAX_COOLDOWN_PERIOD = 52 weeks;

    /// @notice Contract for KWENTA ERC20 token - used for BOTH staking and rewards
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IKwenta public immutable kwenta;

    /// @notice escrow contract which holds (and may stake) reward tokens
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IRewardEscrowV2 public immutable rewardEscrow;

    /// @notice handles reward token minting logic
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IOldStakingRewardsNotifier public immutable rewardsNotifier;

    /*///////////////////////////////////////////////////////////////
                                STATE
    ///////////////////////////////////////////////////////////////*/

    /// @notice list of checkpoints with the number of tokens staked by address
    /// @dev this includes staked escrowed tokens
    mapping(address => Checkpoint[]) public balancesCheckpoints;

    /// @notice list of checkpoints with the number of staked escrow tokens by address
    mapping(address => Checkpoint[]) public escrowedBalancesCheckpoints;

    /// @notice list of checkpoints with the total number of tokens staked in this contract
    Checkpoint[] public totalSupplyCheckpoints;

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

    /// @inheritdoc IOldStakingRewardsV2
    uint256 public cooldownPeriod;

    /// @notice represents the rewardPerToken
    /// value the last time the staker calculated earned() rewards
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice track rewards for a given user which changes when
    /// a user stakes, unstakes, or claims rewards
    mapping(address => uint256) public rewards;

    /// @notice tracks the last time staked for a given user
    mapping(address => uint256) public userLastStakeTime;

    /// @notice tracks all addresses approved to take actions on behalf of a given account
    mapping(address => mapping(address => bool)) public operatorApprovals;

    /*///////////////////////////////////////////////////////////////
                                AUTH
    ///////////////////////////////////////////////////////////////*/

    /// @notice access control modifier for rewardEscrow
    modifier onlyRewardEscrow() {
        _onlyRewardEscrow();
        _;
    }

    function _onlyRewardEscrow() internal view {
        if (msg.sender != address(rewardEscrow)) revert OnlyRewardEscrow();
    }

    /// @notice access control modifier for rewardsNotifier
    modifier onlyRewardsNotifier() {
        _onlyRewardsNotifier();
        _;
    }

    function _onlyRewardsNotifier() internal view {
        if (msg.sender != address(rewardsNotifier)) revert OnlyRewardsNotifier();
    }

    /// @notice only allow execution after the unstaking cooldown period has elapsed
    modifier afterCooldown(address _account) {
        _afterCooldown(_account);
        _;
    }

    function _afterCooldown(address _account) internal view {
        uint256 canUnstakeAt = userLastStakeTime[_account] + cooldownPeriod;
        if (canUnstakeAt > block.timestamp) revert MustWaitForUnlock(canUnstakeAt);
    }

    /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @dev disable default constructor to disable the implementation contract
    /// Actual contract construction will take place in the initialize function via proxy
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param _kwenta The address for the KWENTA ERC20 token
    /// @param _rewardEscrow The address for the RewardEscrowV2 contract
    /// @param _rewardsNotifier The address for the StakingRewardsNotifier contract
    constructor(address _kwenta, address _rewardEscrow, address _rewardsNotifier) {
        if (_kwenta == address(0) || _rewardEscrow == address(0) || _rewardsNotifier == address(0))
        {
            revert ZeroAddress();
        }

        _disableInitializers();

        // define reward/staking token
        kwenta = IKwenta(_kwenta);

        // define contracts which will interact with StakingRewards
        rewardEscrow = IRewardEscrowV2(_rewardEscrow);
        rewardsNotifier = IOldStakingRewardsNotifier(_rewardsNotifier);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function initialize(address _contractOwner) external initializer {
        if (_contractOwner == address(0)) revert ZeroAddress();

        // initialize owner
        __Ownable2Step_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // transfer ownership
        _transferOwnership(_contractOwner);

        // define values
        rewardsDuration = 1 weeks;
        cooldownPeriod = 2 weeks;
    }

    /*///////////////////////////////////////////////////////////////
                                VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOldStakingRewardsV2
    function totalSupply() public view returns (uint256) {
        uint256 length = totalSupplyCheckpoints.length;
        unchecked {
            return length == 0 ? 0 : totalSupplyCheckpoints[length - 1].value;
        }
    }

    /// @inheritdoc IOldStakingRewardsV2
    function balanceOf(address _account) public view returns (uint256) {
        Checkpoint[] storage checkpoints = balancesCheckpoints[_account];
        uint256 length = checkpoints.length;
        unchecked {
            return length == 0 ? 0 : checkpoints[length - 1].value;
        }
    }

    /// @inheritdoc IOldStakingRewardsV2
    function escrowedBalanceOf(address _account) public view returns (uint256) {
        Checkpoint[] storage checkpoints = escrowedBalancesCheckpoints[_account];
        uint256 length = checkpoints.length;
        unchecked {
            return length == 0 ? 0 : checkpoints[length - 1].value;
        }
    }

    /// @inheritdoc IOldStakingRewardsV2
    function nonEscrowedBalanceOf(address _account) public view returns (uint256) {
        return balanceOf(_account) - escrowedBalanceOf(_account);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function unstakedEscrowedBalanceOf(address _account) public view returns (uint256) {
        return rewardEscrow.escrowedBalanceOf(_account) - escrowedBalanceOf(_account);
    }

    /*///////////////////////////////////////////////////////////////
                            STAKE/UNSTAKE
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOldStakingRewardsV2
    function stake(uint256 _amount) external whenNotPaused updateReward(msg.sender) {
        if (_amount == 0) revert AmountZero();

        // update state
        userLastStakeTime[msg.sender] = block.timestamp;
        _addTotalSupplyCheckpoint(totalSupply() + _amount);
        _addBalancesCheckpoint(msg.sender, balanceOf(msg.sender) + _amount);

        // emit staking event and index msg.sender
        emit Staked(msg.sender, _amount);

        // transfer token to this contract from the caller
        kwenta.transferFrom(msg.sender, address(this), _amount);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function unstake(uint256 _amount)
        public
        whenNotPaused
        updateReward(msg.sender)
        afterCooldown(msg.sender)
    {
        if (_amount == 0) revert AmountZero();
        uint256 nonEscrowedBalance = nonEscrowedBalanceOf(msg.sender);
        if (_amount > nonEscrowedBalance) revert InsufficientBalance(nonEscrowedBalance);

        // update state
        _addTotalSupplyCheckpoint(totalSupply() - _amount);
        _addBalancesCheckpoint(msg.sender, balanceOf(msg.sender) - _amount);

        // emit unstake event and index msg.sender
        emit Unstaked(msg.sender, _amount);

        // transfer token from this contract to the caller
        kwenta.transfer(msg.sender, _amount);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function stakeEscrow(uint256 _amount) external {
        _stakeEscrow(msg.sender, _amount);
    }

    function _stakeEscrow(address _account, uint256 _amount)
        internal
        whenNotPaused
        updateReward(_account)
    {
        if (_amount == 0) revert AmountZero();
        uint256 unstakedEscrow = unstakedEscrowedBalanceOf(_account);
        if (_amount > unstakedEscrow) revert InsufficientUnstakedEscrow(unstakedEscrow);

        // update state
        userLastStakeTime[_account] = block.timestamp;
        _addBalancesCheckpoint(_account, balanceOf(_account) + _amount);
        _addEscrowedBalancesCheckpoint(_account, escrowedBalanceOf(_account) + _amount);

        // updates total supply despite no new staking token being transfered.
        // escrowed tokens are locked in RewardEscrow
        _addTotalSupplyCheckpoint(totalSupply() + _amount);

        // emit escrow staking event and index account
        emit EscrowStaked(_account, _amount);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function unstakeEscrow(uint256 _amount) external afterCooldown(msg.sender) {
        _unstakeEscrow(msg.sender, _amount);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function unstakeEscrowSkipCooldown(address _account, uint256 _amount)
        external
        onlyRewardEscrow
    {
        _unstakeEscrow(_account, _amount);
    }

    function _unstakeEscrow(address _account, uint256 _amount)
        internal
        whenNotPaused
        updateReward(_account)
    {
        if (_amount == 0) revert AmountZero();
        uint256 escrowedBalance = escrowedBalanceOf(_account);
        if (_amount > escrowedBalance) revert InsufficientBalance(escrowedBalance);

        // update state
        _addBalancesCheckpoint(_account, balanceOf(_account) - _amount);
        _addEscrowedBalancesCheckpoint(_account, escrowedBalanceOf(_account) - _amount);

        // updates total supply despite no new staking token being transfered.
        // escrowed tokens are locked in RewardEscrow
        _addTotalSupplyCheckpoint(totalSupply() - _amount);

        // emit escrow unstaked event and index account
        emit EscrowUnstaked(_account, _amount);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function exit() external {
        unstake(nonEscrowedBalanceOf(msg.sender));
        _getReward(msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                            CLAIM REWARDS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOldStakingRewardsV2
    function getReward() external {
        _getReward(msg.sender);
    }

    function _getReward(address _account) internal {
        _getReward(_account, _account);
    }

    function _getReward(address _account, address _to)
        internal
        whenNotPaused
        updateReward(_account)
    {
        uint256 reward = rewards[_account];
        if (reward > 0) {
            // update state (first)
            rewards[_account] = 0;

            // emit reward claimed event and index account
            emit RewardPaid(_account, reward);

            // transfer token from this contract to the rewardEscrow
            // and create a vesting entry at the _to address
            kwenta.transfer(address(rewardEscrow), reward);
            rewardEscrow.appendVestingEntry(_to, reward);
        }
    }

    /// @inheritdoc IOldStakingRewardsV2
    function compound() external {
        _compound(msg.sender);
    }

    /// @dev internal helper to compound for a given account
    /// @param _account the account to compound for
    function _compound(address _account) internal {
        _getReward(_account);
        _stakeEscrow(_account, unstakedEscrowedBalanceOf(_account));
    }

    /*///////////////////////////////////////////////////////////////
                        REWARD UPDATE CALCULATIONS
    ///////////////////////////////////////////////////////////////*/

    /// @notice update reward state for the account and contract
    /// @param _account: address of account which rewards are being updated for
    /// @dev contract state not specific to an account will be updated also
    modifier updateReward(address _account) {
        _updateReward(_account);
        _;
    }

    function _updateReward(address _account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (_account != address(0)) {
            // update amount of rewards a user can claim
            rewards[_account] = earned(_account);

            // update reward per token staked AT this given time
            // (i.e. when this user is interacting with StakingRewards)
            userRewardPerTokenPaid[_account] = rewardPerTokenStored;
        }
    }

    /// @inheritdoc IOldStakingRewardsV2
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /// @inheritdoc IOldStakingRewardsV2
    function rewardPerToken() public view returns (uint256) {
        uint256 allTokensStaked = totalSupply();

        if (allTokensStaked == 0) {
            return rewardPerTokenStored;
        }

        return rewardPerTokenStored
            + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / allTokensStaked);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @inheritdoc IOldStakingRewardsV2
    function earned(address _account) public view returns (uint256) {
        uint256 totalBalance = balanceOf(_account);

        return ((totalBalance * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18)
            + rewards[_account];
    }

    /*///////////////////////////////////////////////////////////////
                                DELEGATION
    ///////////////////////////////////////////////////////////////*/

    /// @notice access control modifier for approved operators
    modifier onlyOperator(address _accountOwner) {
        _onlyOperator(_accountOwner);
        _;
    }

    function _onlyOperator(address _accountOwner) internal view {
        if (!operatorApprovals[_accountOwner][msg.sender]) revert NotApproved();
    }

    /// @inheritdoc IOldStakingRewardsV2
    function approveOperator(address _operator, bool _approved) external {
        if (_operator == msg.sender) revert CannotApproveSelf();

        operatorApprovals[msg.sender][_operator] = _approved;

        emit OperatorApproved(msg.sender, _operator, _approved);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function stakeEscrowOnBehalf(address _account, uint256 _amount)
        external
        onlyOperator(_account)
    {
        _stakeEscrow(_account, _amount);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function getRewardOnBehalf(address _account) external onlyOperator(_account) {
        _getReward(_account);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function compoundOnBehalf(address _account) external onlyOperator(_account) {
        _compound(_account);
    }

    /*///////////////////////////////////////////////////////////////
                            CHECKPOINTING VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOldStakingRewardsV2
    function balancesCheckpointsLength(address _account) external view returns (uint256) {
        return balancesCheckpoints[_account].length;
    }

    /// @inheritdoc IOldStakingRewardsV2
    function escrowedBalancesCheckpointsLength(address _account) external view returns (uint256) {
        return escrowedBalancesCheckpoints[_account].length;
    }

    /// @inheritdoc IOldStakingRewardsV2
    function totalSupplyCheckpointsLength() external view returns (uint256) {
        return totalSupplyCheckpoints.length;
    }

    /// @inheritdoc IOldStakingRewardsV2
    function balanceAtTime(address _account, uint256 _timestamp) external view returns (uint256) {
        return _checkpointBinarySearch(balancesCheckpoints[_account], _timestamp);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function escrowedBalanceAtTime(address _account, uint256 _timestamp)
        external
        view
        returns (uint256)
    {
        return _checkpointBinarySearch(escrowedBalancesCheckpoints[_account], _timestamp);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function totalSupplyAtTime(uint256 _timestamp) external view returns (uint256) {
        return _checkpointBinarySearch(totalSupplyCheckpoints, _timestamp);
    }

    /// @notice finds the value of the checkpoint at a given timestamp
    /// @param _checkpoints: array of checkpoints to search
    /// @param _timestamp: timestamp to check
    /// @dev returns 0 if no checkpoints exist, uses iterative binary search
    /// @dev if called with a timestamp that equals the current block timestamp, then the function might return inconsistent
    /// values as further transactions changing the balances can still occur within the same block.
    function _checkpointBinarySearch(Checkpoint[] storage _checkpoints, uint256 _timestamp)
        internal
        view
        returns (uint256)
    {
        uint256 length = _checkpoints.length;
        if (length == 0) return 0;

        uint256 min = 0;
        uint256 max = length - 1;

        if (_checkpoints[min].ts > _timestamp) return 0;
        if (_checkpoints[max].ts <= _timestamp) return _checkpoints[max].value;

        while (max > min) {
            uint256 midpoint = (max + min + 1) / 2;
            if (_checkpoints[midpoint].ts <= _timestamp) min = midpoint;
            else max = midpoint - 1;
        }

        assert(min == max);

        return _checkpoints[min].value;
    }

    /*///////////////////////////////////////////////////////////////
                            UPDATE CHECKPOINTS
    ///////////////////////////////////////////////////////////////*/

    /// @notice add a new balance checkpoint for an account
    /// @param _account: address of account to add checkpoint for
    /// @param _value: value of checkpoint to add
    function _addBalancesCheckpoint(address _account, uint256 _value) internal {
        _addCheckpoint(balancesCheckpoints[_account], _value);
    }

    /// @notice add a new escrowed balance checkpoint for an account
    /// @param _account: address of account to add checkpoint for
    /// @param _value: value of checkpoint to add
    function _addEscrowedBalancesCheckpoint(address _account, uint256 _value) internal {
        _addCheckpoint(escrowedBalancesCheckpoints[_account], _value);
    }

    /// @notice add a new total supply checkpoint
    /// @param _value: value of checkpoint to add
    function _addTotalSupplyCheckpoint(uint256 _value) internal {
        _addCheckpoint(totalSupplyCheckpoints, _value);
    }

    /// @notice Adds a new checkpoint or updates the last one
    /// @param checkpoints The array of checkpoints to modify
    /// @param _value The new value to add as a checkpoint
    /// @dev If the last checkpoint is from a different block, a new checkpoint is added.
    /// If it's from the current block, the value of the last checkpoint is updated.
    function _addCheckpoint(Checkpoint[] storage checkpoints, uint256 _value) internal {
        uint256 length = checkpoints.length;
        uint256 lastTimestamp;
        unchecked {
            lastTimestamp = length == 0 ? 0 : checkpoints[length - 1].ts;
        }

        if (lastTimestamp != block.timestamp) {
            checkpoints.push(
                Checkpoint({
                    ts: uint64(block.timestamp),
                    blk: uint64(block.number),
                    value: uint128(_value)
                })
            );
        } else {
            unchecked {
                checkpoints[length - 1].value = uint128(_value);
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                                SETTINGS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOldStakingRewardsV2
    function notifyRewardAmount(uint256 _reward)
        external
        onlyRewardsNotifier
        updateReward(address(0))
    {
        if (block.timestamp >= periodFinish) {
            rewardRate = _reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (_reward + leftover) / rewardsDuration;
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(_reward);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        if (block.timestamp <= periodFinish) revert RewardsPeriodNotComplete();
        if (_rewardsDuration == 0) revert RewardsDurationCannotBeZero();

        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /// @inheritdoc IOldStakingRewardsV2
    function setCooldownPeriod(uint256 _cooldownPeriod) external onlyOwner {
        if (_cooldownPeriod < MIN_COOLDOWN_PERIOD) revert CooldownPeriodTooLow(MIN_COOLDOWN_PERIOD);
        if (_cooldownPeriod > MAX_COOLDOWN_PERIOD) {
            revert CooldownPeriodTooHigh(MAX_COOLDOWN_PERIOD);
        }

        cooldownPeriod = _cooldownPeriod;
        emit CooldownPeriodUpdated(cooldownPeriod);
    }

    /*///////////////////////////////////////////////////////////////
                                PAUSABLE
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOldStakingRewardsV2
    function pauseStakingRewards() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IOldStakingRewardsV2
    function unpauseStakingRewards() external onlyOwner {
        _unpause();
    }

    /*///////////////////////////////////////////////////////////////
                            MISCELLANEOUS
    ///////////////////////////////////////////////////////////////*/

    /// @dev this function is used by the proxy to set the access control for upgrading the implementation contract
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}

    /// @inheritdoc IOldStakingRewardsV2
    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        if (_tokenAddress == address(kwenta)) revert CannotRecoverStakingToken();
        emit Recovered(_tokenAddress, _tokenAmount);
        IERC20(_tokenAddress).transfer(owner(), _tokenAmount);
    }
}
