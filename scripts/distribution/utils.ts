import { wei } from '@synthetixio/wei';
import { ethers } from 'ethers';
import { NewFormat } from '../merkle/parse-balance-map';

export type SerializedWei = {
    p: number;
    bn: {
        type: string;
        hex: string;
    };
};

// Older versions of wei serialized Wei as objects
export const reconstructWei = (weiObject: SerializedWei) =>
    wei(ethers.BigNumber.from(weiObject.bn.hex).toString(), weiObject.p, true);

export function mergeDistributions(
    stakerDistribution: NewFormat[],
    traderDistribution: NewFormat[]
) {
    let distributions: { [address: string]: NewFormat } = {};
    stakerDistribution.forEach(({ address, earnings }) => {
        distributions[address] = {
            address,
            earnings,
        };
    });

    traderDistribution.forEach(({ address, earnings }) => {
        if (!distributions[address]) {
            distributions[address] = {
                address,
                earnings,
            };
        } else {
            distributions[address] = {
                ...distributions[address],
                earnings: wei(distributions[address].earnings, 18, true)
                    .add(wei(earnings, 18, true))
                    .toString(0, true),
            };
        }
    });

    return Object.values(distributions);
}
