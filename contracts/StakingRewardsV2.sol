// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Ownable2StepUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IKwenta} from "./interfaces/IKwenta.sol";
import {IStakingRewardsV2} from "./interfaces/IStakingRewardsV2.sol";
import {IStakingRewardsV2Integrator} from "./interfaces/IStakingRewardsV2Integrator.sol";
import {IStakingRewards} from "./interfaces/IStakingRewards.sol";
import {ISupplySchedule} from "./interfaces/ISupplySchedule.sol";
import {IRewardEscrowV2} from "./interfaces/IRewardEscrowV2.sol";

/// @title KWENTA Staking Rewards V2
/// @author SYNTHETIX, JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc), tommyrharper (zeroknowledgeltd@gmail.com)
/// @notice Updated version of Synthetix's StakingRewards with new features specific to Kwenta
contract StakingRewardsV2 is
    IStakingRewardsV2,
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
    ISupplySchedule public immutable supplySchedule;

    /// @notice previous version of staking rewards contract - used for migration
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IStakingRewards public immutable stakingRewardsV1;

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

    /// @inheritdoc IStakingRewardsV2
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

    /// @notice access control modifier for supplySchedule
    modifier onlySupplySchedule() {
        _onlySupplySchedule();
        _;
    }

    function _onlySupplySchedule() internal view {
        if (msg.sender != address(supplySchedule)) revert OnlySupplySchedule();
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
    constructor(
        address _kwenta,
        address _rewardEscrow,
        address _supplySchedule,
        address _stakingRewardsV1
    ) {
        if (
            _kwenta == address(0) || _rewardEscrow == address(0) || _supplySchedule == address(0)
                || _stakingRewardsV1 == address(0)
        ) revert ZeroAddress();

        _disableInitializers();

        // define reward/staking token
        kwenta = IKwenta(_kwenta);

        // define contracts which will interact with StakingRewards
        rewardEscrow = IRewardEscrowV2(_rewardEscrow);
        supplySchedule = ISupplySchedule(_supplySchedule);
        stakingRewardsV1 = IStakingRewards(_stakingRewardsV1);
    }

    /// @inheritdoc IStakingRewardsV2
    function initialize(address _contractOwner) external override initializer {
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

    /// @inheritdoc IStakingRewardsV2
    function totalSupply() public view override returns (uint256) {
        uint256 length = totalSupplyCheckpoints.length;
        unchecked {
            return length == 0 ? 0 : totalSupplyCheckpoints[length - 1].value;
        }
    }

    /// @inheritdoc IStakingRewardsV2
    function v1TotalSupply() public view override returns (uint256) {
        return stakingRewardsV1.totalSupply();
    }

    /// @inheritdoc IStakingRewardsV2
    function balanceOf(address _account) public view override returns (uint256) {
        Checkpoint[] storage checkpoints = balancesCheckpoints[_account];
        uint256 length = checkpoints.length;
        unchecked {
            return length == 0 ? 0 : checkpoints[length - 1].value;
        }
    }

    /// @inheritdoc IStakingRewardsV2
    function v1BalanceOf(address _account) public view override returns (uint256) {
        return stakingRewardsV1.balanceOf(_account);
    }

    /// @inheritdoc IStakingRewardsV2
    function escrowedBalanceOf(address _account) public view override returns (uint256) {
        Checkpoint[] storage checkpoints = escrowedBalancesCheckpoints[_account];
        uint256 length = checkpoints.length;
        unchecked {
            return length == 0 ? 0 : checkpoints[length - 1].value;
        }
    }

    /// @inheritdoc IStakingRewardsV2
    function nonEscrowedBalanceOf(address _account) public view override returns (uint256) {
        return balanceOf(_account) - escrowedBalanceOf(_account);
    }

    /// @inheritdoc IStakingRewardsV2
    function unstakedEscrowedBalanceOf(address _account) public view override returns (uint256) {
        return rewardEscrow.escrowedBalanceOf(_account) - escrowedBalanceOf(_account);
    }

    /*///////////////////////////////////////////////////////////////
                            STAKE/UNSTAKE
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function stake(uint256 _amount) external override whenNotPaused updateReward(msg.sender) {
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

    /// @inheritdoc IStakingRewardsV2
    function unstake(uint256 _amount) public override updateReward(msg.sender) {
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

    /// @inheritdoc IStakingRewardsV2
    function stakeEscrow(uint256 _amount) external override {
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

    /// @inheritdoc IStakingRewardsV2
    function unstakeEscrow(uint256 _amount) external override {
        _unstakeEscrow(msg.sender, _amount);
    }

    /// @inheritdoc IStakingRewardsV2
    function unstakeEscrowSkipCooldown(address _account, uint256 _amount)
        external
        override
        onlyRewardEscrow
    {
        _unstakeEscrow(_account, _amount);
    }

    function _unstakeEscrow(address _account, uint256 _amount) internal updateReward(_account) {
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

    /// @inheritdoc IStakingRewardsV2
    function exit() external override {
        unstake(nonEscrowedBalanceOf(msg.sender));
        _getReward(msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                            CLAIM REWARDS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function getReward() external override {
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

    /*//////////////////////////////////////////////////////////////
                           INTEGRATOR REWARDS
    //////////////////////////////////////////////////////////////*/

    function getIntegratorReward(address _integrator) public override {
        address beneficiary = IStakingRewardsV2Integrator(_integrator).beneficiary();
        if (beneficiary != msg.sender) revert NotApproved();
        _getReward(_integrator, beneficiary);
    }

    function getIntegratorAndSenderReward(address _integrator) external override {
        getIntegratorReward(_integrator);
        _getReward(msg.sender);
    }

    function getIntegratorRewardAndCompound(address _integrator) external override {
        getIntegratorReward(_integrator);
        _compound(msg.sender);
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
                    / sumOfAllStakedTokens
            );
    }

    /// @inheritdoc IStakingRewardsV2
    function lastTimeRewardApplicable() public view override returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @inheritdoc IStakingRewardsV2
    function earned(address _account) public view override returns (uint256) {
        uint256 v1Balance = v1BalanceOf(_account);
        uint256 v2Balance = balanceOf(_account);
        uint256 totalBalance = v1Balance + v2Balance;

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

    /// @inheritdoc IStakingRewardsV2
    function approveOperator(address _operator, bool _approved) external override {
        if (_operator == msg.sender) revert CannotApproveSelf();

        operatorApprovals[msg.sender][_operator] = _approved;

        emit OperatorApproved(msg.sender, _operator, _approved);
    }

    /// @inheritdoc IStakingRewardsV2
    function stakeEscrowOnBehalf(address _account, uint256 _amount)
        external
        override
        onlyOperator(_account)
    {
        _stakeEscrow(_account, _amount);
    }

    /// @inheritdoc IStakingRewardsV2
    function getRewardOnBehalf(address _account) external override onlyOperator(_account) {
        _getReward(_account);
    }

    /// @inheritdoc IStakingRewardsV2
    function compoundOnBehalf(address _account) external override onlyOperator(_account) {
        _compound(_account);
    }

    /*///////////////////////////////////////////////////////////////
                            CHECKPOINTING VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function balancesCheckpointsLength(address _account) external view override returns (uint256) {
        return balancesCheckpoints[_account].length;
    }

    /// @inheritdoc IStakingRewardsV2
    function escrowedBalancesCheckpointsLength(address _account)
        external
        view
        override
        returns (uint256)
    {
        return escrowedBalancesCheckpoints[_account].length;
    }

    /// @inheritdoc IStakingRewardsV2
    function totalSupplyCheckpointsLength() external view override returns (uint256) {
        return totalSupplyCheckpoints.length;
    }

    /// @inheritdoc IStakingRewardsV2
    function balanceAtTime(address _account, uint256 _timestamp)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(balancesCheckpoints[_account], _timestamp);
    }

    /// @inheritdoc IStakingRewardsV2
    function escrowedbalanceAtTime(address _account, uint256 _timestamp)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(escrowedBalancesCheckpoints[_account], _timestamp);
    }

    /// @inheritdoc IStakingRewardsV2
    function totalSupplyAtTime(uint256 _timestamp) external view override returns (uint256) {
        return _checkpointBinarySearch(totalSupplyCheckpoints, _timestamp);
    }

    /// @notice finds the value of the checkpoint at a given timestamp
    /// @param _checkpoints: array of checkpoints to search
    /// @param _timestamp: timestamp to check
    /// @dev returns 0 if no checkpoints exist, uses iterative binary search
    function _checkpointBinarySearch(Checkpoint[] memory _checkpoints, uint256 _timestamp)
        internal
        pure
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
        Checkpoint[] storage checkpoints = balancesCheckpoints[_account];
        uint256 length = checkpoints.length;
        uint256 lastTimestamp;
        unchecked {
            lastTimestamp = length == 0 ? 0 : checkpoints[length - 1].ts;
        }

        if (lastTimestamp != block.timestamp) {
            checkpoints.push(Checkpoint({ts: block.timestamp, blk: block.number, value: _value}));
        } else {
            unchecked {
                checkpoints[length - 1].value = _value;
            }
        }
    }

    /// @notice add a new escrowed balance checkpoint for an account
    /// @param _account: address of account to add checkpoint for
    /// @param _value: value of checkpoint to add
    function _addEscrowedBalancesCheckpoint(address _account, uint256 _value) internal {
        Checkpoint[] storage checkpoints = escrowedBalancesCheckpoints[_account];
        uint256 length = checkpoints.length;
        uint256 lastTimestamp;
        unchecked {
            lastTimestamp = length == 0 ? 0 : checkpoints[length - 1].ts;
        }

        if (lastTimestamp != block.timestamp) {
            checkpoints.push(Checkpoint({ts: block.timestamp, blk: block.number, value: _value}));
        } else {
            unchecked {
                checkpoints[length - 1].value = _value;
            }
        }
    }

    /// @notice add a new total supply checkpoint
    /// @param _value: value of checkpoint to add
    function _addTotalSupplyCheckpoint(uint256 _value) internal {
        uint256 length = totalSupplyCheckpoints.length;
        uint256 lastTimestamp;
        unchecked {
            lastTimestamp = length == 0 ? 0 : totalSupplyCheckpoints[length - 1].ts;
        }

        if (lastTimestamp != block.timestamp) {
            totalSupplyCheckpoints.push(
                Checkpoint({ts: block.timestamp, blk: block.number, value: _value})
            );
        } else {
            unchecked {
                totalSupplyCheckpoints[length - 1].value = _value;
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                                SETTINGS
    ///////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStakingRewardsV2
    function notifyRewardAmount(uint256 _reward)
        external
        override
        onlySupplySchedule
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

    /// @inheritdoc IStakingRewardsV2
    function setRewardsDuration(uint256 _rewardsDuration) external override onlyOwner {
        if (block.timestamp <= periodFinish) revert RewardsPeriodNotComplete();
        if (_rewardsDuration == 0) revert RewardsDurationCannotBeZero();

        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /// @inheritdoc IStakingRewardsV2
    function setCooldownPeriod(uint256 _cooldownPeriod) external override onlyOwner {
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
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}

    /// @inheritdoc IStakingRewardsV2
    function recoverERC20(address _tokenAddress, uint256 _tokenAmount)
        external
        override
        onlyOwner
    {
        if (_tokenAddress == address(kwenta)) revert CannotRecoverStakingToken();
        emit Recovered(_tokenAddress, _tokenAmount);
        IERC20(_tokenAddress).transfer(owner(), _tokenAmount);
    }

    function recoverFundsForRollback(address to) external onlyOwner {
        /// @dev the number for stakedEscrow was calculated off-chain (this is the only way)
        /// @dev in order to know the exact amount of liquid kwenta staked in the contract we have to use this off-chain data
        /// @dev in the test file stakingV2.rollback.fork.t there is a test `test_Roll_Back`
        /// @dev this test iterates through all 81 staked users and unstakes their kwenta after recoverFundsForRollback is called
        /// @dev the test is doing using vm.rollFork on optimism mainnet to just after this contract was paused
        /// @dev this shows that there will still be enough KWENTA in the contract for all users to unstake after this function is called
        uint256 stakedEscrow = 0.4553955570144866 ether;
        uint256 totalLiquidStaked = totalSupply() - stakedEscrow;
        uint256 balance = kwenta.balanceOf(address(this));
        uint256 kwentaThatCanBeClaimed = balance - totalLiquidStaked;
        kwenta.transfer(to, kwentaThatCanBeClaimed);
    }
}
