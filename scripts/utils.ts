import { BigNumber, Contract } from "ethers";
import hre from "hardhat";

const isLocal = hre.network.name == "localhost";

export async function saveDeployments(name: string, contract: Contract) {
    // For hardhat-deploy plugin to save deployment artifacts
    const { deployments } = hre;
    const { save } = deployments;

    const artifact = await deployments.getExtendedArtifact(name);
    let deployment = {
        address: contract.address,
        ...artifact,
    };

    await save(name, deployment);
}

type ConstructorArgs = string | BigNumber;
export async function verify(
    address: string,
    constructorArgs: Array<ConstructorArgs>,
    contract?: string
) {
    if (isLocal) return;

    try {
        await hre.run("verify:verify", {
            address: address,
            constructorArguments: constructorArgs,
            contract: contract,
            noCompile: true,
        });
    } catch (e) {
        // Can error out even if already verified
        // We don't want this to halt execution
        console.log(e);
    }
}
