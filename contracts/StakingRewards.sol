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
import "./RewardsDistributionRecipient.sol";
import "./Pausable.sol";

import "./RewardEscrow.sol";


contract StakingRewards is RewardsDistributionRecipient, ReentrancyGuardUpgradeable, Pausable, UUPSUpgradeable {
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

    // Tokens to stake and reward
    IERC20 public rewardsToken;
    IERC20 public stakingToken;
    // Time handling:
    // Time where new reward epoch finishes 
    uint256 public periodFinish;
    // Reward rate per second for next epoch
    uint256 public rewardRate;
    // Epoch default duration
    uint256 public rewardsDuration;
    // Last time an event altering the rewardscore
    uint256 public lastUpdateTimeRewardScore;
    // Last time an event altering the fees decay
    uint256 public lastUpdateTimeFeeDecay;
    // Last rewardRate per RewardScore
    uint256 public rewardPerRewardScoreStored;
    // Maximum amount of time to receive rewards for trading fees
    uint256 public feeRewardsDuration;

    
    // Save the latest reward per RewardScore applicable for each address
    mapping(address => uint256) public userRewardPerRewardScorePaid;
    // Save the latest reward per RewardScore applicable for each address
    mapping(address => uint256) public userLastFeeUpdate;
    // Rewards due to each account
    mapping(address => uint256) public rewards;

    // Total RewardsScore
    uint256 private _totalRewardScore;
    
    // Tokens escrowed for each address
    mapping(address => uint256) private _escrowedBalances;
    // Fees paid for each address
    mapping(address => uint256) private _feesPaid;
    // Decayed fees paid for each address
    mapping(address => uint256) private _decayedFees;
    // Save the latest total token to account for rewards (staked + escrowed rewards)
    mapping(address => uint256) private _totalBalances;
    // Save the latest total token to account for rewards (staked + escrowed rewards)
    mapping(address => uint256) private _rewardScores;
    
    // Minimum staked amount necessary to accumulate rewards
    uint256 private constant MIN_STAKE = 0;
    // Decay rate for fees paid (in USD per second)
    int256 private constant DECAY_RATE = 999000000000000000;

    uint256 private constant MAX_BPS = 10_000;
    uint256 private constant DECIMALS_DIFFERENCE = 1e50;
    // Needs to be int256 for power library, root to calculate is equal to 1/0.3
    int256 private constant WEIGHT_FEES = 3_333_333_333_333_333_333;
    // Needs to be int256 for power library, root to calculate is equal to 1/0.7
    int256 private constant WEIGHT_STAKING =1_428_571_428_571_428_571;

    /* ========== PROXY VARIABLES ========== */
    address private admin;
    
    /* ========== INITIALIZER ========== */

    function initialize(address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        address _rewardEscrow
    ) public initializer {
        __Pausable_init(_owner);

        __ReentrancyGuard_init();

        admin = _owner;

        periodFinish = 0;
        rewardRate = 0;
        rewardsDuration = 7 days;
        feeRewardsDuration = 365 days;

        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
        fixidity.init(18);

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
    /*
    Getter function for the escrowed balance of an account
    */
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

    function rewardPerRewardScore() public view returns (uint256) {
    /*
    Function calculating the state of reward to be delivered per unit of reward score before the new change
    takes place. Saved in userRewardPerRewardScorePaid and used later in function earned() to calculate the 
    extra rewards to add taking into account the reward conditions of the latest change and the current earned() 
    context
    returns: uint256 containing the new reward per rewardScore 
    */
        if (_totalRewardScore == 0) {
            return rewardPerRewardScoreStored;
        }
        // TODO: DIVIDE BY DR^(0.3*(block.timestamp - lastTimeUpdatedFees))
        return
            rewardPerRewardScoreStored.add(
                // lastTimeRewardApplicable().sub(lastUpdateTimeRewardScore).mul(rewardRate).mul(MAX_BPS).mul(DECIMALS_DIFFERENCE).div(_totalRewardScore).div(uint256(fixidity.power_any(DECAY_RATE, 300000000000000000 * int256(block.timestamp - lastUpdateTimeFeeDecay))))
                lastTimeRewardApplicable().sub(lastUpdateTimeRewardScore).mul(rewardRate).mul(MAX_BPS).mul(DECIMALS_DIFFERENCE).div(_totalRewardScore)
            );
    }

    function earned(address account) public view returns(uint256) {
    /*
    Function calculating the rewards earned by an account between the current call moment and the latest change in
    reward score. The function divides the reward score by the total amount, accounts for the changes between now and the 
    last changes (deducting userRewardPerRewardScorePaid) and adds the result to the existing rewards balance of the account
    returns: uint256 containing the total rewards due to account
    */
    // TODO: MULTIPLY REWARDSCORE[ACCOUNT] BY DR^(0.3*(block.timestamp - lastTimeUpdated[account]))
        uint256 tmpVar = 1;
        // if(userLastFeeUpdate[account] > 0) {
        //     tmpVar = uint256(fixidity.power_any(DECAY_RATE, 300000000000000000 * int256(block.timestamp - userLastFeeUpdate[account])));
        // }
        
        return _rewardScores[account].mul(tmpVar).mul(rewardPerRewardScore().sub(userRewardPerRewardScorePaid[account])).div(MAX_BPS).div(DECIMALS_DIFFERENCE).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) {
    /*
    Calculate the total rewards delivered in a specific duration, multiplying rewardRate x duration
    returns: uint256 containing the total rewards to be delivered
    */
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function updateTraderScore(address _trader, uint256 _newFeesPaid) external updateRewards(_trader) {
        /*
        Function called by the ExchangerProxy updating the fees paid by each account and the contribution
        to the total reward scores
        _trader: address, for which to update the score
        _feesPaid: uint256, total fees paid in this period
        returns: NA, updates the state mapping _traderScore
        */
        if(balanceOf(_trader) > MIN_STAKE){
            // TODO: CALCULATE TOTAL DECAYED FEES
            // TODO: UPDATE LAST UPDATED FEES
            userLastFeeUpdate[_trader] = block.timestamp;
            _feesPaid[_trader] = _feesPaid[_trader].add(_newFeesPaid);
            uint256 oldRewardScore = _rewardScores[_trader];
            uint256 newRewardScore = calculateRewardScore(_trader);
            _rewardScores[_trader] = newRewardScore;
            // TODO: DIVIDE BY DR^(0.3*(block.timestamp - lastTimeUpdatedFees)) oldRewardScore
            _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
        }
        
    }

    function calculateRewardScore(address _account) private view returns(uint256){
    /*
    Function updating and returning the reward score for a specific account
    _account: address to update the reward score for
    returns: uint256 containing the new reward score for _account
    */
        // TODO: USE DECAYED FEES
        uint256 newRewardScore = 0;
        // Handle case with 0 reward to avoid the library crashing
        if(_feesPaid[_account] > 0 && _totalBalances[_account] > 0) {
            newRewardScore = uint256(fixidity.root_any(int256(_totalBalances[_account]), WEIGHT_STAKING)).mul(uint256(fixidity.root_any(int256(_feesPaid[_account]), WEIGHT_FEES)));
        }
        return newRewardScore;
    }


    function stake(uint256 amount) external nonReentrant notPaused updateRewards(msg.sender) {
    /*
    Function staking the requested tokens by the user.
    _amount: uint256, containing the number of tokens to stake
    returns: NA
    */
        require(amount > 0, "Cannot stake 0");
        // Update caller balance
        _totalBalances[msg.sender] = _totalBalances[msg.sender].add(amount);
        uint256 oldRewardScore = _rewardScores[msg.sender];
        uint256 newRewardScore = calculateRewardScore(msg.sender);
        _rewardScores[msg.sender] = newRewardScore;
        // TODO: DIVIDE BY DR^(0.3*(block.timestamp - lastTimeUpdatedFees)) oldRewardScore
        _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
        stakingToken.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateRewards(msg.sender) {
    /*
    Function withdrawing the requested tokens by the user.
    _amount: uint256, containing the number of tokens to stake
    returns: NA
    */
        require(amount > 0, "Cannot withdraw 0");
        require(balanceOf(msg.sender) >= amount, "Amount required too high");
        // Update caller balance
        _totalBalances[msg.sender] = _totalBalances[msg.sender].sub(amount);
        uint256 oldRewardScore = _rewardScores[msg.sender];
        uint256 newRewardScore = calculateRewardScore(msg.sender);
        _rewardScores[msg.sender] = newRewardScore;
        // TODO: DIVIDE BY DR^(0.3*(block.timestamp - lastTimeUpdatedFees)) oldRewardScore
        _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
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
        _totalBalances[_account] = _totalBalances[_account].add(_amount);
        _escrowedBalances[_account] = _escrowedBalances[_account].add(_amount);
        uint256 oldRewardScore = _rewardScores[_account];
        uint256 newRewardScore = calculateRewardScore(_account);
        _rewardScores[_account] = newRewardScore;
        // TODO: DIVIDE BY DR^(0.3*(block.timestamp - lastTimeUpdatedFees)) oldRewardScore
        _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
        emit EscrowStaked(_account, _amount);
    }

    function unstakeEscrow(address _account, uint256 _amount) public nonReentrant onlyRewardEscrow updateRewards(_account) {
    /*
    Function called from RewardEscrow (vest) to deduct the escrowed tokens and not accumulate rewards
    _account: address escrowing the rewards
    _amount: uint256, amount escrowed
    */
        require(_escrowedBalances[_account] >= _amount, "Amount required too large");
        _totalBalances[_account] = _totalBalances[_account].sub(_amount);
        _escrowedBalances[_account] = _escrowedBalances[_account].sub(_amount);
        uint256 oldRewardScore = _rewardScores[_account];
        uint256 newRewardScore = calculateRewardScore(_account);
        _rewardScores[_account] = newRewardScore;
        // TODO: DIVIDE BY DR^(0.3*(block.timestamp - lastTimeUpdatedFees)) oldRewardScore
        _totalRewardScore = _totalRewardScore.sub(oldRewardScore).add(newRewardScore);
        emit EscrowUnstaked(_account, _amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateRewards(address(0)) override {
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
        } else {
            // Time to finish the previous reward epoch
            uint256 remaining = periodFinish.sub(block.timestamp);
            // Total rewardsa still to be delivered in previous epoch
            uint256 leftover = remaining.mul(rewardRate);
            // Formula: rewardRate = (sum of remaining rewards and new amount) / time
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardsToken.balanceOf(address(this));
        
        require(rewardRate <= balance.div(rewardsDuration), "Provided reward too high");

        // Time updates
        lastUpdateTimeRewardScore = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
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
        
        // Calculate the reward per unit of reward score applicable to the last stint of account
        rewardPerRewardScoreStored = rewardPerRewardScore();
        lastUpdateTimeFeeDecay = block.timestamp;
        // Calculate if the epoch is finished or not
        lastUpdateTimeRewardScore = lastTimeRewardApplicable();
        if (account != address(0)) {
            // Add the rewards added during the last stint
            rewards[account] = earned(account);
            userRewardPerRewardScorePaid[account] = rewardPerRewardScoreStored;
        }
        _;
    }

    modifier onlyRewardEscrow() {
        bool isRE = msg.sender == address(rewardEscrow);

        require(isRE, "Only the RewardEscrow contract can perform this action");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {

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

    /* ========== PROXY FUNCTIONS ========== */
    

    function getAdmin() public view returns(address) {
        return admin;
    }

    function setAdmin(address _newAdmin) public onlyOwner {
        admin = _newAdmin;
        // emit AdminChanged(msg.sender, _newAdmin);
    }

    modifier onlyAdmin() {
        bool isAdmin = msg.sender == admin;

        require(isAdmin, "Only the Admin address can perform this action");
        _;
    }

    /* ========== PROXY EVENTS ========== */
    // event AdminChanged(address owner, address newAdmin);

}