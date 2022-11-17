import {expect} from 'chai';
import hre, {ethers} from 'hardhat';
import {Contract} from '@ethersproject/contracts';
import {FakeContract, smock} from '@defi-wonderland/smock';
import {SupplySchedule} from '../../../typechain/SupplySchedule';
import {StakingRewards} from '../../../typechain/StakingRewards';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';

describe('vKwenta Redemption', function () {
    const NAME = 'Kwenta';
    const SYMBOL = 'KWENTA';
    const KWENTA_INITIAL_SUPPLY = ethers.utils.parseUnits('313373'); // 313_373

    const vKWENTA_INITIAL_SUPPLY = ethers.utils.parseUnits('10000'); // 10_000
    const REDEEMER_KWENTA_SUPPLY = ethers.utils.parseUnits('9000'); // 9_000

    let kwenta: Contract;
    let vKwenta: Contract;
    let vKwentaRedeemer: Contract;

    let supplySchedule: FakeContract<SupplySchedule>;
    let stakingRewards: FakeContract<StakingRewards>;

    let owner: SignerWithAddress;
    let treasuryDAO: SignerWithAddress;
    let beneficiary: SignerWithAddress;
    let user1: SignerWithAddress;
    let user2: SignerWithAddress;

    beforeEach(async () => {
        [owner, treasuryDAO, beneficiary, user1, user2] =
            await ethers.getSigners();

        supplySchedule = await smock.fake('SupplySchedule');
        stakingRewards = await smock.fake('contracts/StakingRewards.sol:StakingRewards');

        // Deploy Kwenta (i.e. token)
        const Kwenta = await ethers.getContractFactory('Kwenta');
        kwenta = await Kwenta.deploy(
            NAME,
            SYMBOL,
            KWENTA_INITIAL_SUPPLY,
            owner.address,
            treasuryDAO.address
        );
        await kwenta.deployed();
        await kwenta.setSupplySchedule(supplySchedule.address);

        // Deploy vKwenta (i.e. vToken)
        const VKwenta = await ethers.getContractFactory('vKwenta');
        vKwenta = await VKwenta.deploy(
            NAME,
            SYMBOL,
            beneficiary.address,
            vKWENTA_INITIAL_SUPPLY
        );
        await vKwenta.deployed();

        // Deploy VKwentaRedeemer
        const VKwentaRedeemer = await ethers.getContractFactory(
            'vKwentaRedeemer'
        );
        vKwentaRedeemer = await VKwentaRedeemer.deploy(
            vKwenta.address,
            kwenta.address
        );
        await vKwentaRedeemer.deployed();

        // Fund VKwentaRedeemer with $KWENTA
        // @notice only sending vKwentaRedeemer 9_000 $KWENTA (10_000 exists)
        await hre.network.provider.send('hardhat_setBalance', [
            supplySchedule.address,
            '0x1000000000000000',
        ]);
        const impersonatedSupplySchedule = await ethers.getSigner(
            supplySchedule.address
        );
        await kwenta
            .connect(impersonatedSupplySchedule)
            .mint(vKwentaRedeemer.address, REDEEMER_KWENTA_SUPPLY);

        // Trasnfer $vKWENTA to user1
        await vKwenta
            .connect(beneficiary)
            .transfer(user1.address, ethers.utils.parseUnits('1000'));
    });

    it('balances are correct', async function () {
        expect(await vKwenta.balanceOf(beneficiary.address)).to.equal(
            ethers.utils.parseUnits('9000')
        );
        expect(await vKwenta.balanceOf(user1.address)).to.equal(
            ethers.utils.parseUnits('1000')
        );
        expect(await kwenta.balanceOf(vKwentaRedeemer.address)).to.equal(
            ethers.utils.parseUnits('9000')
        );
    });

    it('Caller without vKwenta cant redeem', async function () {
        expect(await vKwenta.balanceOf(user2.address)).to.equal(0);
        await expect(
            vKwentaRedeemer.connect(user2).redeem()
        ).to.be.revertedWith('vKwentaRedeemer: No balance to redeem');
    });

    it('User cannot redeem if vKwentaRedeemer is not approved to spend vKwenta', async function () {
        // attempt to redeem before approving
        await expect(
            vKwentaRedeemer.connect(beneficiary).redeem()
        ).to.be.revertedWith('ERC20: transfer amount exceeds allowance');
    });

    it('Can redeem kwenta for vKwenta', async function () {
        let beneficiaryBalanceToRedeem = await vKwenta.balanceOf(beneficiary.address);

        await vKwenta
            .connect(beneficiary)
            .approve(vKwentaRedeemer.address, beneficiaryBalanceToRedeem);
        await vKwentaRedeemer.connect(beneficiary).redeem();

        expect(await vKwenta.balanceOf(beneficiary.address)).to.equal(0);
        expect(await kwenta.balanceOf(beneficiary.address)).to.equal(
            beneficiaryBalanceToRedeem
        );
        expect(await kwenta.balanceOf(vKwentaRedeemer.address)).to.equal(0);
    });

    it('Can only redeem up to the amount of kwenta vKwentaRedeemer has', async function () {
        let beneficiaryBalanceToRedeem = await vKwenta.balanceOf(beneficiary.address);

        await vKwenta
            .connect(beneficiary)
            .approve(vKwentaRedeemer.address, beneficiaryBalanceToRedeem);
        await vKwentaRedeemer.connect(beneficiary).redeem();

        // @notice previous lines redeemed all kwenta in vKwentaRedeemer contract
        
        let user1BalanceToRedeem = await vKwenta.balanceOf(user1.address);

        await vKwenta
            .connect(user1)
            .approve(vKwentaRedeemer.address, user1BalanceToRedeem);
        await expect(
            vKwentaRedeemer.connect(user1).redeem()
        ).to.be.revertedWith('vKwentaRedeemer: Insufficient contract balance');
    });
});
