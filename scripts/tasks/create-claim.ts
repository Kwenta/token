import { task } from "hardhat/config";
import { address as MULTIPLE_MERKLE_DISTRIBUTOR_ADDRESS } from "../../deployments-hardhat/optimistic-mainnet/EscrowedMultipleMerkleDistributor.json";
import { address as KWENTA_ADDRESS } from "../../deployments-hardhat/optimistic-mainnet/Kwenta.json";
import { parseBalanceMap } from "../merkle/parse-balance-map";
import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

// Example query:
// npx hardhat --network localhost create-claim --claimant 0xC2ecD777d06FFDF8B3179286BEabF52B67E9d991 --amount 1000000000000000000 --epoch 0

task("create-claim", "Create a MultipleMerkleDistributor claim to test against")
    .addParam("claimant", "The account claiming")
    .addParam("amount", "The amount of KWENTA to claim")
    .addParam("epoch", "The epoch tp write the claim for")
    .setAction(async (args, hre) => {
        await mintKwenta(hre, MULTIPLE_MERKLE_DISTRIBUTOR_ADDRESS, args.amount);
        await setMerkleRoot(hre, args.claimant, args.amount, args.epoch);
    });

async function mintKwenta(
    hre: HardhatRuntimeEnvironment,
    address: string,
    amount: string
) {
    // get owner of Kwenta
    const kwenta = await hre.ethers.getContractAt("Kwenta", KWENTA_ADDRESS);
    const owner = await kwenta.supplySchedule();

    // impersonate owner
    await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [owner],
    });

    // get signer
    const signer = await hre.ethers.getSigner(owner);

    await setBalance(owner, hre.ethers.constants.WeiPerEther);

    // mint Kwenta to claimant
    await kwenta.connect(signer).mint(address, amount);

    console.log(
        "KWENTA balance of MultipleMerkleDistributor is",
        hre.ethers.utils.formatEther(await kwenta.balanceOf(address))
    );
}

async function setMerkleRoot(
    hre: HardhatRuntimeEnvironment,
    claimant: string,
    amount: string,
    epoch: number
) {
    // get owner of MultipleMerkleDistributor
    const multipleMerkleDistributor = await hre.ethers.getContractAt(
        "MultipleMerkleDistributor",
        MULTIPLE_MERKLE_DISTRIBUTOR_ADDRESS
    );
    const owner = await multipleMerkleDistributor.owner();

    // impersonate owner
    await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [owner],
    });

    // get signer
    const signer = await hre.ethers.getSigner(owner);

    await setBalance(owner, hre.ethers.constants.WeiPerEther);

    // set the merkle root for epoch 0
    const merkleInfo = parseBalanceMap([
        {
            address: claimant,
            earnings: amount,
        },
    ]);

    await multipleMerkleDistributor
        .connect(signer)
        .setMerkleRootForEpoch(merkleInfo.merkleRoot, epoch);

    console.log("Merkle root of epoch", epoch, "is", merkleInfo.merkleRoot);
}
