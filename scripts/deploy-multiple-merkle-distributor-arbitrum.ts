import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { saveDeployments, verify } from "./utils";

const REWARD_DISTRIBUTOR = "0x5566B4d1767C1019F430F65C6877237bAe25D6B9";
const ARB_TOKEN_ADDRESS = "0x912CE59144191C1204E64559FE8253a0e49E6548";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const tradingRewards = await deployMultipleMerkleDistributor(
        deployer,
        ARB_TOKEN_ADDRESS
    );

    await tradingRewards.nominateNewOwner(REWARD_DISTRIBUTOR);
    console.log(
        "TradingRewards nominated owner:         ",
        await tradingRewards.nominatedOwner()
    );
}

async function deployMultipleMerkleDistributor(
    owner: SignerWithAddress,
    token: string
) {
    const MultipleMerkleDistributor = await ethers.getContractFactory(
        "MultipleMerkleDistributor"
    );
    const multipleMerkleDistributor = await MultipleMerkleDistributor.deploy(
        owner.address,
        token
    );
    await multipleMerkleDistributor.deployed();
    await saveDeployments(
        "MultipleMerkleDistributor",
        multipleMerkleDistributor
    );
    console.log(
        "MultipleMerkleDistributor deployed to:        ",
        multipleMerkleDistributor.address
    );

    await verify(
        multipleMerkleDistributor.address,
        [owner.address, token],
        "contracts/MultipleMerkleDistributor.sol:MultipleMerkleDistributor" // to prevent bytecode clashes with contracts-exposed versions
    );

    return multipleMerkleDistributor;
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
