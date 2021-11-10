// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import necessary contracts for math operations and Token handling
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./libraries/FixidityLib.sol";
import "./libraries/ExponentLib.sol";
import "./libraries/LogarithmLib.sol";

// Inheritance
import "./Pausable.sol";
// Import RewardEscrow contract for Escrow interactions
import "./RewardEscrow.sol";


contract StakingRewards is ReentrancyGuardUpgradeable, Pausable, UUPSUpgradeable {
    /*
    StakingRewards contract for Kwenta responsible for:
    - Staking KWENTA tokens
    - Withdrawing KWENTA tokens
    - Updating staker and trader scores
    - Calculating and notifying rewards
    */
    using SafeMath for uint256;
    using SafeMath for int256;
    using FixidityLib for FixidityLib.Fixidity;
    using ExponentLib for FixidityLib.Fixidity;
    using LogarithmLib for FixidityLib.Fixidity;

    /* ========== STATE VARIABLES ========== */

    FixidityLib.Fixidity public fixidity;

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
    uint256 public lastUpdateTimeRewardScore;
    // Last rewardRate per RewardScore
    uint256 public rewardPerRewardScoreStored;
    // Last Update Time for staking Rewards
    uint256 public lastUpdateTime;
    // Last reward per token staked
    uint256 public rewardPerTokenStored;
    // Time to zero for decay rate
    uint256 public timeToZero;
    uint256 public rewardStartedTime;
    // Decay Rate variables
    uint256 public lastTotalSlope;

    // Mapping containing future decaying slopes of totalRewardScores
    mapping(uint256 => uint256) public slopeChanges;
    // Mapping containing future decaying slopes of each user's total rewards
    mapping(address => mapping(uint256 => uint256)) public userRewardScoreSlopeChanges;
    // Custom data structure to save (i) last state of user reward score, (ii) slope and (iii) updated time
    struct stateUser {
        uint lastRewardScore;
        uint lastSlope;
        uint lastUpdated;
    }
    // Mapping containing the last state of each user
    mapping(address => stateUser) public lastStateUser;

    
    // Save the latest reward per RewardScore applicable for each address (Trading Rewards)
    mapping(address => uint256) public userRewardPerRewardScorePaid;
    // Save the latest reward per Token applicable for each address (Staking Rewards)
    mapping(address => uint256) public userRewardPerTokenPaid;
    // Rewards due to each account
    mapping(address => uint256) public rewards;

    // Total RewardsScore
    uint256 private _totalRewardScore;
    // Total area under the decaying total reward score curve
    uint256 public _accumulatedTotalRewardScore;
    // Total tokens included in rewards (both staked and escrowed)
    uint256 public _totalSupply;
    
    // Tokens escrowed for each address
    mapping(address => uint256) private _escrowedBalances;
    // Fees paid for each address
    mapping(address => uint256) private _feesPaid;
    // Save the latest total token to account for rewards (staked + escrowed rewards)
    mapping(address => uint256) private _totalBalances;
    // Save the rewardScore per address
    mapping(address => uint256) private _rewardScores;
    // Total area under each user's reward score curve
    mapping(address => uint256) public _accumulatedRewardScores;

    
    // Minimum staked amount necessary to accumulate rewards
    uint256 private constant MIN_STAKE = 0;
    // Decimals calculations
    uint256 private constant MAX_BPS = 10_000;
    uint256 private constant DECIMALS_DIFFERENCE = 1e30;
    // Needs to be int256 for power library, root to calculate is equal to 0.7
    int256 private constant WEIGHT_FEES = 700_000_000_000_000_000;
    int256 private constant INVERSE_WEIGHT_FEES = 1_428_571_428_571_430_000;
    // Needs to be int256 for power library, root to calculate is equal to 0.3
    int256 private constant WEIGHT_STAKING = 300_000_000_000_000_000;
    // Division of rewards between staking and trading
    // TODO: Create getters and setters
    uint256 private constant PERCENTAGE_STAKING = 80;
    uint256 private constant PERCENTAGE_TRADING = 20;
    uint256 private constant DAY = 86_400;

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
    }

    /* ========== VIEWS ========== */

    function totalRewardScore() public view returns (uint256) {
    /*
    Getter function for the state variable _totalRewardScore
    */
        return _totalRewardScore;
    }

    function balanceOf(address account) public view returns (uint256) {
    /*
    Getter function for the staked balance of an account
    */
        return _totalBalances[account].sub(_escrowedBalances[account]);
    }

    function rewardScoreOf(address account) external view returns (uint256) {
    /*
    Getter function for the reward score of an account
    */
        return _rewardScores[account];
    }

    function totalBalanceOf(address account) external view returns (uint256) {
    /*
    Getter function for the total balances of an account (staked + escrowed rewards)
    */
        return _totalBalances[account];
    }

    function escrowedBalanceOf(address account) external view returns (uint256) {
    
    // Getter function for the escrowed balance of an account
    
        return _escrowedBalances[account];
    }

    function feesPaidBy(address account) external view returns (uint256) {
    /*
    Getter function for the state variable _feesPaid
    */
        return _feesPaid[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
    /*
    Calculate if we are still in the reward epoch or we reached periodFinish
    */
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRateStaking).mul(DECIMALS_DIFFERENCE).div(_totalSupply)
            );
    }

    function rewardPerRewardScore() public view returns (uint256) {
    /*
    Function calculating the state of reward to be delivered per unit of reward score before the new change
    takes place. Saved in userRewardPerRewardScorePaid and used later in function earned() to calculate the 
    extra rewards to add taking into account the reward conditions of the latest change and the current earned() 
    context
    returns: uint256 containing the new reward per rewardScore 
    */
        if (_accumulatedTotalRewardScore == 0) {
            return rewardPerRewardScoreStored;
        }
        return
            rewardPerRewardScoreStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTimeRewardScore).mul(rewardRateTrading).mul(MAX_BPS).mul(DECIMALS_DIFFERENCE).div(_accumulatedTotalRewardScore)
            );
    }

    function earned(address account) public returns(uint256) {
    /*
    Function calculating the rewards earned by an account between the current call moment and the latest change in
    reward score. The function divides the reward score by the total amount, accounts for the changes between now and the 
    last changes (deducting userRewardPerRewardScorePaid) and adds the result to the existing rewards balance of the account
    returns: uint256 containing the total rewards due to account
    */
        // rewardScores must be decayed!
        uint256 stakingRewards = _totalBalances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(DECIMALS_DIFFERENCE);
        uint256 tradingRewards = _accumulatedRewardScores[account].mul(rewardPerRewardScore().sub(userRewardPerRewardScorePaid[account])).div(MAX_BPS).div(DECIMALS_DIFFERENCE);
        return stakingRewards.add(tradingRewards).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
    /*
    Calculate the total rewards delivered in a specific duration, multiplying rewardRate x duration
    returns: uint256 containing the total rewards to be delivered
    */
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function updateTraderScore(address _trader, uint256 _newFeesPaid) external onlyExchangerProxy updateRewards(_trader) {
        /*
        Function called by the ExchangerProxy updating the fees paid by each account and the contribution
        to the total reward scores
        _trader: address, for which to update the score
        _feesPaid: uint256, total fees paid in this period
        returns: NA, updates the state mapping _traderScore
        */
        if(balanceOf(_trader) > MIN_STAKE){
            _feesPaid[_trader] += _newFeesPaid;
            uint256 oldRewardScore = _rewardScores[_trader];
            uint256 newRewardScore = calculateRewardScore(_trader, 0, _newFeesPaid);
            _rewardScores[_trader] = newRewardScore;
            _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
            lastUpdateTimeRewardScore = block.timestamp;
        }
        
    }

    function addUserSlopes(
        /*
        Function used to increase the already existing user slopes (due to a new staking)
        _account: address, for which to update the score
        additionalSlope: uint256, new slope in tokens per second to add
        updateTime: uint256, time of update
        _timeToZero: uint256, when will the slope alter the total
        returns: NA, updates the necessary mappings containing user and total slopes
        */
        address _account, 
        uint additionalSlope, 
        uint updateTime, 
        uint _timeToZero) internal returns(uint) {

        uint lastTime = updateTime + _timeToZero;

        for(uint i = updateTime; i <= lastTime; i+=DAY) {

            if(userRewardScoreSlopeChanges[_account][i] > 0){
                userRewardScoreSlopeChanges[_account][i] = userRewardScoreSlopeChanges[_account][i] + additionalSlope;
                slopeChanges[i] = slopeChanges[i] + additionalSlope;
            }
        }
    }
    function decreaseUserSlopes(
        /*
        Function used to decrease each user's slopes (due to a withdrawal of tokens)
        _account: address, for which to update the score
        removeSlope: uint256, new slope in tokens per second to substract
        updateTime: uint256, time of update
        _timeToZero: uint256, when will the slope alter the total
        returns: NA, updates the necessary mappings containing user and total slopes
        */
        address _account, 
        uint removeSlope, 
        uint updateTime, 
        uint _timeToZero) internal returns() {

        uint lastTime = updateTime + _timeToZero;

        for(uint i = updateTime; i <= lastTime; i+=DAY) {

            if(userRewardScoreSlopeChanges[_account][i] > 0){
                userRewardScoreSlopeChanges[_account][i] = userRewardScoreSlopeChanges[_account][i] - removeSlope;
                slopeChanges[i] = slopeChanges[i] - removeSlope;
            }
        }
    }

    function addSlope(address _account, uint slope, uint updateTime, uint _timeToZero) internal returns() {
        /*
        Function used to add a new slope change to the user and the decayed totalRewardScore calculation
        _account: address, for which to update the score
        slope: uint256, new slope in tokens per second to add
        updateTime: uint256, time of update
        _timeToZero: uint256, when will the slope alter the total
        returns: NA, updates the necessary mappings containing user and total slopes
        */
        userRewardScoreSlopeChanges[_account][updateTime + _timeToZero] += slope;
        slopeChanges[updateTime + _timeToZero] += slope;
    }

    function calculateDecayedTotalRewardScore() public returns(uint256) {
        /*
        Function used to total decayed reward score since the last update until the current time taking
        into account all slope changes happening in between
        returns: uint, new totalRewardScore
        */
        
        uint currentTime = (block.timestamp / DAY) * DAY;

        uint t = (lastUpdateTimeRewardScore / DAY ) * DAY;

        uint256 nEntries = (currentTime - t) / DAY;
        
        // If initial call or calling the same day it has already been calculated, return same state
        if(nEntries == 0 || t == 0) {
            return _totalRewardScore;
        // If more time than _timeToZero has passed, everything is decayed, return 0
        } else if(nEntries >= timeToZero / DAY) {
            lastTotalSlope = 0;
            _totalRewardScore = 0;
            return 0;
        }
        
        uint slope = lastTotalSlope;
        uint total = _totalRewardScore;
        uint nextSlopeChange = 0;
        
        // Iterate over the last days until reaching the current time, incrementing both the accumulatedTotalRewardScore
        // and updating the totalRewardScore
        for(uint i = t; i <= currentTime; i += DAY) {
            nextSlopeChange = slopeChanges[i];
            if(nextSlopeChange != 0 || i == currentTime) {
                total = (total - slope * (i - t));

                if (t < rewardStartedTime && i >= rewardStartedTime) {
                    _accumulatedTotalRewardScore = 0;
                    _accumulatedTotalRewardScore = total + slope * (Math.min(i, periodFinish) - rewardStartedTime) / 2;
                    _accumulatedTotalRewardScore *= (Math.min(i, periodFinish) - rewardStartedTime);
                } else if (periodFinish > 0) {
                    _accumulatedTotalRewardScore += total * (Math.min(i, periodFinish) - t) + slope * (Math.min(i, periodFinish) - t) * (Math.min(i, periodFinish) - t) / 2;
                }

                t = i;
                slope = slope - nextSlopeChange;
            }
        }


        if (slope == 0) {
            total = 0;
        }

        // Update the necessary state variables
        lastTotalSlope = slope;
        _totalRewardScore = total;

        return total;
    }

    function calculateDecayedUserRewardScore(address _account) public returns(uint256) {
        /*
        Function used a user's decayed reward score since the last update until the current time taking
        into account all slope changes happening in between
        returns: uint, new totalRewardScore
        */
        
        uint currentTime = (block.timestamp / DAY) * DAY;

        uint256 nEntries = (currentTime - lastStateUser[_account].lastUpdated) / DAY;
        
        // If initial call or calling the same day it has already been calculated, return same state
        if(nEntries == 0 || lastStateUser[_account].lastUpdated == 0) {
            return lastStateUser[_account].lastRewardScore;
        // If more time than _timeToZero has passed, everything is decayed, return 0
        } else if(nEntries >= timeToZero / DAY || lastStateUser[_account].lastRewardScore == 0) {
            lastStateUser[_account].lastSlope = 0;
            lastStateUser[_account].lastUpdated = currentTime;
            lastStateUser[_account].lastRewardScore = 0;
            return 0;
        } 
        
        uint t = lastStateUser[_account].lastUpdated;
        uint slope = lastStateUser[_account].lastSlope;
        uint total = lastStateUser[_account].lastRewardScore;
        uint nextSlopeChange = 0;

        // Iterate over the last days until reaching the current time, incrementing both the accumulatedTotalRewardScore
        // and updating the totalRewardScore
        for(uint i = t; i <= currentTime; i += DAY) {

            nextSlopeChange = userRewardScoreSlopeChanges[_account][i];
            if(nextSlopeChange != 0 || i == currentTime) {
                total = (total - slope * (i - t));

                if (t < rewardStartedTime && i >= rewardStartedTime) {
                    userRewardPerRewardScorePaid[_account] = 0;
                    _accumulatedRewardScores[_account] = total + slope * (Math.min(i, periodFinish) - rewardStartedTime) / 2;
                    _accumulatedRewardScores[_account] *= (Math.min(i, periodFinish) - rewardStartedTime);
                } else if (periodFinish > 0){
                    _accumulatedRewardScores[_account] += total * (Math.min(i, periodFinish) - t) + slope * (Math.min(t, periodFinish) - t) * (Math.min(t, periodFinish) - t) / 2;
                }

                t = i;
                slope = slope - nextSlopeChange;
            }

        }

        if (slope == 0) {
            total = 0;
        }

        // Update the necessary state variables
        lastStateUser[_account].lastSlope = slope;
        lastStateUser[_account].lastUpdated = currentTime;
        lastStateUser[_account].lastRewardScore = total;
        
        return total;
    }

    function calculateRewardScore(address _account, uint256 _prevStakingAmount, uint256 _newFees) private returns(uint256){
    /*
    Function updating and returning the reward score for a specific account
    _account: address to update the reward score for
    returns: uint256 containing the new reward score for _account
    */        
        uint256 newRewardScore = 0;
        uint roundedTime = (block.timestamp / DAY) * DAY;
        // Handle case with 0 reward to avoid the library crashing
        if((_totalBalances[_account] == 0) || (_totalBalances[_account] > 0 && lastStateUser[_account].lastRewardScore == 0 && _newFees == 0)) {
            lastStateUser[_account].lastSlope = 0;
            lastStateUser[_account].lastRewardScore = 0;
            lastStateUser[_account].lastUpdated = roundedTime;
            return 0;
        }

        // If the reward score already exists -> Update it instead of recalculating from scratch
        if(_rewardScores[_account] > 0 && _prevStakingAmount > 0) {
            // newFees = 0 means fees haven't changes, must be tokens
            // Perform a re-scaling of the previous reward score by: rewardScorePrev * (Nnew / Nprev) ^ 0.3
            if(_newFees == 0) {
                // Scale Ni + Scale all slopes in the future
                uint scalingFactor = uint256(fixidity.power_any(int256(_totalBalances[_account].mul(1e18).div(_prevStakingAmount)), WEIGHT_STAKING));
                newRewardScore = _rewardScores[_account].mul(scalingFactor).div(1e18);
                uint prevSlope = lastStateUser[_account].lastSlope;
                lastStateUser[_account].lastSlope = lastStateUser[_account].lastSlope.mul(scalingFactor).div(1e18);
                lastStateUser[_account].lastRewardScore = newRewardScore;
                lastStateUser[_account].lastUpdated = roundedTime;

                // If we have increased tokens, add slope, if not, substract
                if(_totalBalances[_account] > _prevStakingAmount) {
                    addUserSlopes(_account, lastStateUser[_account].lastSlope.sub(prevSlope), roundedTime, timeToZero);
                } else {
                    decreaseUserSlopes(_account, prevSlope.sub(lastStateUser[_account].lastSlope), roundedTime, timeToZero);
                }

                lastTotalSlope = lastTotalSlope.sub(prevSlope).add(lastStateUser[_account].lastSlope);

                return newRewardScore;
            } else {
                // New amount of fees, we calculate what are the decayed fees today, add the new amount and 
                // re-calculate rewardScore
                newRewardScore = _rewardScores[_account].div(uint256(fixidity.power_any(int256(_totalBalances[_account]), WEIGHT_STAKING)));
                newRewardScore = uint256(fixidity.power_any(int256(newRewardScore), INVERSE_WEIGHT_FEES)).add(_newFees);
                newRewardScore = uint256(fixidity.power_any(int256(_totalBalances[_account]), WEIGHT_STAKING)).mul(uint256(fixidity.power_any(int256(newRewardScore), WEIGHT_FEES)));

                // New fees mean new slopes to add as they have to decay later + increase today's slope
                uint additionalSlope = (newRewardScore - _rewardScores[_account]).div(timeToZero);
                addSlope(_account, additionalSlope, roundedTime, timeToZero);

                lastStateUser[_account].lastSlope = lastStateUser[_account].lastSlope.add(additionalSlope);
                lastStateUser[_account].lastRewardScore = newRewardScore;
                lastStateUser[_account].lastUpdated = roundedTime;

                lastTotalSlope = lastTotalSlope.add(additionalSlope);

                return newRewardScore;
            }
        }

        // We have to calculate the reward Score entirely
        newRewardScore = uint256(fixidity.power_any(int256(_totalBalances[_account]), WEIGHT_STAKING)).mul(uint256(fixidity.power_any(int256(_feesPaid[_account]), WEIGHT_FEES)));

        lastStateUser[_account].lastSlope = newRewardScore.div(timeToZero);
        lastStateUser[_account].lastRewardScore = newRewardScore;
        lastStateUser[_account].lastUpdated = roundedTime;

        addSlope(_account, lastStateUser[_account].lastSlope, roundedTime, timeToZero);

        lastTotalSlope = lastTotalSlope.add(lastStateUser[_account].lastSlope);

        return newRewardScore;
    }


    function stake(uint256 _amount) external nonReentrant notPaused updateRewards(msg.sender) {
    /*
    Function staking the requested tokens by the user.
    __amount: uint256, containing the number of tokens to stake
    returns: NA
    */
        require(_amount > 0, "Cannot stake 0");
        // Update caller balance
        uint256 oldRewardScore = _rewardScores[msg.sender];
        _totalBalances[msg.sender] = _totalBalances[msg.sender].add(_amount);
        _totalSupply = _totalSupply.add(_amount);
        uint256 newRewardScore = calculateRewardScore(msg.sender, _totalBalances[msg.sender].sub(_amount), 0);
        // oldRewardScore.mul(uint256(fixidity.power_any(int256(_totalBalances[msg.sender] / (_totalBalances[msg.sender].sub(_amount))), WEIGHT_STAKING)));
        _rewardScores[msg.sender] = newRewardScore;
        _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
        lastUpdateTimeRewardScore = lastTimeRewardApplicable();
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public nonReentrant updateRewards(msg.sender) {
    /*
    Function withdrawing the requested tokens by the user.
    __amount: uint256, containing the number of tokens to stake
    returns: NA
    */
        require(_amount > 0, "Cannot withdraw 0");
        require(balanceOf(msg.sender) >= _amount, "_Amount required too high");
        // Update caller balance
        uint256 oldRewardScore = _rewardScores[msg.sender];
        _totalBalances[msg.sender] = _totalBalances[msg.sender].sub(_amount);
        _totalSupply = _totalSupply.sub(_amount);
        uint256 newRewardScore = calculateRewardScore(msg.sender, _totalBalances[msg.sender].add(_amount), 0);
        _rewardScores[msg.sender] = newRewardScore;
        _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
        lastUpdateTimeRewardScore = lastTimeRewardApplicable();
        stakingToken.transfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function getReward() public updateRewards(msg.sender) nonReentrant {
    /*
    Function transferring the accumulated rewards for the caller address and updating the state mapping 
    containing the current rewards
    */
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            // Send the rewards to Escrow for 1 year
            rewardEscrow.appendVestingEntry(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
    /*
    Function handling the exit of the protocol of the caller:
    - Withdraws all tokens
    - Transfers all rewards to caller's address
    */
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function stakeEscrow(address _account, uint256 _amount) public onlyRewardEscrow updateRewards(_account) {
    /*
    Function called from RewardEscrow (append vesting entry) to accumulate escrowed tokens into rewards
    _account: address escrowing the rewards
    _amount: uint256, amount escrowed
    */
        uint256 oldRewardScore = _rewardScores[_account];
        _totalBalances[_account] = _totalBalances[_account].add(_amount);
        _totalSupply = _totalSupply.add(_amount);
        _escrowedBalances[_account] = _escrowedBalances[_account].add(_amount);
        uint256 newRewardScore = calculateRewardScore(_account, _totalBalances[_account].sub(_amount), 0);
        _rewardScores[_account] = newRewardScore;
        _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
        lastUpdateTimeRewardScore = lastTimeRewardApplicable();
        emit EscrowStaked(_account, _amount);
    }

    function unstakeEscrow(address _account, uint256 _amount) public nonReentrant onlyRewardEscrow updateRewards(_account) {
    /*
    Function called from RewardEscrow (vest) to deduct the escrowed tokens and not accumulate rewards
    _account: address escrowing the rewards
    _amount: uint256, amount escrowed
    */
        require(_escrowedBalances[_account] >= _amount, "Amount required too large");
        uint256 oldRewardScore = _rewardScores[_account];
        _totalBalances[_account] = _totalBalances[_account].sub(_amount);
        _totalSupply = _totalSupply.sub(_amount);
        _escrowedBalances[_account] = _escrowedBalances[_account].sub(_amount);
        uint256 newRewardScore = calculateRewardScore(_account, _totalBalances[_account].add(_amount), 0);
        _rewardScores[_account] = newRewardScore;
        _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
        lastUpdateTimeRewardScore = lastTimeRewardApplicable();
        emit EscrowUnstaked(_account, _amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external updateRewards(address(0)) {
    /*
    Function called to initialize a new reward distribution epoch, taking into account rewards still to be 
    delivered from a previous epoch and updating the lastUpdate and periodFinish state variables
    returns: NA
    */
    // If the previous epoch is finished, rewardRate calculation is straightforward
    // if not, add to the new amount to be delivered the remaining rewards still to be delivered by previous epoch
        if (block.timestamp >= periodFinish) {
            // Formula: rewardRate = total reward / time
            rewardRate = reward.div(rewardsDuration);
            rewardStartedTime = (block.timestamp / DAY) * DAY;
        } else {
            // Time to finish the previous reward epoch
            uint256 remaining = periodFinish.sub(block.timestamp);
            // Total rewardsa still to be delivered in previous epoch
            uint256 leftover = remaining.mul(rewardRate);
            // Formula: rewardRate = (sum of remaining rewards and new amount) / time
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }
        rewardRateStaking = rewardRate.mul(MAX_BPS).mul(PERCENTAGE_STAKING).div(MAX_BPS).div(100);
        rewardRateTrading = rewardRate.mul(MAX_BPS).mul(PERCENTAGE_TRADING).div(MAX_BPS).div(100);

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardsToken.balanceOf(address(this));
        
        require(rewardRate <= balance.div(rewardsDuration), "Provided reward too high");

        // Time updates
        lastUpdateTimeRewardScore = (block.timestamp / DAY) * DAY;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        _accumulatedTotalRewardScore = 0;
        rewardPerRewardScoreStored = 0;
        emit RewardAdded(reward);
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
        IERC20(tokenAddress).transfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardEscrow(address _rewardEscrow) external onlyOwner {
    /*
    Function available for the owner to change the rewardEscrow contract to use
    */
        rewardEscrow = RewardEscrow(_rewardEscrow);
        emit RewardEscrowUpdated(address(_rewardEscrow));
    }

    function setExchangerProxy(address _exchangerProxy) external onlyOwner {
    /*
    Function available for the owner to change the rewardEscrow contract to use
    */
        exchangerProxy = _exchangerProxy;
        emit ExchangerProxyUpdated(_exchangerProxy);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
    /*
    Function available for the owner to change the rewards duration via the state variable _rewardsDuration
    */
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /* ========== MODIFIERS ========== */

    modifier updateRewards(address account) {
    /*
    Modifier called each time an event changing the trading score is updated:
    - update trader score
    - notify reward amount
    The modifier saves the state of the reward rate per fee until this point for the specific 
    address to be able to calculate the marginal contribution to rewards afterwards and adds the accumulated
    rewards since the last change to the account rewards
    */  
        _updateRewards(account);
        _;
    }

    function _updateRewards(address account) internal {
        // Calculate the reward per unit of reward score applicable to the last stint of account
        rewardPerTokenStored = rewardPerToken();
        // Decay the total reward score sum and the total accumulated reward score
        calculateDecayedTotalRewardScore();
        rewardPerRewardScoreStored = rewardPerRewardScore();
        // Calculate if the epoch is finished or not
        lastUpdateTime = lastTimeRewardApplicable();
        lastUpdateTimeRewardScore = lastTimeRewardApplicable();
        if (account != address(0)) {
            // Add the rewards added during the last stint
            // Decay the user's reward score until today
            _rewardScores[account] = calculateDecayedUserRewardScore(account);
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
            userRewardPerRewardScorePaid[account] = rewardPerRewardScoreStored;
        }
    }

    modifier onlyExchangerProxy() {
        _onlyExchangerProxy();
        _;
    }

    function _onlyExchangerProxy() internal {
        bool isEP = msg.sender == address(exchangerProxy);

        require(isEP, "Only the Exchanger Proxy contract can perform this action");
    }

    modifier onlyRewardEscrow() {
        _onlyRewardEscrow();
        _;
    }

    function _onlyRewardEscrow() internal {
        bool isRE = msg.sender == address(rewardEscrow);

        require(isRE, "Only the RewardEscrow contract can perform this action");
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
    
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {

    }

    function getAdmin() public view returns(address) {
        return admin;
    }

    function getPendingAdmin() public view returns(address) {
        return pendingAdmin;
    }

    function setPendingAdmin(address _newAdmin) public onlyOwner {
        pendingAdmin = _newAdmin;
    }

    function pendingAdminAccept() public onlyPendingAdmin {
        admin = pendingAdmin;
    }

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyAdmin() internal {
        bool isAdmin = msg.sender == admin;

        require(isAdmin, "Only the Admin address can perform this action");
    }

    modifier onlyPendingAdmin() {
        _onlyPendingAdmin();
        _;
    }

    function _onlyPendingAdmin() internal {
        bool isPendingAdmin = msg.sender == pendingAdmin;

        require(isPendingAdmin, "Only the pending admin address can perform this action");
    }

}