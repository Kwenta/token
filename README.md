# Kwenta Token System

This is the main repository for the Kwenta token and respective system contracts (staking, escrow, distribution, etc..). 

- See [KIP-4](https://kips.kwenta.io/kips/kip-4/) for details on tokenomics.
- See [KIP-3](https://kips.kwenta.io/kips/kip-3/) for details on staking mechanism.

## Documentation

### Kwenta.sol

An extended ERC20 contract constructed with the name “Kwenta”, symbolized as “KWENTA”, and with an initial supply of 313373. Initial distribution is handled by the deployer in the deploy script.

Only the currently set SupplySchedule contract has control over minting.

### SupplySchedule.sol

Similar to Synthetix's [SupplySchedule](https://github.com/Synthetixio/synthetix/blob/204b13bfdfd3c67cb48f875fc314b306965f39cf/contracts/SupplySchedule.sol), this contract describes the inflationary supply schedule over the next four years. There is 1% terminal inflation. Inflation begins as soon as the contract is deployed. Decay begins on week 2, meaning the first week’s rewards are not affected by decay. The current inflation target is roughly 1,009,409.43 KWENTA tokens at the end of four years. The initial weekly emission is calculated from INITIAL SUPPLY * 240% APY. Decay occurs at a rate of 2.05% a week and this should bring the weekly emission near the 1% APY mark at the end of four years.

Minting KWENTA can only be performed once a week. A minting fee is issued first to ensure sustainable rewards for minter. After which, a percentage of the new supply will be diverted to the treasury (20%). Another percentage will be diverted to the trading rewards distribution contract (20%). The remainder will go into StakingRewards.

### StakingRewards.sol

A modified [StakingRewards](https://github.com/Synthetixio/synthetix/blob/204b13bfdfd3c67cb48f875fc314b306965f39cf/contracts/StakingRewards.sol) contract with added support for escrowed KWENTA staking.

When rewards are harvested they are escrowed in RewardEscrow for a year.

### RewardEscrow.sol

Based on Synthetix’s [BaseRewardEscrowV2](https://github.com/Synthetixio/synthetix/blob/204b13bfdfd3c67cb48f875fc314b306965f39cf/contracts/BaseRewardEscrowV2.sol) with migration and account merging functionality stripped out. Supports appending escrow entries from StakingRewards, but also open to anyone with `createEscrowEntry`. For example, the treasuryDAO will use this feature to escrow rewards for DAO beneficiaries. 

Any escrowed Kwenta can also be staked back into StakingRewards, boosting potential rewards for stakers. When staked, tokens are not transferred, but an “escrowedBalance” is accounted for in StakingRewards. There is additional logic to make sure sufficient Kwenta is unstaked when vesting rewards. 

Another mechanism introduced here is a linearly decaying vesting fee that allows beneficiaries to vest early – at a cost. Immediate vesting is subject to a fee that is 80% of the escrowed amount. It falls to 0% as the reward reaches the end of the escrow duration. The fee is sent to the kwenta treasury. 

### MerkleDistributor.sol

Distribution manager for the initial KWENTA distribution. Details are described in [KIP-13](https://kips.kwenta.io/kips/kip-13/) and scripts used to generate the distribution can be found under [scripts/distribution/](scripts/distribution/).

#### ControlL2MerkleDistributor.sol

A companion contract deployed to Ethereum Mainnet to enable multisigs on L1 to claim retroactively earned KWENTA on L2. 

### MultipleMerkleDistributor.sol

Modified MerkleDistributor that supports rewards over multiple epochs. This will be used in conjunction with a trading rewards calculation script to pay out incentives. A portion of inflation is routed towards this contract every mint.

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
```
npm run test:fork
```

## Local Deployment & Interacting

Run a local hardhat node
```
npx hardhat node
```
Deploy contracts to localhost
```
npm run deploy:local
```
Run the interact tool
```
npm run interact:local
```
## Deployments

| Contract | Address |
| --- | --- |
|vKWENTA | [`0x6789D8a7a7871923Fc6430432A602879eCB6520a`](https://optimistic.etherscan.io/token/0x6789d8a7a7871923fc6430432a602879ecb6520a) |

---

> ok I need KWENTA TOKEN TO GO LIVE. like VERY SOON. I cant take this anymore. every day I am checking discord and still no token. every day, check discord, no token. I cant take this anymore, I have under invested, by a lot. it is what it is. but I need the token to GO LIVE ALREADY. can devs DO SOMETHING??
