import {expect} from 'chai';
import {ethers} from 'hardhat';
import {Contract} from '@ethersproject/contracts';
import {FakeContract, smock} from '@defi-wonderland/smock';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import L1CrossDomainMessenger from '@eth-optimism/contracts/artifacts/contracts/L1/messaging/L1CrossDomainMessenger.sol/L1CrossDomainMessenger.json';
import {utils} from 'ethers';

require('chai')
    .use(require('chai-as-promised'))
    .use(require('chai-bn-equal'))
    .use(smock.matchers)
    .should();

// reproduces abi.encodeWithSignature()
function generateMessage(
    index: number,
    account: string,
    destAccount: string,
    amount: number,
    merkleProof: string[]
) {
    const abiCoder = ethers.utils.defaultAbiCoder;
    const sig = ethers.utils
        .keccak256(
            ethers.utils.toUtf8Bytes(
                'claimToAddress(uint256,address,address,uint256,bytes32[])'
            )
        )
        .substring(0, 10)
        .concat('00000000000000000000000000000000'); // 32 bytes
    const messageWithoutSig = abiCoder
        .encode(
            ['uint256', 'address', 'address', 'uint256', 'bytes32[]'],
            [index, account, destAccount, amount, merkleProof]
        )
        .substring(34);
    return sig.concat(messageWithoutSig);
}

describe('Control L2 MerkleDistributor from L1', function () {
    let controlL2MerkleDistributor: Contract;
    let crossDomainMessenger: FakeContract;
    let user1: SignerWithAddress;
    const MerkleDistributorL2Address =
        '0x0000000000000000000000000000000000000000';

    beforeEach(async () => {
        [user1] = await ethers.getSigners();

        crossDomainMessenger = await smock.fake(L1CrossDomainMessenger);

        const ControlL2MerkleDistributor = await ethers.getContractFactory(
            'ControlL2MerkleDistributor'
        );
        controlL2MerkleDistributor = await ControlL2MerkleDistributor.deploy(
            crossDomainMessenger.address,
            MerkleDistributorL2Address
        );
        await controlL2MerkleDistributor.deployed();
    });

    it('Should call claimToAddress with correct parameters', async function () {
        const index = 0;
        const account = user1.address;
        const destAccount = user1.address;
        const amount = 0;
        const merkleProof = [
            // random proof
            '0x3685f6a73e4c1cae016dafe743462d3dfcf8ced4277dae3353c078fc1b6ba859',
            '0x6430c7c7042d2c643dd7db25384f984592d856412f1022a575fe2ea01b2ac59e',
        ];

        const message = generateMessage(index, account, destAccount, amount, merkleProof);

        await controlL2MerkleDistributor.claimToAddress(
            index,
            destAccount,
            amount,
            merkleProof
        );
        expect(crossDomainMessenger.sendMessage).to.have.been.calledWith(
            MerkleDistributorL2Address,
            message,
            1000000
        );
    });
});
