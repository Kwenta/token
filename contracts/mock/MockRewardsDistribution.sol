pragma solidity ^0.8.0;

contract MockRewardsDistribution {

    function distributeRewards(uint amount) external returns (bool) {
        require(amount > 0, "Nothing to distribute");
        emit RewardsDistributed(amount);
        return true;
    }

    event RewardsDistributed(uint amount);

}
