# Kwenta Token System

This is the main repository for the Kwenta token and respective system contracts (staking, escrow, distribution, etc..). 

- See [KIP-4](https://kips.kwenta.io/kips/kip-4/) for details on tokenomics. (**Inflation numbers subject to change and documentation below provides the most current state**)
- See [KIP-3](https://kips.kwenta.io/kips/kip-3/) for details on staking mechanism.

The following architecture diagram represents a general overview of the system, but does not contain full detail of all implemented functions.

![Kwenta Token System Architecture Diagram](img/architecture-diagram-final.png)

## Documentation

### Kwenta.sol

This contract is an extended ERC20 where it’s constructed with the name “Kwenta”, symbolized as “KWENTA”, and with an initial supply of 313373. The initial mint is seeded to the Kwenta treasuryDAO. 

Minting KWENTA can only be performed once a week. A percentage of the new supply will be diverted to the treasury (20%). The remainder will go into StakingRewards and lastly, towards the minter (keeper) fee. There is also burn functionality which is used by our vesting fee mechanism further described below.

### SupplySchedule.sol

Similar to Synthetix's [SupplySchedule](https://github.com/Synthetixio/synthetix/blob/204b13bfdfd3c67cb48f875fc314b306965f39cf/contracts/SupplySchedule.sol), this contract describes the inflationary supply schedule over the next four years. There is 1% terminal inflation. Inflation begins as soon as the contract is deployed. Decay begins on week 2, meaning the first week’s rewards are not affected by decay. The current inflation target is roughly 1,009,409.43 KWENTA tokens at the end of four years. The initial weekly emission is calculated from INITIAL SUPPLY * 240% APY. Decay occurs at a rate of 2.05% a week and this should bring the weekly emission near the 1% APY mark at the end of four years.

### StakingRewards.sol

A modified StakingRewards contract with added support for escrowed KWENTA staking, trading rewards accumulated in epochs, and upgradeability.

Each week the StakingRewards contract is topped up with new inflationary supply `setNRewardEpochs` and `n` will determine for how many epochs (weeks) the current amount of rewards will be available for. This will typically be set to 1.

Rewards are split between stakers (80%) and traders (20%). Stakers will consist of regular KWENTA stakers and escrowed KWENTA stakers. Traders are required to be staked (before trading). To determine a trader’s “rewardScore” we utilize a Cobb-Douglas** function with `feesPaid` (to the Synthetix Exchanger) and staked amount as inputs. See formula below for details.

Epochs run weekly and the start of a new epoch will be marked upon the first interaction with the contract for that epoch. Note: a new epoch would mean a trader would have their `feesPaid` reset, but it does not mean they have to restake.

When rewards are harvested they are escrowed in RewardEscrow for a year.

This contract was made upgradeable (UUPS) to give us flexibility when rewarding additional tokens, but also factoring in additional Kwenta offerings (futures) into the trading rewards system. Upgradeable examples are under [contracts/mocks/upgradeable](contracts/mock/upgradeable/)

**This implementation of the Cobb-Douglas function required Fixidity’s logarithm library which required us to convert unsigned to signed integers as inputs.

![Kwenta Token System Architecture Diagram](img/cobb-douglas.png)
*Details: [Full Staking Mathematical Breakdown](docs/Kwenta_Staking.pdf)*

### RewardEscrow.sol

Based on Synthetix’s [BaseRewardEscrowV2](https://github.com/Synthetixio/synthetix/blob/204b13bfdfd3c67cb48f875fc314b306965f39cf/contracts/BaseRewardEscrowV2.sol) with migration and account merging functionality stripped out. Supports appending escrow entries from StakingRewards, but also open to anyone with `createEscrowEntry`. For example, the treasuryDAO will use this feature to escrow rewards for DAO beneficiaries. 

Any escrowed Kwenta can also be staked back into StakingRewards, boosting potential rewards for stakers. When staked, tokens are not transferred, but an “escrowedBalance” is accounted for in StakingRewards. There is additional logic to make sure sufficient Kwenta is unstaked when vesting rewards. 

Another new feature introduced here is a linearly decaying vesting fee that allows beneficiaries to vest early – at a cost. Immediate vesting is subject to a fee that is 80% of the escrowed amount. It falls to 0% as the reward reaches the end of the escrow duration. The fee is burned. 

### ExchangerProxy.sol

A simple contract that forwards trades to the Synthetix Exchanger, but updates each person’s trader score (currently measured as fees paid), and subsequently `rewardScore` in StakingRewards.

## Testing

```
npm run test
```
```
npm run test:contracts
```
```
npm run test:integration
```

## Deployment

*Coming soon...*

---

> ok I need KWENTA TOKEN TO GO LIVE. like VERY SOON. I cant take this anymore. every day I am checking discord and still no token. every day, check discord, no token. I cant take this anymore, I have under invested, by a lot. it is what it is. but I need the token to GO LIVE ALREADY. can devs DO SOMETHING??
