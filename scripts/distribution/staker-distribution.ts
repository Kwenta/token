import * as mainnetMain from './generated/mainnet-main';
import * as optimismMain from './generated/optimism-main';
import preregenesisSNXHoldersSnapshot from './preregenesis_snapshots/l2-snxholders-preregenesis.json';
import { request, gql } from 'graphql-request';
import { BigNumber, ethers } from 'ethers';
import Synthetix from '@synthetixio/contracts-interface';
import Wei, { wei } from '@synthetixio/wei';
import { reconstructWei, SerializedWei } from './utils';
import fs from 'fs';

type PreregenesisSNXHolder = {
    id: string;
    block: SerializedWei;
    timestamp: SerializedWei;
    balanceOf: SerializedWei;
    collateral: SerializedWei;
    transferable: SerializedWei;
    initialDebtOwnership: SerializedWei;
    debtEntryAtIndex: SerializedWei;
    claims: SerializedWei;
    mints: SerializedWei;
};

type SNXHolder = {
    id: string;
    block: string;
    timestamp: string;
    balanceOf: string;
    collateral: string;
    transferable: string;
    initialDebtOwnership: string;
    debtEntryAtIndex: string;
    claims?: string;
    mints?: string;
};

// Feb-01-2022 12:00:00 AM +UTC
const L1_BLOCK_SNAPSHOT = 14116761;
const L2_BLOCK_SNAPSHOT = 3067128;

const L1_SUBGRAPH =
    'https://api.thegraph.com/subgraphs/name/synthetixio-team/mainnet-main';
const L2_SUBGRAPH =
    'https://api.thegraph.com/subgraphs/name/synthetixio-team/optimism-main';

const getUniqueFeesClaimers = async (isOptimism?: boolean) => {
    console.log('Gathering fee claimers...');

    const feesClaimeds = await (isOptimism
        ? optimismMain
        : mainnetMain
    ).getFeesClaimeds(
        isOptimism ? L2_SUBGRAPH : L1_SUBGRAPH,
        {
            first: 999999999999999,
            orderBy: 'timestamp',
            orderDirection: 'desc',
            where: {
                timestamp_gt: 1630454400,
                timestamp_lt: 1643673600,
            },
        },
        {
            id: true,
            block: true,
            timestamp: true,
            account: true,
            value: true,
            rewards: true,
        }
    );
    console.log(feesClaimeds.length, 'fee claim events gathered.');

    const uniqueAccounts = feesClaimeds.reduce((acc: Array<string>, curr) => {
        if (!acc.includes(curr.account)) acc.push(curr.account);
        return acc;
    }, []);

    console.log(
        uniqueAccounts.length,
        'accounts claimed at least once during specified period.'
    );

    return uniqueAccounts;
};

const getSNXHoldersWithActiveDebt = async (
    accounts: string[],
    block: number,
    isOptimism?: boolean
) => {
    console.log('Gathering SNX holders...');

    let snxholders = [] as Array<SNXHolder>;
    for (let i = 0; i < accounts.length / 1000; i++) {
        const response = await request(
            isOptimism ? L2_SUBGRAPH : L1_SUBGRAPH,
            gql`
                query getSNXHolders($accounts: [String!], $block: Int!) {
                    snxholders(
                        first: 1000
                        block: { number: $block }
                        where: { id_in: $accounts }
                    ) {
                        id
                        block
                        timestamp
                        balanceOf
                        collateral
                        transferable
                        initialDebtOwnership
                        debtEntryAtIndex
                        claims
                        mints
                    }
                }
            `,
            {
                accounts: accounts.slice(i * 1000, (i + 1) * 1000),
                block: block,
            }
        );

        snxholders.push(...response.snxholders);
    }

    console.log(
        snxholders.length,
        `SNX ${isOptimism ? 'post regenesis' : ''} holders found.`
    );

    // Get missing preregenesis stakers
    if (isOptimism) {
        const addressesMissingSNXHolderData = accounts.filter(
            (address) => !snxholders.map((x) => x.id).includes(address)
        );
        const preregenesisStakers = (
            preregenesisSNXHoldersSnapshot as Array<PreregenesisSNXHolder>
        ).filter(
            (snxholder) =>
                addressesMissingSNXHolderData.includes(snxholder.id) &&
                snxholder.claims != undefined &&
                reconstructWei(snxholder.claims).toNumber() != 0
        );

        const cleanedPreregenesisStakers = preregenesisStakers.map((staker) => {
            return {
                id: staker.id,
                block: reconstructWei(staker.block).toString(),
                timestamp: reconstructWei(staker.timestamp).toString(),
                balanceOf: reconstructWei(staker.balanceOf).toString(),
                collateral: reconstructWei(staker.collateral).toString(),
                transferable: reconstructWei(staker.transferable).toString(),
                initialDebtOwnership: reconstructWei(
                    staker.initialDebtOwnership
                ).toString(),
                debtEntryAtIndex: reconstructWei(
                    staker.debtEntryAtIndex
                ).toString(),
            };
        });

        console.log(
            'Appending',
            cleanedPreregenesisStakers.length,
            'pre-regenesis SNXHolders'
        );
        snxholders.push(...cleanedPreregenesisStakers);
    }

    const snxholdersWithDebt = snxholders.filter(
        (snxholder) => snxholder.initialDebtOwnership != '0'
    );

    console.log(snxholdersWithDebt.length, 'with active debt.');

    return snxholdersWithDebt;
};

