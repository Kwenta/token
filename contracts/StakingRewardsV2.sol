// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./utils/Owned.sol";
import "./interfaces/IStakingRewardsV2.sol";
import "./interfaces/IStakingRewards.sol";
import "./interfaces/ISupplySchedule.sol";
import "./interfaces/IRewardEscrowV2.sol";

/// @title KWENTA Staking Rewards
/// @author SYNTHETIX, JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc), tommyrharper (zeroknowledgeltd@gmail.com)
/// @notice Updated version of Synthetix's StakingRewards with new features specific
/// to Kwenta
contract StakingRewardsV2 is
    IStakingRewardsV2,
    Owned,
    ReentrancyGuard,
    Pausable
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
    IERC20 public immutable token;

    /// @notice escrow contract which holds (and may stake) reward tokens
    IRewardEscrowV2 public immutable rewardEscrow;

    /// @notice handles reward token minting logic
    ISupplySchedule public immutable supplySchedule;

    /// @notice previous version of staking rewards contract - used for migration
    IStakingRewards public immutable stakingRewardsV1;

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
    uint256 public periodFinish = 0;

    /// @notice amount of tokens minted per second
    uint256 public rewardRate = 0;

    /// @notice period for rewards
    uint256 public rewardsDuration = 7 days;

    /// @notice track last time the rewards were updated
    uint256 public lastUpdateTime;

    /// @notice summation of rewardRate divided by total staked tokens
    uint256 public rewardPerTokenStored;

    /// @notice the period of time a user has to wait after staking to unstake
    uint256 public unstakingCooldownPeriod = 2 weeks;

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
                                EVENTS
    ///////////////////////////////////////////////////////////////*/

    /// @notice update reward rate
    /// @param reward: amount to be distributed over applicable rewards duration
    event RewardAdded(uint256 reward);

    /// @notice emitted when user stakes tokens
    /// @param user: staker address
    /// @param amount: amount staked
    event Staked(address indexed user, uint256 amount);

    /// @notice emitted when user unstakes tokens
    /// @param user: address of user unstaking
    /// @param amount: amount unstaked
    event Unstaked(address indexed user, uint256 amount);

    /// @notice emitted when escrow staked
    /// @param user: owner of escrowed tokens address
    /// @param amount: amount staked
    event EscrowStaked(address indexed user, uint256 amount);

    /// @notice emitted when staked escrow tokens are unstaked
    /// @param user: owner of escrowed tokens address
    /// @param amount: amount unstaked
    event EscrowUnstaked(address user, uint256 amount);

    /// @notice emitted when user claims rewards
    /// @param user: address of user claiming rewards
    /// @param reward: amount of reward token claimed
    event RewardPaid(address indexed user, uint256 reward);

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
    event OperatorApproved(address owner, address operator, bool approved);

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

    /// @notice attempted to approve self as an operator
    error CannotApproveSelf();

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
    modifier onlyApprovedOperator(address owner) {
        if (!_operatorApprovals[owner][msg.sender]) {
            revert NotApprovedOperator();
        }
        _;
    }

    /// @notice only allow execution after the unstaking cooldown period has elapsed
    modifier afterCooldown(address account) {
        uint256 canUnstakeAt =
            userLastStakeTime[account] + unstakingCooldownPeriod;
        if (canUnstakeAt > block.timestamp) {
            revert CannotUnstakeDuringCooldown(canUnstakeAt);
        }
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ///////////////////////////////////////////////////////////////*/

    /// @notice configure StakingRewards state
    /// @dev owner set to address that deployed StakingRewards
    /// @param _token: token used for staking and for rewards
    /// @param _rewardEscrow: escrow contract which holds (and may stake) reward tokens
    /// @param _supplySchedule: handles reward token minting logic
    constructor(
        address _token,
        address _rewardEscrow,
        address _supplySchedule,
        address _stakingRewardsV1
    ) Owned(msg.sender) {
        // define reward/staking token
        token = IERC20(_token);

        // define contracts which will interact with StakingRewards
        rewardEscrow = IRewardEscrowV2(_rewardEscrow);
        supplySchedule = ISupplySchedule(_supplySchedule);
        stakingRewardsV1 = IStakingRewards(_stakingRewardsV1);
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
    /// @param account: address of potential staker
    /// @return amount of tokens staked by account
    function balanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        return balances[account].length == 0
            ? 0
            : balances[account][balances[account].length - 1].value;
    }

    /// @notice Getter function for number of staked escrow tokens
    /// @param account address to check the escrowed tokens staked
    /// @return amount of escrowed tokens staked
    function escrowedBalanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        return escrowedBalances[account].length == 0
            ? 0
            : escrowedBalances[account][escrowedBalances[account].length - 1].value;
    }

    /// @notice Getter function for the total number of v1 staked tokens
    /// @return amount of tokens staked in v1
    function v1TotalSupply() public view override returns (uint256) {
        return stakingRewardsV1.totalSupply();
    }

    /// @notice Getter function for the number of v1 staked tokens
    /// @param account address to check the tokens staked
    /// @return amount of tokens staked
    function v1BalanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        return stakingRewardsV1.balanceOf(account);
    }

    /// @return rewards for the duration specified by rewardsDuration
    function getRewardForDuration() external view override returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /// @notice Getter function for number of staked non-escrow tokens
    /// @param account address to check the non-escrowed tokens staked
    /// @return amount of non-escrowed tokens staked
    function nonEscrowedBalanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        return balanceOf(account) - escrowedBalanceOf(account);
    }

    /*///////////////////////////////////////////////////////////////
                            STAKE/UNSTAKE
    ///////////////////////////////////////////////////////////////*/

    /// @notice stake token
    /// @param amount: amount to stake
    /// @dev updateReward() called prior to function logic
    function stake(uint256 amount)
        external
        override
        nonReentrant
        whenNotPaused
        updateReward(msg.sender)
    {
        require(amount > 0, "StakingRewards: Cannot stake 0");

        // update state
        userLastStakeTime[msg.sender] = block.timestamp;
        _addTotalSupplyCheckpoint(totalSupply() + amount);
        _addBalancesCheckpoint(msg.sender, balanceOf(msg.sender) + amount);

        // transfer token to this contract from the caller
        token.safeTransferFrom(msg.sender, address(this), amount);

        // emit staking event and index msg.sender
        emit Staked(msg.sender, amount);
    }

    /// @notice unstake token
    /// @param amount: amount to unstake
    /// @dev updateReward() called prior to function logic
    function unstake(uint256 amount)
        public
        override
        nonReentrant
        updateReward(msg.sender)
        afterCooldown(msg.sender)
    {
        require(amount > 0, "StakingRewards: Cannot Unstake 0");
        require(
            amount <= nonEscrowedBalanceOf(msg.sender),
            "StakingRewards: Invalid Amount"
        );

        // update state
        _addTotalSupplyCheckpoint(totalSupply() - amount);
        _addBalancesCheckpoint(msg.sender, balanceOf(msg.sender) - amount);

        // transfer token from this contract to the caller
        token.safeTransfer(msg.sender, amount);

        // emit unstake event and index msg.sender
        emit Unstaked(msg.sender, amount);
    }

    /// @notice stake escrowed token
    /// @param account: address which owns token
    /// @param amount: amount to stake
    /// @dev updateReward() called prior to function logic
    /// @dev msg.sender NOT used (account is used)
    function stakeEscrow(address account, uint256 amount)
        external
        override
        onlyRewardEscrow
    {
        _stakeEscrow(account, amount);
    }

    function _stakeEscrow(address account, uint256 amount)
        internal
        whenNotPaused
        updateReward(account)
    {
        require(amount > 0, "StakingRewards: Cannot stake 0");
        uint256 unstakedEscrow = rewardEscrow.unstakedEscrowBalanceOf(account);
        if (amount > unstakedEscrow) {
            revert InsufficientUnstakedEscrow(unstakedEscrow);
        }

        // update state
        userLastStakeTime[account] = block.timestamp;
        _addBalancesCheckpoint(account, balanceOf(account) + amount);
        _addEscrowedBalancesCheckpoint(
            account, escrowedBalanceOf(account) + amount
        );

        // updates total supply despite no new staking token being transfered.
        // escrowed tokens are locked in RewardEscrow
        _addTotalSupplyCheckpoint(totalSupply() + amount);

        // emit escrow staking event and index _account
        emit EscrowStaked(account, amount);
    }

    /// @notice stake escrowed token on behalf of another account
    /// @param account: address which owns token
    /// @param amount: amount to stake
    function stakeEscrowOnBehalf(address account, uint256 amount)
        external
        override
        onlyApprovedOperator(account)
    {
        _stakeEscrow(account, amount);
    }

    /// @notice unstake escrowed token
    /// @param account: address which owns token
    /// @param amount: amount to unstake
    /// @dev updateReward() called prior to function logic
    /// @dev msg.sender NOT used (account is used)
    function unstakeEscrow(address account, uint256 amount)
        external
        override
        nonReentrant
        onlyRewardEscrow
        updateReward(account)
        afterCooldown(account)
    {
        require(amount > 0, "StakingRewards: Cannot Unstake 0");
        require(
            escrowedBalanceOf(account) >= amount,
            "StakingRewards: Invalid Amount"
        );

        // update state
        _addBalancesCheckpoint(account, balanceOf(account) - amount);
        _addEscrowedBalancesCheckpoint(
            account, escrowedBalanceOf(account) - amount
        );

        // updates total supply despite no new staking token being transfered.
        // escrowed tokens are locked in RewardEscrow
        _addTotalSupplyCheckpoint(totalSupply() - amount);

        // emit escrow unstaked event and index account
        emit EscrowUnstaked(account, amount);
    }

    /// @notice unstake all available staked non-escrowed tokens and
    /// claim any rewards
    function exit() external override {
        unstake(nonEscrowedBalanceOf(msg.sender));
        getReward();
    }

    /*///////////////////////////////////////////////////////////////
                            CLAIM REWARDS
    ///////////////////////////////////////////////////////////////*/

    /// @notice caller claims any rewards generated from staking
    /// @dev rewards are escrowed in RewardEscrow
    /// @dev updateReward() called prior to function logic
    function getReward() public override {
        _getReward(msg.sender);
    }

    function _getReward(address account)
        internal
        nonReentrant
        updateReward(account)
    {
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

    /// @notice caller claims any rewards generated from staking on behalf of another account
    /// The rewards will be escrowed in RewardEscrow with the account as the beneficiary
    /// @param account: address which owns token
    function getRewardOnBehalf(address account)
        external
        override
        onlyApprovedOperator(account)
    {
        _getReward(account);
    }

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
    /// @param account: address of account earned amount is being calculated for
    function earned(address account) public view override returns (uint256) {
        uint256 v1Balance = v1BalanceOf(account);
        uint256 v2Balance = balanceOf(account);
        uint256 totalBalance = v1Balance + v2Balance;

        return (
            (
                totalBalance
                    * (rewardPerToken() - userRewardPerTokenPaid[account])
            ) / 1e18
        ) + rewards[account];
    }

    /*///////////////////////////////////////////////////////////////
                            CHECKPOINTING VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @notice get the number of balances checkpoints for an account
    /// @param account: address of account to check
    /// @return number of balances checkpoints
    function balancesLength(address account)
        external
        view
        override
        returns (uint256)
    {
        return balances[account].length;
    }

    /// @notice get the number of escrowed balance checkpoints for an account
    /// @param account: address of account to check
    /// @return number of escrowed balance checkpoints
    function escrowedBalancesLength(address account)
        external
        view
        override
        returns (uint256)
    {
        return escrowedBalances[account].length;
    }

    /// @notice get the number of total supply checkpoints
    /// @return number of total supply checkpoints
    function totalSupplyLength() external view override returns (uint256) {
        return _totalSupply.length;
    }

    /// @notice get a users balance at a given block
    /// @param account: address of account to check
    /// @param _block: block number to check
    /// @return balance at given block
    function balanceAtBlock(address account, uint256 _block)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(balances[account], _block);
    }

    /// @notice get a users escrowed balance at a given block
    /// @param account: address of account to check
    /// @param _block: block number to check
    /// @return escrowed balance at given block
    function escrowedBalanceAtBlock(address account, uint256 _block)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(escrowedBalances[account], _block);
    }

    /// @notice get the total supply at a given block
    /// @param _block: block number to check
    /// @return total supply at given block
    function totalSupplyAtBlock(uint256 _block)
        external
        view
        override
        returns (uint256)
    {
        return _checkpointBinarySearch(_totalSupply, _block);
    }

    /// @notice finds the value of the checkpoint at a given block
    /// @param checkpoints: array of checkpoints to search
    /// @param _block: block number to check
    /// @dev returns 0 if no checkpoints exist, uses iterative binary search
    function _checkpointBinarySearch(
        Checkpoint[] memory checkpoints,
        uint256 _block
    ) internal pure returns (uint256) {
        uint256 length = checkpoints.length;
        if (length == 0) return 0;

        uint256 min = 0;
        uint256 max = length - 1;

        if (checkpoints[min].block > _block) return 0;
        if (checkpoints[max].block <= _block) return checkpoints[max].value;

        while (max > min) {
            uint256 midpoint = (max + min + 1) / 2;
            if (checkpoints[midpoint].block <= _block) min = midpoint;
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
        uint256 lastBlock = balances[account].length == 0
            ? 0
            : balances[account][balances[account].length - 1].block;

        if (lastBlock != block.number) {
            balances[account].push(Checkpoint(block.number, value));
        } else {
            balances[account][balances[account].length - 1].value = value;
        }
    }

    /// @notice add a new escrowed balance checkpoint for an account
    /// @param account: address of account to add checkpoint for
    /// @param value: value of checkpoint to add
    function _addEscrowedBalancesCheckpoint(address account, uint256 value)
        internal
    {
        uint256 lastBlock = escrowedBalances[account].length == 0
            ? 0
            : escrowedBalances[account][escrowedBalances[account].length - 1].block;

        if (lastBlock != block.number) {
            escrowedBalances[account].push(Checkpoint(block.number, value));
        } else {
            escrowedBalances[account][escrowedBalances[account].length - 1]
                .value = value;
        }
    }

    /// @notice add a new total supply checkpoint
    /// @param value: value of checkpoint to add
    function _addTotalSupplyCheckpoint(uint256 value) internal {
        uint256 lastBlock = _totalSupply.length == 0
            ? 0
            : _totalSupply[_totalSupply.length - 1].block;

        if (lastBlock != block.number) {
            _totalSupply.push(Checkpoint(block.number, value));
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

    /*///////////////////////////////////////////////////////////////
                            PAUSABLE
    ///////////////////////////////////////////////////////////////*/

    /// @dev Triggers stopped state
    function pauseStakingRewards() external override onlyOwner {
        Pausable._pause();
    }

    /// @dev Returns to normal state.
    function unpauseStakingRewards() external override onlyOwner {
        Pausable._unpause();
    }

    /*///////////////////////////////////////////////////////////////
                            MISCELLANEOUS
    ///////////////////////////////////////////////////////////////*/

    /// @notice approve an operator to collect rewards and stake escrow on behalf of the sender
    /// @param operator: address of operator to approve
    /// @param approved: whether or not to approve the operator
    function approveOperator(address operator, bool approved)
        external
        override
    {
        if (operator == msg.sender) revert CannotApproveSelf();

        _operatorApprovals[msg.sender][operator] = approved;

        emit OperatorApproved(msg.sender, operator, approved);
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
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
