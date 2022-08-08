// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { wei } from "@synthetixio/wei";
import { Contract } from "ethers";
import hre, { ethers } from "hardhat";
import { NewFormat, parseBalanceMap } from "./parse-balance-map";
import stakerDistribution from "./distribution/staker-distribution.json";
import traderDistribution from "./distribution/trader-distribution.json";
import { mergeDistributions } from "./distribution/utils";

const MULTISIG = "0xF510a2Ff7e9DD7e18629137adA4eb56B9c13E885";
const TREASURY_DAO = "0x82d2242257115351899894eF384f779b5ba8c695";
const INITIAL_SUPPLY = 313373;

async function main() {
    const [deployer] = await ethers.getSigners();

    // ========== DEPLOYMENT ========== */

    console.log("\n💥 Beginning deployments...");
    const kwenta = await deployKwenta(deployer);
    const safeDecimalMath = await deploySafeDecimalMath();
    const supplySchedule = await deploySupplySchedule(
        deployer,
        safeDecimalMath
    );
    const rewardEscrow = await deployRewardEscrow(deployer, kwenta);
    const stakingRewards = await deployStakingRewards(
        deployer,
        kwenta,
        rewardEscrow,
        supplySchedule
    );
    const vKwentaRedeemer = await deployvKwentaRedeemer(kwenta);
    const tradingRewards = await deployMultipleMerkleDistributor(
        deployer,
        kwenta,
        rewardEscrow
    );
    const merkleDistributor = await deployMerkleDistributor(
        deployer,
        kwenta,
        rewardEscrow,
        mergeDistributions(stakerDistribution, traderDistribution)
    );
    console.log("✅ Deployments complete!");

    // ========== SETTERS ========== */

    console.log("\n🔩 Configuring setters...");
    // set SupplySchedule for kwenta
    await kwenta.setSupplySchedule(supplySchedule.address);
    console.log(
        "Kwenta: SupplySchedule address set to:          ",
        await kwenta.supplySchedule()
    );

    // set StakingRewards address in SupplySchedule
    await supplySchedule.setStakingRewards(stakingRewards.address);
    console.log(
        "SupplySchedule: StakingRewards address set to:  ",
        await supplySchedule.stakingRewards()
    );

    // set TradingRewards (i.e. MultipleMerkleDistributor) address in SupplySchedule
    await supplySchedule.setTradingRewards(tradingRewards.address);
    console.log(
        "SupplySchedule: TradingRewards address set to:  ",
        await supplySchedule.tradingRewards()
    );

    // set StakingRewards address in RewardEscrow
    await rewardEscrow.setStakingRewards(stakingRewards.address);
    console.log(
        "RewardEscrow: StakingRewards address set to:    ",
        await rewardEscrow.stakingRewards()
    );
    console.log("✅ Setters set!");

    /*
     * @TODO: Deploy ControlL2MerkleDistributor on L1 passing deployed merkleDistributor as constructor param
     * @TODO: Call MerkleDistributor.setControlL2MerkleDistributor(), setting ControlL2MerkleDistributor L1 address
     */

    // ========== DISTRIBUTION ========== */

    // Send KWENTA to respective contracts
    console.log("\n🎉 Distributing KWENTA...");
    await distributeKWENTA(
        deployer,
        kwenta,
        vKwentaRedeemer,
        merkleDistributor
    );
    console.log("✅ KWENTA distributed!");

    // ========== OWNER NOMINATION ========== */

    console.log("\n🔒 Nominating multisig as owner...");
    await kwenta.nominateNewOwner(MULTISIG);
    console.log(
        "Kwenta nominated owner:                 ",
        await kwenta.nominatedOwner()
    );
    await merkleDistributor.nominateNewOwner(MULTISIG);
    console.log(
        "MerkleDistributor nominated owner:      ",
        await merkleDistributor.nominatedOwner()
    );
    await tradingRewards.nominateNewOwner(MULTISIG);
    console.log(
        "TradingRewards nominated owner:         ",
        await tradingRewards.nominatedOwner()
    );
    await supplySchedule.nominateNewOwner(MULTISIG);
    console.log(
        "SupplySchedule nominated owner:         ",
        await supplySchedule.nominatedOwner()
    );
    await rewardEscrow.nominateNewOwner(MULTISIG);
    console.log(
        "RewardEscrow nominated owner:           ",
        await rewardEscrow.nominatedOwner()
    );
    await stakingRewards.nominateNewOwner(MULTISIG);
    console.log(
        "StakingRewards nominated owner:         ",
        await stakingRewards.nominatedOwner()
    );
    console.log("✅ Nomination complete!\n");
}

/************************************************
 * @deployers
 ************************************************/

async function deploySafeDecimalMath() {
    // deploy SafeDecimalMath
    const SafeDecimalMath = await ethers.getContractFactory("SafeDecimalMath");
    const safeDecimalMath = await SafeDecimalMath.deploy();
    await safeDecimalMath.deployed();
    await saveDeployments("SafeDecimalMath", safeDecimalMath);

    return safeDecimalMath;
}

async function deployKwenta(owner: SignerWithAddress) {
    const Kwenta = await ethers.getContractFactory("Kwenta");
    const kwenta = await Kwenta.deploy(
        "Kwenta",
        "KWENTA",
        wei(INITIAL_SUPPLY).toBN(),
        owner.address,
        owner.address // Send KWENTA to deployer first
    );
    await kwenta.deployed();
    await saveDeployments("Kwenta", kwenta);
    console.log("KWENTA token deployed to:          ", kwenta.address);
    return kwenta;
}

