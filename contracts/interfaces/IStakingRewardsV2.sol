// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IStakingRewardsV2 {
    /*//////////////////////////////////////////////////////////////
                                Views
    //////////////////////////////////////////////////////////////*/
    // token state
    function totalSupply() external view returns (uint256);
    function v1TotalSupply() external view returns (uint256);
    // staking state
    function balanceOf(address account) external view returns (uint256);
    function v1BalanceOf(address account) external view returns (uint256);
    function escrowedBalanceOf(address account) external view returns (uint256);
    function nonEscrowedBalanceOf(address account) external view returns (uint256);
    // rewards
    function getRewardForDuration() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function lastTimeRewardApplicable() external view returns (uint256);
    function earned(address account) external view returns (uint256);
    // checkpointing
    function balancesLength(address account) external view returns (uint256);
    function escrowedBalancesLength(address account) external view returns (uint256);
    function totalSupplyLength() external view returns (uint256);
    function balanceAtTime(address account, uint256 block) external view returns (uint256);
    function escrowedbalanceAtTime(address account, uint256 block)
        external
        view
        returns (uint256);
    function totalSupplyAtTime(uint256 block) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                Mutative
    //////////////////////////////////////////////////////////////*/
    // Staking/Unstaking
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function stakeEscrow(address account, uint256 amount) external;
    function unstakeEscrowSkipCooldown(address account, uint256 amount) external;
    function unstakeEscrow(address account, uint256 amount) external;
    function stakeEscrowOnBehalf(address account, uint256 amount) external;
    function exit() external;
    // claim rewards
    function getReward() external;
    function getRewardOnBehalf(address account) external;
    // settings
    function notifyRewardAmount(uint256 reward) external;
    function setUnstakingCooldownPeriod(uint256 _rewardsDuration) external;
    function setRewardsDuration(uint256 _unstakingCooldownPeriod) external;
    // pausable
    function pauseStakingRewards() external;
    function unpauseStakingRewards() external;
    // misc.
    function approveOperator(address operator, bool approved) external;
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    /*//////////////////////////////////////////////////////////////
                                Structs
    //////////////////////////////////////////////////////////////*/

    /// @notice A checkpoint for tracking values at a given block
    struct Checkpoint {
        // The timestamp when the value was generated
        uint256 ts;
        // The value of the checkpoint
        uint256 value;
    }

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

    /// @notice error someone other than reward escrow calls an onlyRewardEscrow function
    error OnlyRewardEscrow();

    /// @notice error someone other than the supply schedule calls an onlySupplySchedule function
    error OnlySupplySchedule();

    /// @notice error when user tries to stake/unstake 0 tokens
    error AmountMustBeGreaterThanZero();

    /// @notice the user does not have enough tokens to unstake that amount
    error InsufficientBalance();

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

}
