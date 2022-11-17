import stakerDistribution from './distribution/staker-distribution.json';
import traderDistribution from './distribution/trader-distribution.json';
import multisigWallets from './distribution/L1-multisig-addresses.json';
import exploitedWallets from './distribution/gnosis_safe_wallets/exploited-wallets.json';
import savedWallets1 from './distribution/gnosis_safe_wallets/saved-wallets-1.json';
import savedWallets2 from './distribution/gnosis_safe_wallets/saved-wallets-2.json';
import { mergeDistributions } from './distribution/utils';
import { NewFormat } from './merkle/parse-balance-map';
import { ethers } from 'ethers';
import { network } from 'hardhat';
import dotenv from 'dotenv';

dotenv.config();

/*
 * to run:
 * npx ts-node scripts/blacklist-finder.ts
 *
 * @notice running this might take quite long... below is my output:
 * 
 
    ### DISTRIBUTION OVERVIEW ###
    Total # of distribution addresses: 5247
    Total # of multisig distribution addresses: 258
    Total # of EOA distribution addresses: 4989


    ### EXPLOIT OVERVIEW ###
    # of multisig wallets saved by OE: 22101
    # of multisig wallets exploited: 10044


    ### FINDINGS ###
    Total # of multisig distribution addresses that are whitelisted: 0
    Total # of multisig distribution addresses that are blacklisted: 0
    Total # of multisig distribution addresses that were not exploited NOR saved by OE: 258

 *
 */

const provider = new ethers.providers.JsonRpcProvider(
    process.env.L1_ARCHIVE_NODE_URL
);

async function main() {
    // addresses eligible for KWENTA distribution
    let distributions: NewFormat[] = mergeDistributions(
        stakerDistribution,
        traderDistribution
    );

    // for logging
    let savedWalletCount = 0;
    let exploitedWalletCount = 0;

    // hash savedWallets for quick look-up
    let savedWalletsMap = new Map<string, string>();
    savedWallets1.forEach(({ data }) => {
        let address = data.multisig.slice(49, 91);

        // will throw if invalid address
        ethers.utils.getAddress(address);

        savedWalletsMap.set(address, address);
        savedWalletCount++;
    });
    savedWallets2.forEach(({ data }) => {
        let address = data.multisig.slice(49, 91);

        // will throw if invalid address
        ethers.utils.getAddress(address);

        savedWalletsMap.set(address, address);
        savedWalletCount++;
    });

    // hash exploitedWallets for quick look-up
    let exploitedWalletsMap = new Map<string, string>();
    exploitedWallets.forEach(({ data }) => {
        let address = data.multisig.slice(49, 91);

        // will throw if invalid address
        ethers.utils.getAddress(address);

        exploitedWalletsMap.set(address, address);
        exploitedWalletCount++;
    });

    // determine whitelisted and blacklisted multisig addresses
    let multisig: string[] = []; // distribution addresses which are multisig
    let whitelisted: string[] = [];
    let blacklisted: string[] = [];
    let unaccounted: string[] = [];

    for (let i = 0; i < distributions.length; i++) {
        const address = distributions[i].address;

        // will throw if invalid address
        ethers.utils.getAddress(address);

        // is address multisig (contract)?
        let isMultisig = await isContract(address);

        // if address is contract (i.e. multisig) check if vulnerable
        if (isMultisig) {
            multisig.push(address);

            if (exploitedWalletsMap.has(address)) {
                blacklisted.push(address);
            } else if (savedWalletsMap.has(address)) {
                whitelisted.push(address);
            } else {
                unaccounted.push(address);
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                                LOGGING
    ///////////////////////////////////////////////////////////////*/

    logDistributionOverview(distributions, multisig);
    logExploitOverview(savedWalletCount, exploitedWalletCount);
    logFindings(whitelisted, blacklisted, unaccounted);

    // UNCOMMENT BELOW LINE TO SEE ALL MULTISIG ADDRESSES IN DISTRIBUTION
    // logMultisigs(multisig);
}

/*///////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
///////////////////////////////////////////////////////////////*/

async function isContract(address: string) {
    const code = await provider.getCode(address);
    return code !== '0x';
}

function logDistributionOverview(
    distributions: NewFormat[],
    multisig: string[]
) {
    // log total number of addresses that are:
    // (1) eligible for KWENTA
    // (2) saved by OE
    // (3) exploited by hack
    console.log('\n');
    console.log('### DISTRIBUTION OVERVIEW ###');
    console.log('Total # of distribution addresses: ' + distributions.length);
    console.log(
        'Total # of multisig distribution addresses: ' + multisig.length
    );
    console.log(
        'Total # of EOA distribution addresses: ' +
            (distributions.length - multisig.length)
    );
    console.log('\n');
}

function logExploitOverview(
    savedWalletCount: number,
    exploitedWalletCount: number
) {
    console.log('### EXPLOIT OVERVIEW ###');
    console.log('# of multisig wallets saved by OE: ' + savedWalletCount);
    console.log('# of multisig wallets exploited: ' + exploitedWalletCount);
    console.log('\n');
}

function logFindings(
    whitelisted: string[],
    blacklisted: string[],
    unaccounted: string[]
) {
    console.log('### FINDINGS ###');
    // log total number of *eligible for KWENTA* addresses that are:
    // (1) whitelisted
    // (2) blacklisted
    // (3) neither
    console.log(
        'Total # of multisig distribution addresses that are whitelisted: ' +
            whitelisted.length
    );
    console.log(
        'Total # of multisig distribution addresses that are blacklisted: ' +
            blacklisted.length
    );
    console.log(
        'Total # of multisig distribution addresses that were not exploited NOR saved by OE: ' +
            unaccounted.length
    );
    console.log('\n');
}

function logMultisigs(multisig: string[]) {
    console.log('### ALL MULTISIG ADDRESSES IN KWENTA DISTRIBUTION ###');
    for (let i = 0; i < multisig.length; i++) {
        console.log(multisig[i]);
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
