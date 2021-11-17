// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import necessary contracts for math operations and Token handling
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./libraries/FixidityLib.sol";
import "./libraries/ExponentLib.sol";
import "./libraries/LogarithmLib.sol";

import "./libraries/DecayRateLib.sol";

// Inheritance
import "./Pausable.sol";
// Import RewardEscrow contract for Escrow interactions
import "./RewardEscrow.sol";

/*
    StakingRewards contract for Kwenta responsible for:
    - Staking KWENTA tokens
    - Withdrawing KWENTA tokens
    - Updating staker and trader scores
    - Calculating and notifying rewards
    */
contract StakingRewards is ReentrancyGuardUpgradeable, Pausable, UUPSUpgradeable {
    using FixidityLib for FixidityLib.Fixidity;
    using ExponentLib for FixidityLib.Fixidity;
    using LogarithmLib for FixidityLib.Fixidity;

    /* ========== STATE VARIABLES ========== */

    FixidityLib.Fixidity private fixidity;

    // Reward Escrow
    RewardEscrow public rewardEscrow;

    // ExchangerProxy
    address private exchangerProxy;

    // Tokens to stake and reward
    IERC20 public rewardsToken;
    IERC20 public stakingToken;
    // Time handling:
    // Time where new reward epoch finishes 
    uint256 public periodFinish;
    // Reward rate per second for next epoch
    uint256 public rewardRate;
    uint256 public rewardRateStaking;
    uint256 public rewardRateTrading;
    // Epoch default duration
    uint256 public rewardsDuration;
    // Last time an event altering the rewardscore
    uint256 private lastUpdateTimeRewardScore;
    // Last rewardRate per RewardScore
    uint256 private rewardPerRewardScoreStored;
    // Last Update Time for staking Rewards
    uint256 private lastUpdateTime;
    // Last reward per token staked
    uint256 private rewardPerTokenStored;
    // Time to zero for decay rate
    uint256 public timeToZero;
    uint256 public rewardStartedTime;
    // Decay Rate variables
    uint256 private lastTotalSlope;

    // Mapping containing future decaying slopes of totalRewardScores
    mapping(uint256 => uint256) private slopeChanges;
    // Mapping containing future decaying slopes of each user's total rewards
    mapping(address => mapping(uint256 => uint256)) private userRewardScoreSlopeChanges;
    // Custom data structure to save (i) last state of user reward score, (ii) slope and (iii) updated time
    struct StateUser {
        uint256 lastRewardScore;
        uint256 lastSlope;
        uint256 lastUpdated;
    }
    // Mapping containing the last state of each user
    mapping(address => StateUser) private lastStateUser;

    
    // Save the latest reward per RewardScore applicable for each address (Trading Rewards)
    mapping(address => uint256) private userRewardPerRewardScorePaid;
    // Save the latest reward per Token applicable for each address (Staking Rewards)
    mapping(address => uint256) private userRewardPerTokenPaid;
    // Rewards due to each account
    mapping(address => uint256) public rewards;

    // Total RewardsScore
    uint256 private _totalRewardScore;
    // Total area under the decaying total reward score curve
    uint256 private _accumulatedTotalRewardScore;
    // Total tokens included in rewards (both staked and escrowed)
    uint256 private _totalSupply;
    
    // Tokens escrowed for each address
    mapping(address => uint256) private _escrowedBalances;
    // Fees paid for each address
    mapping(address => uint256) private _feesPaid;
    // Save the latest total token to account for rewards (staked + escrowed rewards)
    mapping(address => uint256) private _totalBalances;
    // Save the rewardScore per address
    mapping(address => uint256) private _rewardScores;
    // Total area under each user's reward score curve
    mapping(address => uint256) private _accumulatedRewardScores;
    // Division of rewards between staking and trading
    uint256 public PERCENTAGE_STAKING;
    uint256 public PERCENTAGE_TRADING;

    
    // Decimals calculations
    uint256 private constant MAX_BPS = 10_000;
    uint256 private constant DECIMALS_DIFFERENCE = 1e30;
    // Needs to be int256 for power library, root to calculate is equal to 0.7
    int256 private constant WEIGHT_FEES = 7e17;
    // 1/0.7 constant used to update the rewardscore when increasing the trading fees spent
    int256 private constant INVERSE_WEIGHT_FEES = 1_428_571_428_571_430_000;
    // Needs to be int256 for power library, root to calculate is equal to 0.3
    int256 private constant WEIGHT_STAKING = 3e17;
    // 
    uint256 private constant DAY = 1 days;

    /* ========== PROXY VARIABLES ========== */
    address private admin;
    address private pendingAdmin;
    
    /* ========== INITIALIZER ========== */
    function initialize(address _owner,
        address _rewardsToken,
        address _stakingToken,
        address _rewardEscrow,
        uint256 _timeToZero
    ) public initializer {
        __Pausable_init(_owner);

        __ReentrancyGuard_init();

        admin = _owner;
        pendingAdmin = _owner;

        periodFinish = 0;
        rewardRate = 0;
        rewardsDuration = 7 days;

        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        fixidity.init(18);

        timeToZero = _timeToZero;

        rewardEscrow = RewardEscrow(_rewardEscrow);

        PERCENTAGE_STAKING = 8_000;
        PERCENTAGE_TRADING = 2_000;
    }

    /* ========== VIEWS ========== */

    /*
    * @notice Getter function for the state variable _totalRewardScore
    * @return sum of all rewardScores
    */
    function totalRewardScore() public view returns (uint256) {
        return _totalRewardScore;
    }

    /*
    * @notice Getter function for the staked balance of an account
    * @param account address to check token balance of
    * @return token balance of specified account
    */
    function balanceOf(address account) public view returns (uint256) {
        return _totalBalances[account] - _escrowedBalances[account];
    }

    /*
    * @notice Getter function for the reward score of an account
    * @param account address to check the reward score of
    * @return reward score of specified account
    */
    function rewardScoreOf(address account) external view returns (uint256) {
        return _rewardScores[account];
    }

    /*
    * @notice Getter function for the total balances of an account (staked + escrowed rewards)
    * @param account address to check the total balance of
    * @return total balance of specified account
    */
    function totalBalanceOf(address account) external view returns (uint256) {
        return _totalBalances[account];
    }

    /*
    * @notice Getter function for the escrowed balance of an account
    * @param account address to check the escrowed balance of
    * @return escrowed balance of specified account
    */
    function escrowedBalanceOf(address account) external view returns (uint256) {
        return _escrowedBalances[account];
    }

    /*
    * @notice Getter function for the total fees paid by an account
    * @param account address to check the fees balance of
    * @return fees of specified account
    */
    function feesPaidBy(address account) external view returns (uint256) {
        return _feesPaid[account];
    }

    /*
    * @notice Calculate if we are still in the reward epoch or we reached periodFinish
    * @return Max date to sum rewards, either now or period finish
    */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    /*
    * @notice Calculate the reward distribution per token based on the time elapsed and current value of totalSupply
    * @return corresponding reward per token stored
    */
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (
                (lastTimeRewardApplicable() - lastUpdateTime) * rewardRateStaking * DECIMALS_DIFFERENCE / _totalSupply
            );
    }

    /*
    * @notice Function calculating the state of reward to be delivered per unit of reward score before the new change
    * takes place. Saved in userRewardPerRewardScorePaid and used later in function earned() to calculate the 
    * extra rewards to add taking into account the reward conditions of the latest change and the current earned() 
    * context
    * @return uint256 containing the new reward per rewardScore 
    */
    
    function rewardPerRewardScore() public view returns (uint256) {
        if (_accumulatedTotalRewardScore == 0) {
            return rewardPerRewardScoreStored;
        }
        return
            rewardPerRewardScoreStored + (
                (lastTimeRewardApplicable() - Math.min(lastUpdateTimeRewardScore, periodFinish)) * rewardRateTrading * DECIMALS_DIFFERENCE / _accumulatedTotalRewardScore
            );
    }

    /*
    * @notice Function calculating the rewards earned by an account between the current call moment and the latest change in
    * reward score. The function divides the reward score by the total amount, accounts for the changes between now and the 
    * last changes (deducting userRewardPerRewardScorePaid) and adds the result to the existing rewards balance of the account
    * @param account to calculate the earned rewards
    * @return uint256 containing the total rewards due to account
    */
    function earned(address account) public view returns(uint256) {
        // rewardScores must be decayed!
        uint256 stakingRewards = _totalBalances[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / DECIMALS_DIFFERENCE;
        uint256 tradingRewards = _accumulatedRewardScores[account] * (rewardPerRewardScore() - userRewardPerRewardScorePaid[account]) / DECIMALS_DIFFERENCE;
        return stakingRewards + tradingRewards + rewards[account];
    }

    /*
    * @notice Calculate the total rewards delivered in a specific duration, multiplying rewardRate x duration
    * @return uint256 containing the total rewards to be delivered
    */
    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Set the % distribution between staking and trading
     * @dev Only the owner can use this function and parameters should be in base 10_000 (80% = 8_000)
     * @param _percentageStaking the % of rewards to distribute to staking scores
     * @param _percentageTrading the % of rewards to distribute to reward scores
     */
    function setPercentageRewards(uint256 _percentageStaking, uint256 _percentageTrading) external onlyOwner {
        require(_percentageTrading + _percentageStaking == 10_000);
        PERCENTAGE_STAKING = _percentageStaking;
        PERCENTAGE_TRADING = _percentageTrading;
    }

    /*
    * @notice Function called by the ExchangerProxy updating the fees paid by each account and the contribution
    * to the total reward scores
    * @param _trader: address, for which to update the score
    * @param _feesPaid: uint256, total fees paid in this period
    */
    function updateTraderScore(address _trader, uint256 _newFeesPaid) external onlyExchangerProxy updateRewards(_trader) {
        _feesPaid[_trader] += _newFeesPaid;
        uint256 oldRewardScore = _rewardScores[_trader];
        updateRewardScore(_trader, 0, oldRewardScore, _newFeesPaid);
    }

    /*
    * @notice Function used to increase the already existing user slopes (due to a new staking)
    * @param _account: address, for which to update the score
    * @param additionalSlope: uint256, new slope in tokens per second to add
    * @param updateTime: uint256, time of update
    * @param _timeToZero: uint256, when will the slope alter the total
    */
    function addUserSlopes(
        address _account, 
        uint256 additionalSlope, 
        uint256 updateTime, 
        uint256 _timeToZero) internal {

        uint256 lastTime = updateTime + _timeToZero;

        for(uint256 i = updateTime; i <= lastTime; i+=DAY) {
            if(userRewardScoreSlopeChanges[_account][i] > 0){
                addSlope(_account, additionalSlope, i);
            }
        }
    }

    /*
    * @notice Function used to decrease each user's slopes (due to a withdrawal of tokens)
    * @param _account: address, for which to update the score
    * @param removeSlope: uint256, new slope in tokens per second to substract
    * @param updateTime: uint256, time of update
    * @param _timeToZero: uint256, when will the slope alter the total
    */
    function decreaseUserSlopes(
        address _account, 
        uint256 removeSlope, 
        uint256 updateTime, 
        uint256 _timeToZero) internal {

        uint256 lastTime = updateTime + _timeToZero;

        for(uint256 i = updateTime; i <= lastTime; i+=DAY) {
            if(userRewardScoreSlopeChanges[_account][i] > 0){
                if(userRewardScoreSlopeChanges[_account][i] >= removeSlope) {
                    userRewardScoreSlopeChanges[_account][i] = userRewardScoreSlopeChanges[_account][i] - removeSlope;
                } else {
                    userRewardScoreSlopeChanges[_account][i] = 0;
                }
                slopeChanges[i] = slopeChanges[i] - removeSlope;
            }
        }
    }

    /*
    * @notice Function used to add a new slope change to the user and the decayed totalRewardScore calculation
    * @param _account: address, for which to update the score
    * @param slope: uint256, new slope in tokens per second to add
    * @param updateTime: uint256, time of update
    * @param _timeToZero: uint256, when will the slope alter the total
    */
    function addSlope(address _account, uint256 slope, uint256 nextChange) internal {
        userRewardScoreSlopeChanges[_account][nextChange] += slope;
        slopeChanges[nextChange] += slope;
    }

    /*
    * @notice Getter function for the total slope change required
    * @param timeSlopeChange, uint256 containing the date for which to lookup the slope change
    * @return slope change for the specific day required
    */
    function getSlopeChangeAt(uint256 timeSlopeChange) external view returns(uint) {
        return slopeChanges[timeSlopeChange];
    }

    /*
    * @notice Setter function for the state of the total reward score (value, slope, accumulated)
    * @param slope new slope to update to
    * @param total new total to update to
    * @param accumulated new accumuladted total to update to
    */
    function setNewTotalState(uint256 slope, uint256 total, uint256 accumulated) internal {
        lastTotalSlope = slope;
        _totalRewardScore = total;
        _accumulatedTotalRewardScore = accumulated;
    }

    /*
    * @notice Getter function for the user slope change required
    * @param account address to check the slope change
    * @param timeSlopeChange, uint256 containing the date for which to lookup the slope change
    * @return slope change for the specific account and day required
    */
    function getUserSlopeChangeAt(address _account, uint256 timeSlopeChange) external view returns(uint) {
        return userRewardScoreSlopeChanges[_account][timeSlopeChange];
    }

    /*
    * @notice Setter function for the new user state
    * @param account address to update last state of
    * @param slope new slope to update to
    * @param total new total to update to
    * @param lastUpdate new lastUpdate time to update to
    */
    function setNewUserState(address _account, uint256 slope, uint256 total, uint256 lastUpdate) internal {
        lastStateUser[_account].lastSlope = slope;
        lastStateUser[_account].lastRewardScore = total;
        lastStateUser[_account].lastUpdated = lastUpdate;
    }

    /*
    * @notice Setter function for the new user accumulated state
    * @param account address to update last state of
    * @param accumulated new user accumulated value to update to
    */
    function setNewAccumulatedUser(address _account, uint256 accumulated) internal {
        _accumulatedRewardScores[_account] = accumulated;
    }

    /*
    * @notice Wrapper to calculate the decayed total reward score using the DecayRateLib
    */
    function calculateDecayedTotalRewardScore() internal {

        DecayRateLib.ParamsCalculateDecayedRewardScore memory params = DecayRateLib.ParamsCalculateDecayedRewardScore(
           lastTotalSlope,
           _totalRewardScore,
           (periodFinish/DAY)*DAY,
           rewardStartedTime,
           _accumulatedTotalRewardScore,
           lastUpdateTimeRewardScore,
           timeToZero
        );

        (uint256 totalSlope, uint256 total, uint256 accumulated) = DecayRateLib.calculateDecayedTotalRewardScore(
            params);
        setNewTotalState(totalSlope, total, accumulated);
    }

    /*
    * @notice Wrapper to calculate the decayed user reward score using the DecayRateLib
    * @return new reward score for the requested account
    */
    function calculateDecayedUserRewardScore(address account) internal returns(uint256) {
        
        DecayRateLib.ParamsCalculateDecayedRewardScore memory params = DecayRateLib.ParamsCalculateDecayedRewardScore(
           lastStateUser[account].lastSlope,
           lastStateUser[account].lastRewardScore,
           (periodFinish/DAY)*DAY,
           rewardStartedTime,
           _accumulatedRewardScores[account],
           lastStateUser[account].lastUpdated,
           timeToZero
        );

        (uint256 userSlope, uint256 userTotal, uint256 userAccumulated) = DecayRateLib.calculateDecayedUserRewardScore(
                account,
                params);
        setNewUserState(account, userSlope, userTotal, (block.timestamp / DAY) * DAY);
        setNewAccumulatedUser(account, userAccumulated);

        return userTotal;
    }

    /*
    * @notice update the reward score depending on the scenario (using the DecayRateLib):
    * - if token balance has changed: re-scale the previous reward score
    * - if fee balance has changed: re-calculate the reward score accounting for new fees
    * - if previous reward score is 0, calculate the reward score from scratch
    * Adjust both the total and user slopes accordingly
    * @param _account, the user to update the reward score to
    * @param _prevBalance, user's previous total Balance, will be 0 if coming from it's not a re-scaling
    * @param _oldRewardScore, user's previous reward score, used to update the total reward score
    * @param _newFees, user's new amount of fees, only used if called from updateTraderScore()
    */
    function updateRewardScore(address _account, uint256 _prevBalance, uint256 _oldRewardScore, uint256 _newFees) internal {
        uint256 roundedTime = (block.timestamp / DAY) * DAY;
        uint256 _totalBalanceUser = _totalBalances[_account];
        DecayRateLib.ParamsCalculateRewardScore memory params = DecayRateLib.ParamsCalculateRewardScore(
            _account,
            _prevBalance, 
            _newFees,
            _totalBalanceUser,
            lastStateUser[_account].lastSlope,
            _oldRewardScore,
            WEIGHT_STAKING,
            WEIGHT_FEES,
            INVERSE_WEIGHT_FEES,
            timeToZero
        );
        uint256 _timeToZero = timeToZero;
        uint256 newRewardScore = 0;
        uint256 lastSlope = 0;
        uint256 prevSlope = lastStateUser[_account].lastSlope;

        if((_totalBalanceUser == 0) || (_totalBalanceUser > 0 && _oldRewardScore == 0 && _newFees == 0)) {
                setNewUserState(_account, 0, 0, roundedTime);
        } else if(_oldRewardScore > 0 && _prevBalance > 0) {
            if (_newFees == 0) {
                (newRewardScore, lastSlope) = DecayRateLib.scalePreviousRewardScore(params, fixidity);
                // If we have increased tokens, add slope, if not, substract
                if(_totalBalanceUser > _prevBalance) {
                    addUserSlopes(_account, lastSlope - prevSlope, roundedTime, _timeToZero);
                } else {
                    decreaseUserSlopes(_account, prevSlope - lastSlope, roundedTime, _timeToZero);
                }
                lastTotalSlope = lastTotalSlope - prevSlope + lastSlope;
            } else {
                (newRewardScore, lastSlope) = DecayRateLib.increaseFeesRewardScore(params, fixidity);
                addSlope(_account, lastSlope, roundedTime + _timeToZero);
                lastTotalSlope = lastTotalSlope + lastSlope;
                lastSlope = prevSlope + lastSlope;
            }
        } else {
            newRewardScore = DecayRateLib.calculateRewardScore(params, fixidity);
            lastSlope = newRewardScore / _timeToZero;
            addSlope(_account, lastSlope, roundedTime + _timeToZero);
            lastTotalSlope = lastTotalSlope + lastSlope;
        }

        setNewUserState(_account, lastSlope, newRewardScore, roundedTime);

        _rewardScores[_account] = newRewardScore;
        _totalRewardScore = _totalRewardScore - _oldRewardScore + newRewardScore;
        lastUpdateTimeRewardScore = block.timestamp;
    }


    /*
    * @notice Function staking the requested tokens by the user.
    * @param _amount: uint256, containing the number of tokens to stake
    */
    function stake(uint256 _amount) external nonReentrant notPaused updateRewards(msg.sender) {
        require(_amount > 0);
        // Update caller balance
        uint256 oldRewardScore = _rewardScores[msg.sender];
        uint256 _totalBalance = _totalBalances[msg.sender];
        _totalBalances[msg.sender] = _totalBalance + _amount;
        _totalSupply = _totalSupply + _amount;
        updateRewardScore(msg.sender, _totalBalance, oldRewardScore, 0);
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    /*
    * @notice Function withdrawing the requested tokens by the user.
    * @param _amount: uint256, containing the number of tokens to stake
    */
    function withdraw(uint256 _amount) public nonReentrant updateRewards(msg.sender) {
        require(_amount > 0, "Cannot withdraw 0");
        require(balanceOf(msg.sender) >= _amount);
        // Update caller balance
        uint256 oldRewardScore = _rewardScores[msg.sender];
        uint256 _totalBalance = _totalBalances[msg.sender];
        _totalBalances[msg.sender] = _totalBalance - _amount;
        _totalSupply = _totalSupply - _amount;
        updateRewardScore(msg.sender, _totalBalance, oldRewardScore, 0);
        stakingToken.transfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    /*
    * @notice Function transferring the accumulated rewards for the caller address and updating the state mapping 
    containing the current rewards
    */
    function getReward() public updateRewards(msg.sender) nonReentrant {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            // Send the rewards to Escrow for 1 year
            stakingToken.transfer(address(rewardEscrow), reward);
            rewardEscrow.appendVestingEntry(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /*
    * @notice Function handling the exit of the protocol of the caller:
    * - Withdraws all tokens
    * - Transfers all rewards to caller's address
    */
    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    /*
    * @notice Function called from RewardEscrow (append vesting entry) to accumulate escrowed tokens into rewards
    * @param _account: address escrowing the rewards
    * @param _amount: uint256, amount escrowed
    */
    function stakeEscrow(address _account, uint256 _amount) public onlyRewardEscrow updateRewards(_account) {
        uint256 oldRewardScore = _rewardScores[_account];
        uint256 _totalBalance = _totalBalances[_account];
        _totalBalances[_account] = _totalBalance + _amount;
        _totalSupply = _totalSupply + _amount;
        _escrowedBalances[_account] = _escrowedBalances[_account] + _amount;
        updateRewardScore(_account, _totalBalance, oldRewardScore, 0);
        emit EscrowStaked(_account, _amount);
    }

    /*
    * @notice Function called from RewardEscrow (vest) to deduct the escrowed tokens and not accumulate rewards
    * @param _account: address escrowing the rewards
    * @param _amount: uint256, amount escrowed
    */
    function unstakeEscrow(address _account, uint256 _amount) public nonReentrant onlyRewardEscrow updateRewards(_account) {
        require(_escrowedBalances[_account] >= _amount);
        uint256 oldRewardScore = _rewardScores[_account];
        uint256 _totalBalance = _totalBalances[_account];
        _totalBalances[_account] = _totalBalance - _amount;
        _totalSupply = _totalSupply - _amount;
        _escrowedBalances[_account] = _escrowedBalances[_account] - _amount;
        updateRewardScore(_account, _totalBalance, oldRewardScore, 0);
        emit EscrowUnstaked(_account, _amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /*
    * @notice Function called to initialize a new reward distribution epoch, taking into account rewards still to be 
    * delivered from a previous epoch and updating the lastUpdate and periodFinish state variables
    * @param reward, amount to be distributed among stakers and traders
    */
    function notifyRewardAmount(uint256 reward) external updateRewards(address(0)) {
    // If the previous epoch is finished, rewardRate calculation is straightforward
    // if not, add to the new amount to be delivered the remaining rewards still to be delivered by previous epoch
        if (block.timestamp >= periodFinish) {
            // Formula: rewardRate = total reward / time
            rewardRate = reward / rewardsDuration;
            rewardStartedTime = (block.timestamp / DAY) * DAY;
        } else {
            // Time to finish the previous reward epoch
            uint256 remaining = periodFinish - block.timestamp;
            // Total rewardsa still to be delivered in previous epoch
            uint256 leftover = remaining * rewardRate;
            // Formula: rewardRate = (sum of remaining rewards and new amount) / time
            rewardRate = (reward + leftover) / rewardsDuration;
        }
        rewardRateStaking = rewardRate * PERCENTAGE_STAKING / MAX_BPS;
        rewardRateTrading = rewardRate * PERCENTAGE_TRADING / MAX_BPS;

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        
        require(rewardRate <= balance / rewardsDuration);

        // Time updates
        lastUpdateTimeRewardScore = block.timestamp;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    // @notice Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken));
        IERC20(tokenAddress).transfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /*
    * @notice Function available for the owner to change the rewardEscrow contract to use
    * @param address of the rewardEsxrow contract to use
    */
    function setRewardEscrow(address _rewardEscrow) external onlyOwner {
        rewardEscrow = RewardEscrow(_rewardEscrow);
        emit RewardEscrowUpdated(address(_rewardEscrow));
    }

    /*
    * @notice Function available for the owner to change the exchangerProxy contract to use
    * @param address of the exchanger proxy to use
    */
    function setExchangerProxy(address _exchangerProxy) external onlyOwner {
        exchangerProxy = _exchangerProxy;
        emit ExchangerProxyUpdated(_exchangerProxy);
    }

    /*
    * @notice Function available for the owner to change the rewards duration via the state variable _rewardsDuration
    * @param _rewardsDuration to set
    */
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > periodFinish
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /*
    * @notice Function available for the owner to change the decay rate period
    * @param _rewardsDuration to set
    */
    function setDecayRate(uint256 newTimeToZero) external onlyOwner {
        require(
            block.timestamp > periodFinish
        );
        timeToZero = newTimeToZero;
    }

    /* ========== MODIFIERS ========== */

    /*
    * @notice Modifier called each time an event changing the trading score is updated:
    * - update trader score
    * - notify reward amount
    * The modifier saves the state of the reward rate per fee until this point for the specific 
    * address to be able to calculate the marginal contribution to rewards afterwards and adds the accumulated
    * rewards since the last change to the account rewards
    * @param address to update rewards to
    */  
    modifier updateRewards(address account) {
        _updateRewards(account);
        _;
    }

    /*
    * @notice internal function used in the modifier with the same name to optimize bytecode
    */
    function _updateRewards(address account) public {
        // Calculate the reward per unit of reward score applicable to the last stint of account
        rewardPerTokenStored = rewardPerToken();
        // Decay the total reward score sum and the total accumulated reward score
        calculateDecayedTotalRewardScore();
        rewardPerRewardScoreStored = rewardPerRewardScore();
        // Calculate if the epoch is finished or not
        lastUpdateTime = lastTimeRewardApplicable();
        lastUpdateTimeRewardScore = block.timestamp; // lastTimeRewardApplicable();
        if (account != address(0)) {
            // Add the rewards added during the last stint
            // Decay the user's reward score until today
            _rewardScores[account] = calculateDecayedUserRewardScore(account);
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
            userRewardPerRewardScorePaid[account] = rewardPerRewardScoreStored;
        }
    }

    /*
    * @notice access control modifier for exchanger proxy
    */
    modifier onlyExchangerProxy() {
        _onlyExchangerProxy();
        _;
    }

    /*
    * @notice internal function used in the modifier with the same name to optimize bytecode
    */
    function _onlyExchangerProxy() internal {
        bool isEP = msg.sender == address(exchangerProxy);

        require(isEP);
    }

    /*
    * @notice access control modifier for rewardEscrow
    */
    modifier onlyRewardEscrow() {
        _onlyRewardEscrow();
        _;
    }

    /*
    * @notice internal function used in the modifier with the same name to optimize bytecode
    */
    function _onlyRewardEscrow() internal {
        bool isRE = msg.sender == address(rewardEscrow);

        require(isRE);
    }



    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event EscrowStaked(address account, uint256 amount);
    event EscrowUnstaked(address account, uint256 amount);
    event RewardEscrowUpdated(address account);
    event ExchangerProxyUpdated(address account);

    /* ========== PROXY FUNCTIONS ========== */
    
    /*
    * @notice Necessary override for Open Zeppelin UUPS proxy to make sure the admin logic is included
    */
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {

    }

    /*
    * @notice Getter function for current admin of stakingRewards Proxy
    */
    function getAdmin() external view returns(address) {
        return admin;
    }

    /*
    * @notice Getter function for current proposed new admin of stakingRewards Proxy
    */
    function getPendingAdmin() external view returns(address) {
        return pendingAdmin;
    }

    /*
    * @notice Propose a new admin for the staking rewards proxy (only the owner can do this)
    */
    function setPendingAdmin(address _newAdmin) external onlyOwner {
        pendingAdmin = _newAdmin;
    }

    /*
    * @notice Pending admin accepts the new role as admin
    */
    function pendingAdminAccept() external onlyPendingAdmin {
        admin = pendingAdmin;
    }

    /*
    * @notice access control modifier for admin
    */
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    /*
    * @notice internal function used in the modifier with the same name to optimize bytecode
    */
    function _onlyAdmin() internal {
        bool isAdmin = msg.sender == admin;

        require(isAdmin);
    }

    /*
    * @notice access control modifier for pending admin
    */
    modifier onlyPendingAdmin() {
        _onlyPendingAdmin();
        _;
    }

    /*
    * @notice internal function used in the modifier with the same name to optimize bytecode
    */
    function _onlyPendingAdmin() internal {
        bool isPendingAdmin = msg.sender == pendingAdmin;

        require(isPendingAdmin);
    }

}