import stakerDistribution from "./distribution/staker-distribution.json";
import traderDistribution from "./distribution/trader-distribution.json";
import { mergeDistributions } from "./distribution/utils";
import { NewFormat } from "./merkle/parse-balance-map";
import { ethers } from "ethers";
import dotenv from "dotenv";

dotenv.config();

// L1 Provider
const provider_L1 = new ethers.providers.JsonRpcProvider(
    process.env.L1_ARCHIVE_NODE_URL
);

// L2 Provider
const provider_L2 = new ethers.providers.JsonRpcProvider(
    process.env.ARCHIVE_NODE_URL
);

/**
 * @author jaredborders
 * @notice to run:
 * `npx ts-node scripts/distribution-analysis.ts`
 */

async function main() {
    console.log("ANALYSIS");
    console.log("\n#################\n");

    // addresses eligible for KWENTA distribution
    let distributions: NewFormat[] = mergeDistributions(
        stakerDistribution,
        traderDistribution
    );

    console.log(
        "🟢 Total count of addresses eligible for $KWENTA: " +
            distributions.length
    );
    console.log("\n#################\n");

    let L1_multisigs: string[] = [];
    let L2_multisigs: string[] = [];
    let L1_AND_L2_multisigs: string[] = [];

    /**
     * L1 Analysis
     * @dev uses L1 provider and loops through all staker and trader addresses
     * eligible to claim $KWENTA
     */

    // for logging
    let multisigCount = 0;
    let multisigOnL1AndL2Count = 0;

    for (let i = 0; i < distributions.length; i++) {
        const address = distributions[i].address;

        // will throw if invalid address
        ethers.utils.getAddress(address);

        // is address multisig (contract)?
        let isMultisig = await isContract(provider_L1, address);
        if (isMultisig) {
            L1_multisigs.push(address);
            multisigCount++;
            let isBoth = await isContract(provider_L2, address);
            if (isBoth) {
                L1_AND_L2_multisigs.push(address);
                multisigOnL1AndL2Count++;
            }
        }
    }

    console.log("🟡 Total count of Multisigs on L1: " + multisigCount);
    console.log("\n#################\n");

    /**
     * L2 Analysis
     * @dev uses L2 provider and loops through all staker and trader addresses
     * eligible to claim $KWENTA
     */

    // for logging
    multisigCount = 0;

    for (let i = 0; i < distributions.length; i++) {
        const address = distributions[i].address;

        // will throw if invalid address
        ethers.utils.getAddress(address);

        // is address multisig (contract)?
        let isMultisig = await isContract(provider_L2, address);
        if (isMultisig) {
            L2_multisigs.push(address);
            multisigCount++;
        }
    }

    console.log("🔵 Total count of Multisigs on L2: " + multisigCount);
    console.log("\n#################\n");

    console.log(
        "🔵 Total count of addresses with code on L1 AND L2: " +
            multisigOnL1AndL2Count
    );
    console.log("\n#################\n");

    /**
     * @dev multisig addresses
     */

    console.log("🟡 L1 Addresses where codesize is non-zero 🟡");
    console.log("\n#################\n");
    for (let i = 0; i < L1_multisigs.length; i++) {
        console.log(L1_multisigs[i]);
    }

    console.log("🔵 L2 Addresses where codesize is non-zero 🔵");
    console.log("\n#################\n");
    for (let i = 0; i < L2_multisigs.length; i++) {
        console.log(L2_multisigs[i]);
    }

    console.log("🟠 Addresses where codesize is non-zero on L1 and L2 🟠");
    console.log("\n#################\n");
    for (let i = 0; i < L1_AND_L2_multisigs.length; i++) {
        console.log(L1_AND_L2_multisigs[i]);
    }

    console.log("\n#################\n");
}

/*///////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
///////////////////////////////////////////////////////////////*/

async function isContract(
    provider: ethers.providers.JsonRpcProvider,
    address: string
) {
    const code = await provider.getCode(address);
    return code !== "0x";
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
