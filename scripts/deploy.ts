// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {wei} from '@synthetixio/wei';
import {Contract} from 'ethers';
import {ethers, upgrades} from 'hardhat';

const OWNER = '0xF510a2Ff7e9DD7e18629137adA4eb56B9c13E885';
const TREASURY_DAO = '0x82d2242257115351899894eF384f779b5ba8c695';
const INITIAL_SUPPLY = 313373;

// Pulled from StakingRewards.sol setWeeklyRewards()
/**
 * Friday: 6
 * Saturday: 5
 * Sunday: 4
 * Monday: 3
 * Tuesday: 2
 * Wednesday: 1
 * Thursday: 0
 */
const THURSDAY = 4; // Because EPOCH time starts on thursday
const distanceFromThursday = THURSDAY - new Date().getDay(); // Use current day
// Modulo expression to keep values within range:
// https://stackoverflow.com/a/50055050
// https://stackoverflow.com/a/4467559
const WEEKLY_START_REWARDS = ((distanceFromThursday % 7) + 7) % 7; // Equivalent to distance from next Thursday

const SYNTHETIX_ADDRESS_RESOLVER = '0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C';

async function main() {
    const [deployer] = await ethers.getSigners();

    const [fixidityLib, logarithmLib, exponentLib, safeDecimalMath] =
        await deployLibraries();

    console.log('\nBeginning deployments...');
    const kwenta = await deployKwenta(deployer);
    const supplySchedule = await deploySupplySchedule(
        deployer,
        safeDecimalMath
    );
    const rewardEscrow = await deployRewardEscrow(deployer, kwenta);
    console.log('EPOCH START DAY:', WEEKLY_START_REWARDS);
    const stakingRewards = await deployStakingRewards(
        deployer,
        fixidityLib,
        exponentLib,
        kwenta,
        rewardEscrow,
        supplySchedule
    );
    const exchangerProxy = await deployExchangerProxy(stakingRewards);
    console.log('Deployments complete!\n');

    console.log('Configuring setters...');
    // set SupplySchedule for kwenta
    await kwenta.setSupplySchedule(supplySchedule.address);
    console.log(
        'Kwenta: SupplySchedule address set to:',
        await kwenta.supplySchedule()
    );

    // set StakingRewards address in SupplySchedule
    await supplySchedule.setStakingRewards(stakingRewards.address);
    console.log(
        'SupplySchedule: StakingRewards address set to:',
        await supplySchedule.stakingRewards()
    );

    // set StakingRewards address in RewardEscrow
    await rewardEscrow.setStakingRewards(stakingRewards.address);
    console.log(
        'RewardEscrow: StakingRewards address set to:',
        await rewardEscrow.stakingRewards()
    );

    // set ExchangerProxy address in StakingRewards
    await stakingRewards.setExchangerProxy(exchangerProxy.address);
    console.log(
        'StakingRewards: ExchangerProxy address set to:',
        await stakingRewards.exchangerProxy()
    );
    console.log('Setters set!');

    // Switch ownership to multisig
}

async function deployLibraries() {
    // deploy FixidityLib
    const FixidityLib = await ethers.getContractFactory('FixidityLib');
    const fixidityLib = await FixidityLib.deploy();
    await fixidityLib.deployed();

    // deploy LogarithmLib
    const LogarithmLib = await ethers.getContractFactory('LogarithmLib', {
        libraries: {
            FixidityLib: fixidityLib.address,
        },
    });
    const logarithmLib = await LogarithmLib.deploy();
    await logarithmLib.deployed();

    // deploy ExponentLib
    const ExponentLib = await ethers.getContractFactory('ExponentLib', {
        libraries: {
            FixidityLib: fixidityLib.address,
            LogarithmLib: logarithmLib.address,
        },
    });
    const exponentLib = await ExponentLib.deploy();
    await exponentLib.deployed();

    // deploy SafeDecimalMath
    const SafeDecimalMath = await ethers.getContractFactory('SafeDecimalMath');
    const safeDecimalMath = await SafeDecimalMath.deploy();
    await safeDecimalMath.deployed();

    return [fixidityLib, logarithmLib, exponentLib, safeDecimalMath];
}

async function deployKwenta(owner: SignerWithAddress) {
    const Kwenta = await ethers.getContractFactory('Kwenta');
    const kwenta = await Kwenta.deploy(
        'Kwenta',
        'KWENTA',
        wei(INITIAL_SUPPLY).toBN(),
        owner.address,
        TREASURY_DAO
    );
    await kwenta.deployed();
    console.log('KWENTA token deployed to:', kwenta.address);
    return kwenta;
}

async function deploySupplySchedule(
    owner: SignerWithAddress,
    safeDecimalMath: Contract
) {
    const SupplySchedule = await ethers.getContractFactory('SupplySchedule', {
        libraries: {
            SafeDecimalMath: safeDecimalMath.address,
        },
    });
    const supplySchedule = await SupplySchedule.deploy(
        owner.address,
        TREASURY_DAO
    );
    console.log('SupplySchedule deployed to:', supplySchedule.address);
    await supplySchedule.deployed();
    return supplySchedule;
}

async function deployRewardEscrow(owner: SignerWithAddress, kwenta: Contract) {
    const RewardEscrow = await ethers.getContractFactory('RewardEscrow');
    const rewardEscrow = await RewardEscrow.deploy(
        owner.address,
        kwenta.address
    );
    await rewardEscrow.deployed();
    console.log('RewardEscrow deployed to:', rewardEscrow.address);
    return rewardEscrow;
}

async function deployStakingRewards(
    owner: SignerWithAddress,
    fixidityLib: Contract,
    exponentLib: Contract,
    kwenta: Contract,
    rewardEscrow: Contract,
    supplySchedule: Contract
) {
    const StakingRewards = await ethers.getContractFactory('StakingRewards', {
        libraries: {
            ExponentLib: exponentLib.address,
            FixidityLib: fixidityLib.address,
        },
    });

    const stakingRewardsProxy = await upgrades.deployProxy(
        StakingRewards,
        [
            owner.address,
            kwenta.address,
            rewardEscrow.address,
            supplySchedule.address,
            WEEKLY_START_REWARDS,
        ],
        {
            kind: 'uups',
            unsafeAllow: ['external-library-linking'],
        }
    );
    await stakingRewardsProxy.deployed();
    console.log('StakingRewards deployed to:', stakingRewardsProxy.address);
    return stakingRewardsProxy;
}

async function deployExchangerProxy(stakingRewards: Contract) {
    const ExchangerProxy = await ethers.getContractFactory('ExchangerProxy');
    const exchangerProxy = await ExchangerProxy.deploy(
        SYNTHETIX_ADDRESS_RESOLVER,
        stakingRewards.address
    );
    await exchangerProxy.deployed();
    console.log('ExchangerProxy token deployed to:', exchangerProxy.address);
    return exchangerProxy;
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
