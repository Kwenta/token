pragma solidity ^0.8.0;

// Inheritance
import "./Owned.sol";
import "./interfaces/ISupplySchedule.sol";

// Libraries
import "./SafeDecimalMath.sol";
import "./libraries/Math.sol";

// Internal references
// import "./Proxy.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IKwenta.sol";
import './interfaces/IStakingRewards.sol';

// https://docs.synthetix.io/contracts/source/contracts/supplyschedule
contract SupplySchedule is Owned, ISupplySchedule {
    using SafeMath for uint;
    using SafeDecimalMath for uint;
    using Math for uint;

    IKwenta public kwenta;

    // Time of the last inflation supply mint event
    uint public lastMintEvent;

    // Counter for number of weeks since the start of supply inflation
    uint public weekCounter;

    // The number of KWENTA rewarded to the caller of Kwenta.mint()
    uint public minterReward = 1e18;

    uint public constant INITIAL_SUPPLY = 313373e18;

    // Initial Supply * 240% Initial Inflation Rate / 52 weeks.
    uint public constant INITIAL_WEEKLY_SUPPLY = INITIAL_SUPPLY * 240 / 100 / 52;

    // Max KWENTA rewards for minter
    uint public constant MAX_MINTER_REWARD = 20 * 1e18;

    // How long each inflation period is before mint can be called
    uint public constant MINT_PERIOD_DURATION = 1 weeks;

    uint public INFLATION_START_DATE;
    uint public constant MINT_BUFFER = 1 days;
    uint8 public constant SUPPLY_DECAY_START = 2; // Supply decay starts on the 2nd week of rewards
    uint8 public constant SUPPLY_DECAY_END = 208; // Inclusive of SUPPLY_DECAY_END week.

    // Weekly percentage decay of inflationary supply
    uint public constant DECAY_RATE = 20500000000000000; // 2.05% weekly

    // Percentage growth of terminal supply per annum
    uint public constant TERMINAL_SUPPLY_RATE_ANNUAL = 10000000000000000; // 1.0% pa

    uint public treasuryDiversion = 2000; // 20% to treasury

    address immutable treasuryDAO;
    IStakingRewards public stakingRewards;

    constructor(
        address _owner,
        address _treasuryDAO,
        address _stakingRewards
    ) Owned(_owner) {
        treasuryDAO = _treasuryDAO;
        stakingRewards = IStakingRewards(_stakingRewards);

        INFLATION_START_DATE = block.timestamp; //Inflation starts as soon as the contract is deployed.
        lastMintEvent = block.timestamp;
        weekCounter = 0;
    }

    // ========== VIEWS ==========

    /**
     * @return The amount of KWENTA mintable for the inflationary supply
     */
    function mintableSupply() override public view returns (uint) {
        uint totalAmount;

        if (!isMintable()) {
            return totalAmount;
        }

        uint remainingWeeksToMint = weeksSinceLastIssuance();

        uint currentWeek = weekCounter;

        // Calculate total mintable supply from exponential decay function
        // The decay function stops after week 234
        while (remainingWeeksToMint > 0) {
            currentWeek++;

            if (currentWeek < SUPPLY_DECAY_START) {
                // If current week is before supply decay we add initial supply to mintableSupply
                totalAmount = totalAmount.add(INITIAL_WEEKLY_SUPPLY);
                remainingWeeksToMint--;
            } else if (currentWeek <= SUPPLY_DECAY_END) {
                // if current week before supply decay ends we add the new supply for the week
                // diff between current week and (supply decay start week - 1)
                uint decayCount = currentWeek.sub(SUPPLY_DECAY_START - 1);

                totalAmount = totalAmount.add(tokenDecaySupplyForWeek(decayCount));
                remainingWeeksToMint--;
            } else {
                // Terminal supply is calculated on the total supply of Kwenta including any new supply
                // We can compound the remaining week's supply at the fixed terminal rate
                uint totalSupply = IERC20(kwenta).totalSupply();
                uint currentTotalSupply = totalSupply.add(totalAmount);

                totalAmount = totalAmount.add(terminalInflationSupply(currentTotalSupply, remainingWeeksToMint));
                remainingWeeksToMint = 0;
            }
        }

        return totalAmount;
    }

    /**
     * @return A unit amount of decaying inflationary supply from the INITIAL_WEEKLY_SUPPLY
     * @dev New token supply reduces by the decay rate each week calculated as supply = INITIAL_WEEKLY_SUPPLY * ()
     */
    function tokenDecaySupplyForWeek(uint counter) public pure returns (uint) {
        // Apply exponential decay function to number of weeks since
        // start of inflation smoothing to calculate diminishing supply for the week.
        uint effectiveDecay = (SafeDecimalMath.unit().sub(DECAY_RATE)).powDecimal(counter);
        uint supplyForWeek = INITIAL_WEEKLY_SUPPLY.multiplyDecimal(effectiveDecay);

        return supplyForWeek;
    }

    /**
     * @return A unit amount of terminal inflation supply
     * @dev Weekly compound rate based on number of weeks
     */
    function terminalInflationSupply(uint totalSupply, uint numOfWeeks) public pure returns (uint) {
        // rate = (1 + weekly rate) ^ num of weeks
        uint effectiveCompoundRate = SafeDecimalMath.unit().add(TERMINAL_SUPPLY_RATE_ANNUAL.div(52)).powDecimal(numOfWeeks);

        // return Supply * (effectiveRate - 1) for extra supply to issue based on number of weeks
        return totalSupply.multiplyDecimal(effectiveCompoundRate.sub(SafeDecimalMath.unit()));
    }

    /**
     * @dev Take timeDiff in seconds (Dividend) and MINT_PERIOD_DURATION as (Divisor)
     * @return Calculate the numberOfWeeks since last mint rounded down to 1 week
     */
    function weeksSinceLastIssuance() public view returns (uint) {
        // Get weeks since lastMintEvent
        // If lastMintEvent not set or 0, then start from inflation start date.
        uint timeDiff = lastMintEvent > 0 ? block.timestamp.sub(lastMintEvent) : block.timestamp.sub(INFLATION_START_DATE);
        return timeDiff.div(MINT_PERIOD_DURATION);
    }

    /**
     * @return boolean whether the MINT_PERIOD_DURATION (7 days)
     * has passed since the lastMintEvent.
     * */
    function isMintable() override public view returns (bool) {
        if (block.timestamp - lastMintEvent > MINT_PERIOD_DURATION) {
            return true;
        }
        return false;
    }

    // ========== MUTATIVE FUNCTIONS ==========

    /**
     * @notice Record the mint event from Kwenta by incrementing the inflation
     * week counter for the number of weeks minted (probabaly always 1)
     * and store the time of the event.
     * @param supplyMinted the amount of KWENTA the total supply was inflated by.
     * */
    function recordMintEvent(uint supplyMinted) internal returns (bool) {
        uint numberOfWeeksIssued = weeksSinceLastIssuance();

        // add number of weeks minted to weekCounter
        weekCounter = weekCounter.add(numberOfWeeksIssued);

        // Update mint event to latest week issued (start date + number of weeks issued * seconds in week)
        // 1 day time buffer is added so inflation is minted after feePeriod closes
        lastMintEvent = INFLATION_START_DATE.add(weekCounter.mul(MINT_PERIOD_DURATION)).add(MINT_BUFFER);

        emit SupplyMinted(supplyMinted, numberOfWeeksIssued, lastMintEvent, block.timestamp);
        return true;
    }

    /**
     * @notice Sets the reward amount of KWENTA for the caller of the public
     * function Kwenta.mint().
     * This incentivises anyone to mint the inflationary supply and the mintr
     * Reward will be deducted from the inflationary supply and sent to the caller.
     * @param amount the amount of KWENTA to reward the minter.
     * */
    function setMinterReward(uint amount) external onlyOwner {
        require(amount <= MAX_MINTER_REWARD, "Reward cannot exceed max minter reward");
        minterReward = amount;
        emit MinterRewardUpdated(minterReward);
    }

    /**
     * @notice Mints new inflationary supply weekly
     * New KWENTA is distributed between the minter, treasury, and StakingRewards contract
     * */
    function mint() override external {
        require(address(stakingRewards) != address(0), "Staking rewards not set");

        uint supplyToMint = mintableSupply();
        require(supplyToMint > 0, "No supply is mintable");

        // record minting event before mutation to token supply
        recordMintEvent(supplyToMint);

        uint amountToDistribute = supplyToMint - minterReward;
        uint amountToTreasury = amountToDistribute * treasuryDiversion / 10000;
        uint amountToStakingRewards = amountToDistribute - amountToTreasury;

        kwenta.mint(treasuryDAO, amountToTreasury);
        kwenta.mint(address(stakingRewards), amountToStakingRewards);
        stakingRewards.setRewardNEpochs(amountToStakingRewards, 1);
        kwenta.mint(msg.sender, minterReward);
    }

    // ========== SETTERS ========== */

    /**
     * @notice Set the Kwenta should it ever change.
     * SupplySchedule requires Kwenta address as it has the authority
     * to record mint event.
     * */
    function setKwenta(IKwenta _kwenta) external onlyOwner {
        require(address(_kwenta) != address(0), "Address cannot be 0");
        kwenta = _kwenta;
        emit KwentaUpdated(address(kwenta));
    }

    function setTreasuryDiversion(uint _treasuryDiversion) override public onlyOwner {
        require(_treasuryDiversion < 10000, "Represented in basis points");
        treasuryDiversion = _treasuryDiversion;
    }

    function setStakingRewards(address _stakingRewards) override external onlyOwner {
        stakingRewards = IStakingRewards(_stakingRewards);
    }

    // ========== MODIFIERS ==========

    /**
     * @notice Only the Kwenta contract is authorised to call this function
     * */
    modifier onlyKwenta() {
        require(
            msg.sender == address(kwenta),
            "Only the kwenta contract can perform this action"
        );
        _;
    }

    /* ========== EVENTS ========== */
    /**
     * @notice Emitted when the inflationary supply is minted
     * */
    event SupplyMinted(uint supplyMinted, uint numberOfWeeksIssued, uint lastMintEvent, uint timestamp);

    /**
     * @notice Emitted when the KWENTA minter reward amount is updated
     * */
    event MinterRewardUpdated(uint newRewardAmount);

    /**
     * @notice Emitted when setKwenta is called changing the Kwenta Proxy address
     * */
    event KwentaUpdated(address newAddress);
}