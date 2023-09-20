// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { createV1EscrowEntries } from "./helpers/staking-v2";

/************************************************
 * @main
 ************************************************/

async function main() {
    const numToCreate = 5;
    const recipientAddress = "0x8E2f228c0322F872efAF253eF25d7F5A78d5851D";

    await createV1EscrowEntries({
        numToCreate,
        recipientAddress,
    });
}

/************************************************
 * @execute
 ************************************************/

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
