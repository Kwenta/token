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
    function balanceOf(uint256 accountId) external view returns (uint256);
    function v1BalanceOf(uint256 accountId) external view returns (uint256);
    function escrowedBalanceOf(uint256 accountId) external view returns (uint256);
    function nonEscrowedBalanceOf(uint256 accountId) external view returns (uint256);
    // rewards
    function getRewardForDuration() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function lastTimeRewardApplicable() external view returns (uint256);
    function earned(uint256 accountId) external view returns (uint256);
    // checkpointing
    function balancesLength(uint256 accountId) external view returns (uint256);
    function escrowedBalancesLength(uint256 accountId) external view returns (uint256);
    function totalSupplyLength() external view returns (uint256);
    function balanceAtTime(uint256 accountId, uint256 block) external view returns (uint256);
    function escrowedbalanceAtTime(uint256 accountId, uint256 block) external view returns (uint256);
    function totalSupplyAtTime(uint256 block) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                Mutative
    //////////////////////////////////////////////////////////////*/
    // Staking/Unstaking
    function stake(uint256 accountId, uint256 amount) external;
    function unstake(uint256 accountId, uint256 amount) external;
    function stakeEscrow(uint256 accountId, uint256 amount) external;
    function unstakeEscrow(uint256 accountId, uint256 amount) external;
    function stakeEscrowOnBehalf(uint256 accountId, uint256 amount) external;
    function exit(uint256 accountId) external;
    // claim rewards
    function getReward(uint256 accountId) external;
    function getRewardOnBehalf(uint256 accountId) external;
    // settings
    function notifyRewardAmount(uint256 reward) external;
    function setUnstakingCooldownPeriod(uint256 _rewardsDuration) external;
    function setRewardsDuration(uint256 _unstakingCooldownPeriod) external;
    // pausable
    function pauseStakingRewards() external;
    function unpauseStakingRewards() external;
    // misc.
    function approveOperator(uint256 accountId, address operator, bool approved) external;
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
}
