// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IStakingRewards {
    // Views

    function escrowedBalanceOf(address account) external view returns (uint256);

    function totalRewardScore() external view returns (uint256);
    
    function stakedBalanceOf(address account) external view returns (uint256);
    
    function totalBalanceOf(address account) external view returns (uint256);

    function rewardScoreOf(address account) external view returns (uint256);

    function rewardPerRewardScoreOfEpoch(uint256 _epoch) external view returns (uint256);

    function feesPaidBy(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    // Mutative

    function setPercentageRewards(uint256 _percentageStaking, uint256 _percentageTrading) external;

    function updateTraderScore(address _trader, uint256 _newFeesPaid) external;

    function exit() external;

    function getReward() external;

    function stake(uint256 amount) external;

    function unstake(uint256 amount) external;

    function setRewards(uint256 reward) external;

    function stakeEscrow(address _account, uint256 _amount) external;

    function unstakeEscrow(address _account, uint256 _amount) external;

}