import stakerDistribution from './distribution/staker-distribution.json';
import traderDistribution from './distribution/trader-distribution.json';
import exploitedWallets from './distribution/gnosis_safe_wallets/exploited-wallets.json';
import savedWallets1 from './distribution/gnosis_safe_wallets/saved-wallets-1.json';
import savedWallets2 from './distribution/gnosis_safe_wallets/saved-wallets-2.json';
import { mergeDistributions } from './distribution/utils';
import { NewFormat } from './parse-balance-map';
import { ethers } from 'ethers';

// to run:
// npx hardhat run --network localhost scripts/blacklist-finder.ts

async function main() {
    let distributions: NewFormat[] = mergeDistributions(
        stakerDistribution,
        traderDistribution
    );
    
    // used for logging (later)
    let x = 0;
    let y = 0;
    let z = 0;

    // hash distributions for quick look-up
    let distributionsMap = new Map<string, string>();

    distributions.forEach(({ address }) => {
        // will throw if invalid address
        ethers.utils.getAddress(address);

        distributionsMap.set(address, address);
        x++;
    });

    // hash savedWallets for quick look-up
    let savedWalletsMap = new Map<string, string>();
    savedWallets1.forEach(({ data }) => {
        let address = data.multisig.slice(49, 91);

        // will throw if invalid address
        ethers.utils.getAddress(address);

        savedWalletsMap.set(address, address);
        y++;
    });
    savedWallets2.forEach(({ data }) => {
        let address = data.multisig.slice(49, 91);

        // will throw if invalid address
        ethers.utils.getAddress(address);

        savedWalletsMap.set(address, address);
        y++;
    });

    // hash exploitedWallets for quick look-up
    let exploitedWalletsMap = new Map<string, string>();
    exploitedWallets.forEach(({ data }) => {
        let address = data.multisig.slice(49, 91);

        // will throw if invalid address
        ethers.utils.getAddress(address);

        exploitedWalletsMap.set(address, address);
        z++;
    });

    // determine whitelisted and blacklisted multisig addresses
    let whitelisted: string[] = [];
    let blacklisted: string[] = [];
    let unaccounted: string[] = [];

    distributions.forEach(({ address }) => {
        if (exploitedWalletsMap.has(address)) {
            blacklisted.push(address);
        } else if (savedWalletsMap.has(address)) {
            whitelisted.push(address);
        } else {
            unaccounted.push(address);
        }
    });

    // log total number of *eligible for KWENTA* addresses that are:
    // (1) whitelisted
    // (2) blacklisted
    // (3) neither
    console.log('\n# of whitelisted: ' + whitelisted.length);
    console.log('# of blacklisted: ' + blacklisted.length);
    console.log('# of unaccounted: ' + unaccounted.length);

    // log total number of addresses that are:
    // (1) eligible for KWENTA
    // (2) saved by OE
    // (3) exploited by hack
    console.log('\ntotal distributions: ' + x);
    console.log('total savedWallets: ' + y);
    console.log('total exploitedWallets: ' + z + '\n');
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