const getTotalDebt = async (
    provider: ethers.providers.Provider,
    block: number,
    isL2?: boolean
) => {
    const synthetix = Synthetix({
        network: isL2 ? 'mainnet-ovm' : 'mainnet',
        provider,
    });

    const { DebtCache } = synthetix.contracts;
    const currentDebt = await DebtCache.currentDebt({
        blockTag: block,
    });

    return wei(currentDebt.debt, 18, true);
};

const getLastDebtLedgerEntry = async (
    provider: ethers.providers.Provider,
    block: number,
    isL2?: boolean
) => {
    const synthetix = Synthetix({
        network: isL2 ? 'mainnet-ovm' : 'mainnet',
        provider,
    });

    const { SynthetixState } = synthetix.contracts;
    const lastDebtLedgerEntry: BigNumber =
        await SynthetixState.lastDebtLedgerEntry({
            blockTag: block,
        });

    return wei(lastDebtLedgerEntry, 27, true);
};

const getDebtWeightedScore = (
    initialDebtOwnership: Wei,
    debtEntryAtIndex: Wei,
    totalL1Debt: Wei,
    scaledTotalL2Debt: Wei,
    lastDebtLedgerEntry: Wei,
    isL2: boolean
) => {
    const debtBalance = (isL2 ? scaledTotalL2Debt : totalL1Debt)
        .mul(lastDebtLedgerEntry)
        .div(debtEntryAtIndex)
        .mul(initialDebtOwnership);

    const totalSystemDebt = totalL1Debt.add(scaledTotalL2Debt);

    const ownershipPercentOfTotalDebt = debtBalance.div(totalSystemDebt);

    return ownershipPercentOfTotalDebt.toNumber();
};

