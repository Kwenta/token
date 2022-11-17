import fs from "fs";
import { ethers, BigNumber } from "ethers";
import stakerDistribution from "../distribution/staker-distribution.json";
import traderDistribution from "../distribution/trader-distribution.json";

type DistributionMap = {
    [address: string]: {
        address: string;
        earnings: string;
    };
};

const PRICE = ethers.utils.parseEther("31.91");

const readCSV = (path: string) => {
    const rows = fs.readFileSync(path, "utf8").split("\n");
    return rows.slice(1, rows.length - 1);
};

const writeCSV = (
    path: string,
    distributionData: {
        earnings: string;
        address: string;
    }[]
) => {
    const csvString = distributionData.reduce(
        (acc, staker) =>
            acc + `${staker.address},${staker.earnings.toString()}\n`,
        ""
    );

    fs.writeFileSync(path, csvString);
};

const generate = async () => {
    const rawAddresses = readCSV("scripts/aelin-distribution/data/pool1_addresses.csv");
    const lonoClauseEligible = rawAddresses.map((address) =>
        ethers.utils.getAddress(address)
    );

    let distributionMap = stakerDistribution.reduce((obj, dist) => {
        return (
            (obj[dist.address] = {
                address: dist.address,
                earnings: dist.earnings,
            }),
            obj
        );
    }, {} as DistributionMap);

    traderDistribution.forEach(({ address, earnings }) => {
        if (address in distributionMap) {
            distributionMap[address].earnings = BigNumber.from(
                distributionMap[address].earnings
            )
                .add(BigNumber.from(earnings))
                .toString();
        } else {
            distributionMap[address] = {
                address,
                earnings,
            };
        }
    });

    const fullDistribution = Object.values(distributionMap).map(
        ({ address, earnings }) => ({
            address: ethers.utils.getAddress(address),
            earnings,
        })
    );

    // Log OG Dist Amount
    let totalDistAmount = BigNumber.from(0);
    fullDistribution.forEach(({ earnings }) => {
        totalDistAmount = totalDistAmount.add(BigNumber.from(earnings));
    });
    console.log(
        "Total Original Distribution Amount:",
        ethers.utils.formatEther(totalDistAmount)
    );

    // Log Amount Subtracted
    let distAmountSubtracted = BigNumber.from(0);
    fullDistribution.forEach(({ address, earnings }) => {
        if (lonoClauseEligible.includes(address)) {
            distAmountSubtracted = distAmountSubtracted.add(
                BigNumber.from(earnings)
            );
        }
    });
    console.log(
        "Amount Removed: ",
        ethers.utils.formatEther(distAmountSubtracted)
    );

    const fullDistributionWithLonoClauseRecipientsRemoved =
        fullDistribution.filter(
            ({ address }) => !lonoClauseEligible.includes(address)
        );
    const distributionWithOnlyLonoClauseRecipients = fullDistribution.filter(
        ({ address }) => lonoClauseEligible.includes(address)
    );

    // Log Final Dist Amount with Lono Clause Recipients Removed
    let totalDistAmountWithLonoClause = BigNumber.from(0);
    fullDistributionWithLonoClauseRecipientsRemoved.forEach(({ earnings }) => {
        totalDistAmountWithLonoClause = totalDistAmountWithLonoClause.add(
            BigNumber.from(earnings)
        );
    });
    console.log(
        "Total Distribution Amount with Lono Clause: ",
        ethers.utils.formatEther(totalDistAmountWithLonoClause)
    );

    let totalUSD = BigNumber.from(0);
    const aelinAllowlist = fullDistributionWithLonoClauseRecipientsRemoved.map(
        ({ address, earnings }) => {
            const allocationCap = BigNumber.from(earnings)
                .mul(PRICE)
                .div(ethers.constants.WeiPerEther)
                .toString();
            totalUSD = totalUSD.add(allocationCap);

            return {
                address,
                earnings: allocationCap,
            };
        }
    );
    console.log("Total USD proceeds: ", ethers.utils.formatEther(totalUSD));

    writeCSV(
        `scripts/aelin-distribution/kwenta-allowlist.csv`,
        fullDistributionWithLonoClauseRecipientsRemoved
    );
    writeCSV(
        `scripts/aelin-distribution/lono-clause-recipients.csv`,
        distributionWithOnlyLonoClauseRecipients
    );
    writeCSV(`scripts/aelin-distribution/kwenta-allowlist-usd.csv`, aelinAllowlist);
};

generate();