async function deploySupplySchedule(
    owner: SignerWithAddress,
    safeDecimalMath: Contract
) {
    const SupplySchedule = await ethers.getContractFactory("SupplySchedule", {
        libraries: {
            SafeDecimalMath: safeDecimalMath.address,
        },
    });
    const supplySchedule = await SupplySchedule.deploy(
        owner.address,
        TREASURY_DAO
    );
    await supplySchedule.deployed();
    await saveDeployments("SupplySchedule", supplySchedule);
    console.log("SupplySchedule deployed to:        ", supplySchedule.address);
    return supplySchedule;
}

async function deployRewardEscrow(owner: SignerWithAddress, kwenta: Contract) {
    const RewardEscrow = await ethers.getContractFactory("RewardEscrow");
    const rewardEscrow = await RewardEscrow.deploy(
        owner.address,
        kwenta.address
    );
    await rewardEscrow.deployed();
    await saveDeployments("RewardEscrow", rewardEscrow);
    console.log("RewardEscrow deployed to:          ", rewardEscrow.address);
    return rewardEscrow;
}

async function deployStakingRewards(
    owner: SignerWithAddress,
    kwenta: Contract,
    rewardEscrow: Contract,
    supplySchedule: Contract
) {
    const StakingRewards = await ethers.getContractFactory("StakingRewards");
    const stakingRewards = await StakingRewards.connect(owner).deploy(
        kwenta.address,
        rewardEscrow.address,
        supplySchedule.address
    );
    await stakingRewards.deployed();
    await saveDeployments("StakingRewards", stakingRewards);
    console.log("StakingRewards deployed to:        ", stakingRewards.address);
    return stakingRewards;
}

async function deployvKwentaRedeemer(kwenta: Contract) {
    const VKwentaRedeemer = await ethers.getContractFactory("vKwentaRedeemer");
    const vKwentaRedeemer = await VKwentaRedeemer.deploy(
        "0x6789D8a7a7871923Fc6430432A602879eCB6520a",
        kwenta.address
    );
    await vKwentaRedeemer.deployed();
    await saveDeployments("vKwentaRedeemer", vKwentaRedeemer);
    console.log("vKwentaRedeemer deployed to:       ", vKwentaRedeemer.address);
    return vKwentaRedeemer;
}

async function deployMerkleDistributor(
    owner: SignerWithAddress,
    kwenta: Contract,
    rewardEscrow: Contract,
    distribution: NewFormat[]
) {
    const merkleDistributorInfo = parseBalanceMap(distribution);
    const merkleRoot = merkleDistributorInfo.merkleRoot;

    const MerkleDistributor = await ethers.getContractFactory(
        "MerkleDistributor"
    );
    const merkleDistributor = await MerkleDistributor.deploy(
        owner.address,
        kwenta.address,
        rewardEscrow.address,
        merkleRoot
    );
    await merkleDistributor.deployed();
    await saveDeployments("MerkleDistributor", merkleDistributor);
    console.log(
        "MerkleDistributor deployed to:     ",
        merkleDistributor.address
    );

    console.log(
        "Total tokens in distribution:      ",
        wei(merkleDistributorInfo.tokenTotal, 18, true).toString()
    );

    return merkleDistributor;
}

async function deployMultipleMerkleDistributor(
    owner: SignerWithAddress,
    kwenta: Contract,
    rewardEscrow: Contract
) {
    const MultipleMerkleDistributor = await ethers.getContractFactory(
        "MultipleMerkleDistributor"
    );
    const multipleMerkleDistributor = await MultipleMerkleDistributor.deploy(
        owner.address,
        kwenta.address,
        rewardEscrow.address
    );
    await multipleMerkleDistributor.deployed();
    await saveDeployments(
        "MultipleMerkleDistributor",
        multipleMerkleDistributor
    );
    console.log(
        "TradingRewards deployed to:        ",
        multipleMerkleDistributor.address
    );
    return multipleMerkleDistributor;
}

/************************************************
 * @distributions
 ************************************************/

async function distributeKWENTA(
    signer: SignerWithAddress,
    kwenta: Contract,
    vKwentaRedeemer: Contract,
    merkleDistributor: Contract
) {
    // Transfer 5% KWENTA to vKwentaRedeemer
    await kwenta.transfer(
        vKwentaRedeemer.address,
        wei(INITIAL_SUPPLY).mul(0.05).toBN()
    );

    // Transfer 35% KWENTA to MerkleDistributor
    await kwenta.transfer(
        merkleDistributor.address,
        wei(INITIAL_SUPPLY).mul(0.35).toBN()
    );

    // Transfer 60% KWENTA to Treasury
    await kwenta.transfer(TREASURY_DAO, wei(INITIAL_SUPPLY).mul(0.6).toBN());

    console.log(
        "vKwentaRedeemer balance:     ",
        ethers.utils.formatEther(
            await kwenta.balanceOf(vKwentaRedeemer.address)
        )
    );
    console.log(
        "MerkleDistributor balance:   ",
        ethers.utils.formatEther(
            await kwenta.balanceOf(merkleDistributor.address)
        )
    );
    console.log(
        "TreasuryDAO balance:         ",
        ethers.utils.formatEther(await kwenta.balanceOf(TREASURY_DAO))
    );
    console.log(
        "Final signer balance:        ",
        ethers.utils.formatEther(await kwenta.balanceOf(signer.address))
    );
}

/************************************************
 * @saveDeployments
 ************************************************/

async function saveDeployments(name: string, contract: Contract) {
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

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
