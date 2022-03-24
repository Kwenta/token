// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import necessary contracts for math operations and Token handling
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./libraries/FixidityLib.sol";
import "./libraries/ExponentLib.sol";
import "./libraries/LogarithmLib.sol";
import "./interfaces/IStakingRewards.sol";
// Import SupplySchedule interface for access control of setRewardNEpochs
import "./interfaces/ISupplySchedule.sol";

// Inheritance
import "./utils/Pausable.sol";
// Import RewardEscrow contract for Escrow interactions
import "./RewardEscrow.sol";

/*
    StakingRewards contract for Kwenta responsible for:
    - Staking KWENTA tokens
    - Withdrawing KWENTA tokens
    - Updating staker and trader scores
    - Calculating and notifying rewards
*/
contract StakingRewards is IStakingRewards, ReentrancyGuardUpgradeable, Pausable, UUPSUpgradeable {
    using FixidityLib for FixidityLib.Fixidity;
    using ExponentLib for FixidityLib.Fixidity;

    /* ========== STATE VARIABLES ========== */

    FixidityLib.Fixidity private fixidity;

    // Reward Escrow
    RewardEscrow public rewardEscrow;

    // Reward Escrow
    ISupplySchedule public supplySchedule;

    // ExchangerProxy
    address private exchangerProxy;

    // Tokens to stake and reward
    IERC20 public override rewardsToken;
    IERC20 public stakingToken;
    // Time handling:
    // Time where new reward epoch finishes 
    uint256 public periodFinish;
    uint256 public weeklyStartRewards;
    // Reward rate per second for next epoch
    uint256 public rewardRate;
    uint256 public rewardRateStaking;
    uint256 public rewardRateTrading;
    // Epoch default duration
    uint256 public rewardsDuration;
    // Last Update Time for staking Rewards
    uint256 private lastUpdateTime;
    // Last reward per token staked
    uint256 private rewardPerTokenStored;
    uint256 public currentEpoch;
    
    // Save the date of the latest interaction for each address (Trading Rewards)
    mapping(address => uint256) private lastTradeUserEpoch;
    // Save the rewardPerRewardScore of each epoch for backward reward calculation
    mapping(uint256 => uint256) private epochRewardPerRewardScore;
    // Save the latest reward per Token applicable for each address (Staking Rewards)
    mapping(address => uint256) private userRewardPerTokenPaid;
    // Rewards due to each account
    mapping(address => uint256) public rewards;

    // Total RewardsScore
    uint256 private _totalRewardScore;
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
    // Division of rewards between staking and trading
    uint256 public PERCENTAGE_STAKING;
    uint256 public PERCENTAGE_TRADING;
    
    // Decimals calculations
    uint256 private constant MAX_BPS = 10_000;
    uint256 private constant DECIMALS_DIFFERENCE = 1e30;
    // Constant to return the reward scores with the correct decimal precision
    uint256 private constant TOKEN_DECIMALS = 1e18;
    // Needs to be int256 for power library, root to calculate is equal to 0.7
    int256 public WEIGHT_FEES;
    // Needs to be int256 for power library, root to calculate is equal to 0.3
    int256 public WEIGHT_STAKING;
    // Time constants
    uint256 private constant DAY = 1 days;
    uint256 private constant WEEK = 7 days;

    uint256 public constant STAKING_SAFETY_MINIMUM = 1e4;
    uint256 public constant FEES_PAID_SAFETY_MINIMUM = 1e12;

    /* ========== PROXY VARIABLES ========== */
    address private admin;
    address private pendingAdmin;
    
    /* ========== INITIALIZER ========== */
    function initialize(
        address _owner,
        address _rewardsToken,
        address _stakingToken,
        address _rewardEscrow,
        address _supplySchedule,
        uint256 _weeklyStartRewards
    ) public initializer {
        __Pausable_init(_owner);

        __ReentrancyGuard_init();

        admin = _owner;

        periodFinish = 0;
        rewardRate = 0;
        rewardsDuration = 7 days;

        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        fixidity.init(18);

        rewardEscrow = RewardEscrow(_rewardEscrow);
        supplySchedule = ISupplySchedule(_supplySchedule);

        PERCENTAGE_STAKING = 8_000;
        PERCENTAGE_TRADING = 2_000;

        WEIGHT_STAKING = 3e17;
        WEIGHT_FEES = 7e17;

        weeklyStartRewards = _weeklyStartRewards;
    }

    /* ========== VIEWS ========== */

    /*
     * @notice Getter function for the state variable _totalRewardScore
     * Divided by 1e18 as during the calculation we are multiplying two 18 decimal numbers, ending up with 
     * a 36 precision number. To avoid losing any precision by scaling it down during internal calculations,
     * we only scale it down for the getters
     * @return sum of all rewardScores
     */
    function totalRewardScore() override public view returns (uint256) {
        return _totalRewardScore / TOKEN_DECIMALS;
    }

    /*
     * @notice Getter function for the staked balance of an account
     * @param account address to check token balance of
     * @return token balance of specified account
     */
    function stakedBalanceOf(address account) override public view returns (uint256) {
        return _totalBalances[account] - _escrowedBalances[account];
    }

    /*
     * @notice Getter function for the reward score of an account
     * Divided by 1e18 as during the calculation we are multiplying two 18 decimal numbers, ending up with 
     * a 36 precision number. To avoid losing any precision by scaling it down during internal calculations,
     * we only scale it down for the getters
     * @param account address to check the reward score of
     * @return reward score of specified account
     */
    function rewardScoreOf(address account) override external view returns (uint256) {
        return _rewardScores[account] / TOKEN_DECIMALS;
    }

    /*
     * @notice Getter function for the total balances of an account (staked + escrowed rewards)
     * @param account address to check the total balance of
     * @return total balance of specified account
     */
    function totalBalanceOf(address account) override external view returns (uint256) {
        return _totalBalances[account];
    }

    /*
     * @notice Getter function for the escrowed balance of an account
     * @param account address to check the escrowed balance of
     * @return escrowed balance of specified account
     */
    function escrowedBalanceOf(address account) override external view returns (uint256) {
        return _escrowedBalances[account];
    }

    /*
     * @notice Getter function for the reward per reward score of a past epoch
     * @param id of the week to get the reward
     * @return reward per reward score of specified week
     */
    function rewardPerRewardScoreOfEpoch(uint256 _epoch) override external view returns (uint256) {
        return epochRewardPerRewardScore[_epoch];
    }

    /*
     * @notice Getter function for the total fees paid by an account
     * @param account address to check the fees balance of
     * @return fees of specified account
     */
    function feesPaidBy(address account) override external view returns (uint256) {
        return _feesPaid[account];
    }

    /*
     * @notice Calculate if we are still in the reward epoch or we reached periodFinish
     * @return Max date to sum rewards, either now or period finish
     */
    function lastTimeRewardApplicable() override public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    /*
     * @notice Calculate the reward distribution per token based on the time elapsed and current value of totalSupply
     * @return corresponding reward per token stored
     */
    function rewardPerToken() override public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (
                (lastTimeRewardApplicable() - lastUpdateTime) * rewardRateStaking * DECIMALS_DIFFERENCE / _totalSupply
            );
    }

    /*
     * @notice Function calculating the rewards earned by an account between the current call moment and the latest change in
     * reward score. The function divides the reward score by the total amount, accounts for the changes between now and the 
     * last changes (deducting userRewardPerRewardScorePaid) and adds the result to the existing rewards balance of the account
     * @param account to calculate the earned rewards
     * @return uint256 containing the total rewards due to account
     */
    function earned(address account) override public view returns(uint256) {
        uint256 stakingRewards = _totalBalances[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / DECIMALS_DIFFERENCE;
        uint256 tradingRewards = 0;
        if(lastTradeUserEpoch[account] < currentEpoch) {
            tradingRewards = _rewardScores[account] * epochRewardPerRewardScore[lastTradeUserEpoch[account]] / DECIMALS_DIFFERENCE;
        }
        return stakingRewards + tradingRewards + rewards[account];
    }

    /*
     * @notice Calculate the total rewards delivered in a specific duration, multiplying rewardRate x duration
     * @return uint256 containing the total rewards to be delivered
     */
    function getRewardForDuration() override external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /**
     * @notice Calculate the reward epoch for a specific date, taking into account the day they start
     * @param _date to calculate the reward epoch for
     * @ return uint256 containing the date of the start of the epoch
     */
    function getEpochForDate(uint256 _date) internal view returns(uint256) {
        _date = (_date / DAY) * DAY;
        uint256 naturalEpoch = (_date / WEEK) * WEEK;

        if(_date - naturalEpoch >= (7-weeklyStartRewards)*DAY) {
            return naturalEpoch + WEEK - weeklyStartRewards*DAY;
        } else {
            return naturalEpoch - weeklyStartRewards*DAY;
        }

    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Set the weights for the reward score formula
     * @dev Only the owner can use this function and parameters should be in Units (100% = 1e18)
     * @param _weightStaking the weight for tokens staked
     * @param _weightFees the weight of fees paid in the epoch
     */
    function setWeightsRewardScore(int256 _weightStaking, int256 _weightFees) override external onlyOwner {
        require(_weightStaking + _weightFees == 1e18);
        WEIGHT_STAKING = _weightStaking;
        WEIGHT_FEES = _weightFees;
    }

    /**
     * @notice Set the % distribution between staking and trading
     * @dev Only the owner can use this function and parameters should be in base 10_000 (80% = 8_000)
     * @param _percentageStaking the % of rewards to distribute to staking scores
     * @param _percentageTrading the % of rewards to distribute to reward scores
     */
    function setPercentageRewards(uint256 _percentageStaking, uint256 _percentageTrading) override external onlyOwner {
        require(_percentageTrading + _percentageStaking == 10_000);
        PERCENTAGE_STAKING = _percentageStaking;
        PERCENTAGE_TRADING = _percentageTrading;
    }

    /**
     * @notice Set the day of the week the reward epochs start
     * @dev As UNIX times started on a Thursday (January 1st 1970), shift n days as necessary, e.g. to start
     * on a Monday go 3 days prior (Wednesday, Tuesday, Monday), the remaining options are:
     * Friday: 6
     * Saturday: 5
     * Sunday: 4 
     * Monday: 3
     * Tuesday: 2
     * Wednesday: 1
     * Thursday: 0
     * @param newWeeklyStart the number of days to shift
     */
    function setWeeklyStartRewards(uint256 newWeeklyStart) external onlyOwner {
        require(newWeeklyStart < 7);
        weeklyStartRewards = newWeeklyStart;
    }

    /**
     * @notice If this is the first interaction with the contract in a new Epoch, save the rewardPerRewardScore
     * in the epochs mapping
     */
    function updateRewardEpoch() internal {
        // Dividing by week to get the last batch of 7 days, as UNIX started in 1970/01/01 (Thursday), we
        // go back 3 days to start a Monday
        uint256 newEpoch = getEpochForDate(block.timestamp);

        if(newEpoch > currentEpoch) {
            // Save rewardRateTrading * WEEK / _totalRewardScore to epoch mapping
            if(_totalRewardScore > 0 && currentEpoch < getEpochForDate(periodFinish)) {
                epochRewardPerRewardScore[currentEpoch] = rewardRateTrading * WEEK * DECIMALS_DIFFERENCE / _totalRewardScore;
            }
            _totalRewardScore = 0;
            currentEpoch = newEpoch;
        }

    }

    /*
     * @notice Function called by the ExchangerProxy updating the fees paid by each account and the contribution
     * to the total reward scores
     * @param _trader: address, for which to update the score
     * @param _feesPaid: uint256, total fees paid in this period
     */
    function updateTraderScore(address _trader, uint256 _newFeesPaid) override external onlyExchangerProxy updateRewards(_trader) {
        uint256 oldRewardScore = _rewardScores[_trader];
        if (lastTradeUserEpoch[_trader] < currentEpoch) {
            _feesPaid[_trader] = _newFeesPaid;
            lastTradeUserEpoch[_trader] = currentEpoch;
            oldRewardScore = 0;
        } else {
            _feesPaid[_trader] += _newFeesPaid;
        }
        updateRewardScore(_trader, oldRewardScore);
    }

    /*
     * @notice update the reward score:
     * - if there hasn´t been a trade in the currentEpoch, return 0
     * - if there has, update the reward score
     * @param _account, the user to update the reward score to
     */
    function updateRewardScore(address _account, uint256 _oldRewardScore) internal {
        // Prevent any staking balance change from falling within the danger threshold
        require(_totalBalances[_account] == 0 || _totalBalances[_account] >= STAKING_SAFETY_MINIMUM, "STAKING_SAFETY_MINIMUM");
        // Prevent any fees paid change from falling witihin the danger threshold
        require(_feesPaid[_account] == 0 || _feesPaid[_account] >= FEES_PAID_SAFETY_MINIMUM, "FEES_PAID_SAFETY_MINIMUM");
        
        uint256 newRewardScore = 0;
        if((lastTradeUserEpoch[_account] == currentEpoch) && (_totalBalances[_account] > 0)) {
            newRewardScore = uint256(fixidity.power_any(int256(_totalBalances[_account]), WEIGHT_STAKING)) * (uint256(fixidity.power_any(int256(_feesPaid[_account]), WEIGHT_FEES)));
        }

        if(lastTradeUserEpoch[_account] < currentEpoch) {
            _oldRewardScore = 0;
        }

        _rewardScores[_account] = newRewardScore;
        _totalRewardScore = _totalRewardScore  - _oldRewardScore + newRewardScore;

    }


    /*
     * @notice Function staking the requested tokens by the user.
     * @param _amount: uint256, containing the number of tokens to stake
     */
    function stake(uint256 _amount) override external nonReentrant notPaused updateRewards(msg.sender) {
        require(_amount > 0);
        // Update caller balance
        _totalBalances[msg.sender] += _amount;
        _totalSupply += _amount;
        updateRewardScore(msg.sender, _rewardScores[msg.sender]);
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    /*
     * @notice Function withdrawing the requested tokens by the user.
     * @param _amount: uint256, containing the number of tokens to stake
     */
    function withdraw(uint256 _amount) override public nonReentrant updateRewards(msg.sender) {
        require(_amount > 0, "Cannot withdraw 0");
        require(stakedBalanceOf(msg.sender) >= _amount);
        // Update caller balance
        _totalBalances[msg.sender] -= _amount;
        _totalSupply -=  _amount;
        updateRewardScore(msg.sender, _rewardScores[msg.sender]);
        stakingToken.transfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    /*
     * @notice Function transferring the accumulated rewards for the caller address and updating the state mapping 
     * containing the current rewards
     */
    function getReward() override public updateRewards(msg.sender) nonReentrant {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            
            // Send the rewards to Escrow for 1 year
            stakingToken.transfer(address(rewardEscrow), reward);
            rewardEscrow.appendVestingEntry(msg.sender, reward, 52 weeks);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /*
     * @notice Function handling the exit of the protocol of the caller:
     * - Withdraws all tokens
     * - Transfers all rewards to caller's address
     */
    function exit() override external {
        withdraw(stakedBalanceOf(msg.sender));
        getReward();
    }

    /*
     * @notice Function called from RewardEscrow to accumulate escrowed tokens into rewards
     * @param _account: address escrowing the rewards
     * @param _amount: uint256, amount escrowed
     */
    function stakeEscrow(address _account, uint256 _amount) override public onlyRewardEscrow updateRewards(_account) {
        _totalBalances[_account] +=  _amount;
        _totalSupply +=  _amount;
        _escrowedBalances[_account] +=  _amount;
        updateRewardScore(msg.sender, _rewardScores[msg.sender]);
        emit EscrowStaked(_account, _amount);
    }

    /*
     * @notice Function called from RewardEscrow (vest) to deduct the escrowed tokens and not accumulate rewards
     * @param _account: address escrowing the rewards
     * @param _amount: uint256, amount escrowed
     */
    function unstakeEscrow(address _account, uint256 _amount) override public nonReentrant onlyRewardEscrow updateRewards(_account) {
        require(_escrowedBalances[_account] >= _amount);
        _totalBalances[_account] -= _amount;
        _totalSupply -= _amount;
        _escrowedBalances[_account] -= _amount;
        updateRewardScore(msg.sender, _rewardScores[msg.sender]);
        emit EscrowUnstaked(_account, _amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /*
     * @notice Function used to set the rewards for the next N epochs
     * @param rewards, total amount to distribute
     * @param nEpochs, number of weeks with rewards
     */  
    function setRewardNEpochs(uint256 reward, uint256 nEpochs) override external onlySupplySchedule updateRewards(address(0)) {
        rewardRate = reward / nEpochs / WEEK;
        rewardRateStaking = rewardRate * PERCENTAGE_STAKING / MAX_BPS;
        rewardRateTrading = rewardRate * PERCENTAGE_TRADING / MAX_BPS;

        uint256 balance = rewardsToken.balanceOf(address(this));
        require(reward <= balance);
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration * nEpochs;
        emit RewardAdded(reward, nEpochs);
    }

    // @notice Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(rewardsToken));
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
    function _updateRewards(address account) internal {
        // Calculate the reward per unit of reward score applicable to the last stint of account
        rewardPerTokenStored = rewardPerToken();
        // Calculate if the epoch is finished or not
        lastUpdateTime = lastTimeRewardApplicable();
        updateRewardEpoch();
        if (account != address(0)) {
            // Add the rewards added during the last stint
            rewards[account] = earned(account);
            // Reset the reward score as we have already paid these trading rewards
            if (lastTradeUserEpoch[msg.sender] < currentEpoch) {
                _rewardScores[msg.sender] = 0;
            }
            // Reset the reward per token as we have already paid these staking rewards
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
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
    function _onlyExchangerProxy() internal view {
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
    function _onlyRewardEscrow() internal view {
        bool isRE = msg.sender == address(rewardEscrow);

        require(isRE);
    }

    /*
     * @notice access control modifier for rewardEscrow
     */
    modifier onlySupplySchedule() {
        _onlySupplySchedule();
        _;
    }

    /*
     * @notice internal function used in the modifier with the same name to optimize bytecode
     */
    function _onlySupplySchedule() internal view {
        bool isSS = msg.sender == address(supplySchedule);

        require(isSS);
    }



    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward, uint256 nEpochs);
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
        pendingAdmin = address(0);
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
    function _onlyAdmin() internal view {
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
    function _onlyPendingAdmin() internal view {
        bool isPendingAdmin = msg.sender == pendingAdmin;

        require(isPendingAdmin);
    }

}