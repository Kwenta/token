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

## Staking V2

Staking was upgraded to V2 on the 11th of July 2023. This introduces changes described by the following KIPS:
- [KIP-42: delegation of claiming ability](https://github.com/Kwenta/kwenta-state-log/blob/master/kips/kip-042.md)
- [KIP-58: checkpointing system and migration to V2](https://github.com/Kwenta/kwenta-state-log/blob/master/kips/kip-058.md)
- [KIP-62: transferable escrow entries](https://github.com/Kwenta/kwenta-state-log/blob/master/kips/kip-062.md)
- [KIP-77: upgradeable staking contracts](https://github.com/Kwenta/kwenta-state-log/blob/master/kips/kip-077.md)
- [KIP-86: support for staking integrators](https://github.com/Kwenta/kwenta-state-log/blob/master/kips/kip-086.md)
- [KIP-75: 50% of early vest fees distributed to stakers](https://github.com/Kwenta/kwenta-state-log/blob/master/kips/kip-075.md)

Here is an overview of the changes:
- [Overview of Staking V2 Changes](https://github.com/tommyrharper/shared-notes/blob/main/stakingv2/overview/stakingv2-overview-new.md)

Here is an explanation of the migration process:
- [The Migration Process Explained](https://github.com/tommyrharper/shared-notes/blob/main/stakingv2/migration-v2/migration-v2.md)

Three main new contracts were deployed:
- `RewardEscrowV2.sol` - upgraded version of `RewardEscrow`
- `StakingRewardsV2.sol` - upgraded version of `StakingRewards`
- `EscrowMigrator.sol` - used for the migration process.

All of these contracts are upgradeable following the UUPS standard.

Also the following simple non-upgradeable contract was added to help enact `KIP-75`:
- `StakingRewardsNotifier.sol`

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

## Scripting with Tenderly

You can use scripts such as `npm run deploy:stakingv2-tenderly` to deploy and verify contracts on a Tenderly fork.

In order for the verification to work, you must:
- [Install `tenderly-cli`](https://github.com/Tenderly/tenderly-cli)
  - `brew install tenderly`
- [Create a Tenderly API Access Token](https://docs.tenderly.co/other/platform-access/how-to-generate-api-access-tokens)
- [Log in to tenderly via the CLI](https://github.com/Tenderly/tenderly-cli#login)
  - `tenderly login --access-key <KEY>`
- Set the tenderly fork URL in your `.env`
  - `TENDERLY_FORK_URL=https://rpc.tenderly.co/fork/<KEY>`

Now you can run `npm run deploy:stakingv2-tenderly` and it will deploy and verify the contracts on Tenderly.

You can also follow the pattern in [`deploy-stakingv2-tenderly.ts`](./scripts/deploy-stakingv2-tenderly.ts) to deploy and verify other contracts.

Or another example of a tenderly script is [`get-tenderly-time.ts`](./scripts/get-tenderly-time.ts).

## Deployments

Note: for contracts with both an implementation and proxy, when interaction with the contract is required, the proxy address should be used.

| Contract                        | Address                                                                                                                            |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Kwenta                          | [`0x920Cf626a271321C151D027030D5d08aF699456b`](https://optimistic.etherscan.io/token/0x920Cf626a271321C151D027030D5d08aF699456b)   |
| SupplySchedule                  | [`0x3e8b82326Ff5f2f10da8CEa117bD44343ccb9c26`](https://optimistic.etherscan.io/address/0x3e8b82326Ff5f2f10da8CEa117bD44343ccb9c26) |
| StakingRewards                  | [`0x6e56A5D49F775BA08041e28030bc7826b13489e0`](https://optimistic.etherscan.io/address/0x6e56A5D49F775BA08041e28030bc7826b13489e0) |
| RewardEscrow                    | [`0x1066A8eB3d90Af0Ad3F89839b974658577e75BE2`](https://optimistic.etherscan.io/address/0x1066A8eB3d90Af0Ad3F89839b974658577e75BE2) |
| StakingRewardsNotifier          | [`0x03f6dC6e616AB3a367a1F2C26B8Bc146f632b451`](https://optimistic.etherscan.io/address/0x03f6dC6e616AB3a367a1F2C26B8Bc146f632b451) |
| StakingRewardsV2 Proxy          | [`0x61294940CE7cD1BDA10e349adC5B538B722CeB88`](https://optimistic.etherscan.io/address/0x61294940CE7cD1BDA10e349adC5B538B722CeB88) |
| StakingRewardsV2 Implementation | [`0x626e666c95f4a31439A9cA2d5ef757EA3d72A2fd`](https://optimistic.etherscan.io/address/0x626e666c95f4a31439A9cA2d5ef757EA3d72A2fd) |
| RewardEscrowV2 Proxy            | [`0xb2a20fCdc506a685122847b21E34536359E94C56`](https://optimistic.etherscan.io/address/0xb2a20fCdc506a685122847b21E34536359E94C56) |
| RewardEscrowV2 Implementation   | [`0x15725a8159629ca9763deC4211e309c94d9f5CB0`](https://optimistic.etherscan.io/address/0x15725a8159629ca9763deC4211e309c94d9f5CB0) |
| EscrowMigrator Proxy            | [`0xC9aF789Ae606F69cF8Ed073A04eC92f2354b027d`](https://optimistic.etherscan.io/address/0xC9aF789Ae606F69cF8Ed073A04eC92f2354b027d) |
| EscrowMigrator Implementation   | [`0x10B04483d762Bd4F193F35600112ad52391004A7`](https://optimistic.etherscan.io/address/0x10B04483d762Bd4F193F35600112ad52391004A7) |
| MultipleMerkleDistributor       | [`0xf486A72E8c8143ACd9F65A104A16990fDb38be14`](https://optimistic.etherscan.io/address/0xf486A72E8c8143ACd9F65A104A16990fDb38be14) |
| MultipleMerkleDistributor (ARB) | [`0x5733Ef72c134E7A276029CB4ba07Bff8b1163086`](https://arbiscan.io/address/0x5733Ef72c134E7A276029CB4ba07Bff8b1163086) |
| vKWENTA                         | [`0x6789D8a7a7871923Fc6430432A602879eCB6520a`](https://optimistic.etherscan.io/token/0x6789d8a7a7871923fc6430432a602879ecb6520a)   |
| vKWENTARedeemer                 | [`0x8132EE584bCD6f8Eb1bea141DB7a7AC1E72917b9`](https://optimistic.etherscan.io/address/0x8132EE584bCD6f8Eb1bea141DB7a7AC1E72917b9) |

## Staking V2 Audits

- [Final Audit Report By Guhu](https://gist.github.com/guhu95/3330fad8e6417b567a3787f86392ae32)
- [Final Audit Report by Macro](https://0xmacro.com/library/audits/kwenta-7.html)

Other audit reports to add:
- [Final Audit Report by Omniscia](https://omniscia.io/reports/kwenta-staking-v2-w-migrators-64e48aba18c4480014cf4897/)

---

> ok I need KWENTA TOKEN TO GO LIVE. like VERY SOON. I cant take this anymore. every day I am checking discord and still no token. every day, check discord, no token. I cant take this anymore, I have under invested, by a lot. it is what it is. but I need the token to GO LIVE ALREADY. can devs DO SOMETHING??
