import fs from "fs";
import { ethers, BigNumber } from "ethers";
import { request, gql } from "graphql-request";

const TOTAL_DISTRIBUTION = ethers.utils.parseEther("109680.55");
const PRICE = ethers.utils.parseEther("31.91");

const readCSV = (path: string) => {
    const rows = fs.readFileSync(path, "utf8").split("\n");
    return rows.slice(0, rows.length - 1);
};

const writeCSV = (
    path: string,
    distributionData: {
        amount: string;
        address: string;
    }[]
) => {
    const csvString = distributionData.reduce(
        (acc, distributee) =>
            acc + `${distributee.address},${distributee.amount.toString()}\n`,
        ""
    );

    fs.writeFileSync(path, csvString);
};

const divBig = (a: BigNumber, b: BigNumber) =>
    a.mul(ethers.constants.WeiPerEther).div(b);

async function main() {
    const response = (
        await request(
            "https://api.thegraph.com/subgraphs/name/alextheboredape/aelin-mainnet",
            gql`
                query deposits($pool: String!) {
                    deposits(
                        first: 1000
                        orderBy: timestamp
                        orderDirection: desc
                        where: { pool: $pool }
                    ) {
                        userAddress
                        amountDeposited
                    }
                }
            `,
            {
                pool: "0x21f4f88a95f656ef4ee1ea107569b3b38cf8daef",
            }
        )
    ).deposits as {
        userAddress: string;
        amountDeposited: string;
    }[];

    const pool2PurchaseAmounts = response.map(
        ({ userAddress, amountDeposited }) => {
            const kwentaPurchased = BigNumber.from(amountDeposited)
                .mul(ethers.constants.WeiPerEther)
                .div(PRICE);
            return {
                address: ethers.utils.getAddress(userAddress),
                amount: kwentaPurchased,
            };
        }
    );

    const lono = readCSV("scripts/aelin-distribution/lono-clause-recipients.csv");

    const lonoAllocationAmounts = lono.map((row) => {
        const rowCells = row.split(",");
        const kwentaAlloc = BigNumber.from(rowCells[1]);
        return {
            address: ethers.utils.getAddress(rowCells[0]),
            amount: kwentaAlloc,
        };
    });

    const totalActualDistribution = pool2PurchaseAmounts.concat(
        lonoAllocationAmounts
    );

    // 40605.83 = LONO + Aelin Pool Purchases
    const sumAllocated = totalActualDistribution.reduce(
        (acc, curr) => acc.add(curr.amount),
        BigNumber.from(0)
    );

    console.log("Sum allocated:", ethers.utils.formatEther(sumAllocated));

    const percentDistributed = divBig(sumAllocated, TOTAL_DISTRIBUTION);
    const proportionalDistributionFactor = divBig(
        ethers.constants.WeiPerEther,
        percentDistributed.add(ethers.constants.One)
    ); // Add ONE so the inverse preserves truncation

    // Factor is calculated to be roughly ~2.7x
    const proportionalDistributionAmounts = totalActualDistribution.map(
        (distribution) => {
            return {
                ...distribution,
                extraDistributionAmount: distribution.amount
                    .mul(proportionalDistributionFactor)
                    .div(ethers.constants.WeiPerEther)
                    .sub(distribution.amount),
            };
        }
    );

    const totalDistributionAmount = proportionalDistributionAmounts
        .reduce(
            (acc, curr) => acc.add(curr.extraDistributionAmount),
            BigNumber.from(0)
        )
        .add(sumAllocated);

    console.log(
        "Final total distribution amount:",
        ethers.utils.formatEther(totalDistributionAmount),
        ethers.utils.formatEther(TOTAL_DISTRIBUTION)
    );

    writeCSV(
        "scripts/aelin-distribution/proportional-distribution.csv",
        proportionalDistributionAmounts
            // Sort by highest amounts
            .sort((a, b) =>
                Number(
                    ethers.utils.formatEther(
                        b.extraDistributionAmount.sub(a.extraDistributionAmount)
                    )
                )
            ) // Prep results for processing
            .map(({ address, extraDistributionAmount }) => ({
                address,
                amount: extraDistributionAmount.toString(),
            }))
    );
}

main();