const main = async () => {
    const providerL1 = new ethers.providers.JsonRpcProvider(
        'https://eth-mainnet.alchemyapi.io/v2/BxMdi15KTChUN673E1sigzV5EeBTzUlU'
    );
    const providerL2 = new ethers.providers.JsonRpcProvider(
        'https://opt-mainnet.g.alchemy.com/v2/4jaqXoLzv_hTeuWJUmtzOp7H-axcyR9R'
    );
    const totalL1Debt = await getTotalDebt(providerL1, L1_BLOCK_SNAPSHOT);
    const totalL2Debt = await getTotalDebt(providerL2, L2_BLOCK_SNAPSHOT, true);
    const lastDebtLedgerEntryL1 = await getLastDebtLedgerEntry(
        providerL1,
        L1_BLOCK_SNAPSHOT
    );
    const lastDebtLedgerEntryL2 = await getLastDebtLedgerEntry(
        providerL2,
        L2_BLOCK_SNAPSHOT,
        true
    );

    console.log('--System Info--');

    console.log('L1 Debt', totalL1Debt.toString());
    console.log('L2 Debt', totalL2Debt.toString());
    console.log('L1 Last Debt Ledger Entry', lastDebtLedgerEntryL1.toString());
    console.log('L2 Last Debt Ledger Entry', lastDebtLedgerEntryL2.toString());

    const normalisedL2CRatio = 500 / 400;
    const scaledTotalL2Debt = totalL2Debt.mul(normalisedL2CRatio);

    console.log('Scaled L2 Debt', scaledTotalL2Debt.toString());

    console.log(
        'Scaled L2 Debt Percentage',
        scaledTotalL2Debt.div(scaledTotalL2Debt.add(totalL1Debt)).toString()
    );

    console.log('\n--Grabbing L1 Set--');
    const eligibleAddressesL1 = await getUniqueFeesClaimers();
    const eligibleAddressesWithDebtL1 = await getSNXHoldersWithActiveDebt(
        eligibleAddressesL1,
        L1_BLOCK_SNAPSHOT
    );
    console.log('\n--Grabbing L2 Set--');
    const eligibleAddressesL2 = await getUniqueFeesClaimers(true);
    const eligibleAddressesWithDebtL2 = await getSNXHoldersWithActiveDebt(
        eligibleAddressesL2,
        L2_BLOCK_SNAPSHOT,
        true
    );

    const l1DebtScores = eligibleAddressesWithDebtL1.map(
        ({ id, initialDebtOwnership, debtEntryAtIndex }) => ({
            address: id,
            debtScore: getDebtWeightedScore(
                wei(initialDebtOwnership, 18, true),
                wei(debtEntryAtIndex, 18, true),
                totalL1Debt,
                scaledTotalL2Debt,
                lastDebtLedgerEntryL1,
                false
            ),
        })
    );

    const l2DebtScores = eligibleAddressesWithDebtL2.map(
        ({ id, initialDebtOwnership, debtEntryAtIndex }) => ({
            address: id,
            debtScore: getDebtWeightedScore(
                wei(initialDebtOwnership, 18, true),
                wei(debtEntryAtIndex, 18, true),
                totalL1Debt,
                scaledTotalL2Debt,
                lastDebtLedgerEntryL2,
                true
            ),
        })
    );

    // Merge duplicate L1 & L2 addresses
    const mergedStakersDebtScores: any = [
        ...l1DebtScores,
        ...l2DebtScores,
    ].reduce((acc: any, curr) => {
        if (acc.filter((i: any) => i.address === curr.address).length > 0) {
            return acc.map((j: any) => {
                if (j.address === curr.address) {
                    return {
                        ...j,
                        debtScore: j.debtScore + curr.debtScore,
                    };
                }
                return j;
            });
        }
        return [...acc, curr];
    }, []);

    // Remove stakers below 1e-8 score
    const filteredDebtScores = (
        mergedStakersDebtScores as Array<{ address: string; debtScore: number }>
    ).filter((staker) => staker.debtScore >= 1e-7);

    // Sum total debt scores
    const totalDebtScore = filteredDebtScores.reduce(
        (total: Wei, curr) => total.add(curr.debtScore),
        wei(0)
    );

    // Assign pro-rata weights for debt scores
    const distributionShare = filteredDebtScores.map((staker) => ({
        ...staker,
        debtScoreShare: wei(staker.debtScore).div(totalDebtScore),
    }));

    const floorKwentaAmount = wei(5);
    const remainingKwentaAmount = wei(313373)
        .mul(0.3)
        .sub(floorKwentaAmount.mul(distributionShare.length));

    // Assign KWENTA to stakers
    const realDistributionAmounts = distributionShare.map((staker) => ({
        ...staker,
        amount: floorKwentaAmount.add(
            wei(staker.debtScoreShare).mul(remainingKwentaAmount)
        ),
    }));

    const sortedKwentaDistribution = realDistributionAmounts.sort((a, b) =>
        b.amount.sub(a.amount).toNumber()
    );

    console.log(
        '\nFinal number of distribution recipients:',
        sortedKwentaDistribution.length
    );

    const finalDistribution = sortedKwentaDistribution.map(
        ({ address, amount }) => ({
            address,
            earnings: amount.toBN().toString(),
        })
    );

    writeCSV(finalDistribution);
    writeCSV(finalDistribution, true);
    writeJSON(finalDistribution);

    console.log('\n--JSON Generation Complete--');
};

const writeJSON = (
    distributionData: {
        earnings: string;
        address: string;
    }[]
) => {
    fs.writeFileSync(
        `./scripts/distribution/staker-distribution.json`,
        JSON.stringify(distributionData, null, 2)
    );
};

const writeCSV = (
    distributionData: {
        earnings: string;
        address: string;
    }[],
    amountsHidden: boolean = false
) => {
    const csvString = distributionData.reduce(
        (acc, staker) =>
            acc +
            `${staker.address}${
                amountsHidden ? '' : `,${staker.earnings.toString()}`
            }\n`,
        ''
    );

    fs.writeFileSync(
        `./scripts/distribution/staker-distribution${
            amountsHidden ? '-ONLY-ADDRESSES' : ''
        }.csv`,
        csvString
    );
};

main();
