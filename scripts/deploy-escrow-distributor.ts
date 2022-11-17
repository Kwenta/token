import { ethers } from "hardhat";

import kwentaTestnetDeploy from "../deployments/optimistic-goerli/Kwenta.json";
import rewardEscrowTestnetDeploy from "../deployments/optimistic-goerli/RewardEscrow.json";
import { saveDeployments, verify } from "./utils";

async function main() {
    const [deployer] = await ethers.getSigners();

    const EscrowDistributor = await ethers.getContractFactory(
        "EscrowDistributor"
    );

    const chain = await deployer.getChainId();

    // TODO: Add mainnet once deployed
    if (chain !== 420) throw new Error("Network not supported");

    console.log("Deploying contract");

    const escrowDistributor = await EscrowDistributor.deploy(
        kwentaTestnetDeploy.address,
        rewardEscrowTestnetDeploy.address
    );

    await escrowDistributor.deployed();

    console.log("Contract deployed: ", escrowDistributor.address);

    await saveDeployments("EscrowDistributor", escrowDistributor);

    await verify(
        escrowDistributor.address,
        [kwentaTestnetDeploy.address, rewardEscrowTestnetDeploy.address],
        "contracts/EscrowDistributor.sol:EscrowDistributor"
    );

    console.log("Contract verified and deployment complete.");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
