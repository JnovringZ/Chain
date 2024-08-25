const { ethers, upgrades } = require("hardhat");



function sleep(time) {
    return new Promise((resolve) => setTimeout(resolve, time));
}



const contracts = {
    pancakeRouter: '0xB713d6D7386d5b0D8d66207387568E4E68BEdB78', //导入的是 Factory 和 usdc
    pancakeFactory: '0x5b1A3Fa067A2Fa802Bd9B19aFf1fd2c65cb07c26',
    multiSignature: '0xF8790238E10BddFEfD14955E76E116561591C730',
    multiSignatureToSToken: '0xF8790238E10BddFEfD14955E76E116561591C730',
    usdc: '0xB710660986701049d70fcfcAF633b270E530572c',
    fish: '0x03B43245A4dDFF76Ee3298e7e31585969D909dDe',
    fishOracle: '0xB010D53c42eabD3CeDCd66B06F475717370642B2',
    sFISH: '0xa5a6878d3ad5Ce2f1e22eB649814B31e7C37d445',
    dev: '0xA393CC2279B4d727cbf8FfC98B8b66C7aD5ECafe',
    op: '0xA393CC2279B4d727cbf8FfC98B8b66C7aD5ECafe',
    usdc_fish_lp: '0x2605855eE5ad9c0026F15632Df7a0e158a25eB94',
    fishNft: '0x8bdDB6274dFc0BfAB6DD6e04Ab51DEC79dBd7E16',
    usdcBuyNftLogic: '0x84744241211Dcfc8FffEbA8B2487F5F9Fb98F622'
}


async function main() {
    const [deployer] = await ethers.getSigners();

    var now = Math.round(new Date() / 1000);
    contracts.dev = deployer.address;
    contracts.op = deployer.address;
    console.log('部署人：', deployer.address);

    const PancakeRouter = await ethers.getContractFactory('PancakeRouter');
    const pancakeRouter = PancakeRouter.attach(contracts.pancakeRouter);
    console.log("pancakeRouter:", contracts.pancakeRouter);
    const PancakeFactory = await ethers.getContractFactory('PancakeFactory');
    const pancakeFactory = PancakeFactory.attach(contracts.pancakeFactory);
    console.log("pancakeFactory:", contracts.pancakeFactory);

    /**
     * 假USDC ERC20 (实盘不需要)
     */
    const USDCERC20 = await ethers.getContractFactory('FishERC20');
    if (contracts.usdc) {
        var usdc = USDCERC20.attach(contracts.usdc);
    } else {
        usdc = await upgrades.deployProxy(USDCERC20, ['USDC-test', 'TUSDC', deployer.address, '100000000000000000000000000'], { initializer: 'initialize' });
        await usdc.deployed();
    }
    contracts.usdc = usdc.address;
    console.log("usdc:", contracts.usdc);


    /**
     * FishERC20
     */
    const FishERC20 = await ethers.getContractFactory('FishERC20');
    if (contracts.fish) {
        var fish = FishERC20.attach(contracts.fish);
    } else {
        fish = await upgrades.deployProxy(FishERC20, ['Fish Token', 'FISH', deployer.address, '100000000000000000'], { initializer: 'initialize' });
        await fish.deployed();
    }
    contracts.fish = fish.address;
    console.log("fish:", contracts.fish);

    /**
     * 组流动性
     */

    await pancakeFactory.createPair(fish.address, usdc.address); //创建代币对
    await sleep(10000);
    var usdc_fish_lp_address = await pancakeFactory.getPair(fish.address, usdc.address); //查看代币对地址
    console.log("usdc_fish_lp_address:", usdc_fish_lp_address);
    contracts.usdc_fish_lp = usdc_fish_lp_address;
    console.log('arrived5');
    await usdc.approve(contracts.pancakeRouter, '1000000000000000000000000000000'); console.log("usdc.approve:");
    await fish.approve(contracts.pancakeRouter, '1000000000000000000000000000000'); console.log("fish.approve:");
    await pancakeRouter.addLiquidity(
        fish.address,
        usdc.address,
        '100000000000000000',//0.1 fish
        '1500000000000000000',//1.5u
        0,
        0,
        deployer.address,
        Math.round(new Date() / 1000) + 1000
    );
    console.log("addLiquidity");


    /**
     * FISHOracle
     */
    const FISHOracle = await ethers.getContractFactory('FISHOracle');
    if (contracts.fishOracle) {
        var fishOracle = FISHOracle.attach(contracts.fishOracle);
    } else {
        fishOracle = await upgrades.deployProxy(FISHOracle, [usdc_fish_lp_address, contracts.fish], { initializer: 'initialize' });
        await fishOracle.deployed();
    }
    await fishOracle.get('0x0000000000000000000000000000000000000000'); console.log("get:");
    contracts.fishOracle = fishOracle.address;
    console.log("fishOracle:", contracts.fishOracle);


    /**
     * sFISH
     */
    const SFISH = await ethers.getContractFactory('sFish');
    if (contracts.sFISH) {
        var sFISH = SFISH.attach(contracts.sFISH);
    } else {
        sFISH = await SFISH.deploy(fish.address);
        //定价
        await fish.approve(sFISH.address, '1000000000000000000000000000000'); console.log("fish.approve:sFISH");
        await fish.setExecutor(deployer.address, true); console.log("fish.setExecutor deployer.address");
        await fish.mint(deployer.address, '1000000000000000000');
        await sFISH.mint('1000000000000000000'); console.log("sFISH.mint");
    }
    contracts.sFISH = sFISH.address;
    console.log("sFISH:", contracts.sFISH);


    /**
     * fishNFT FishNft
     */
    const FishNft = await ethers.getContractFactory('FishNft');
    if (contracts.fishNft) {
        var fishNft = FishNft.attach(contracts.fishNft);
    } else {
        fishNft = await upgrades.deployProxy(FishNft, ["0xFishBone Nft", 'FB-NFT', contracts.fish], { initializer: 'initialize' });
        await fishNft.deployed();
    }
    contracts.fishNft = fishNft.address;
    console.log("fishNft:", contracts.fishNft);


    /**
     * UsdcBuyNftLogic
     */
    const UsdcBuyNftLogic = await ethers.getContractFactory('usdcBuyNftLogic');
    if (contracts.usdcBuyNftLogic) {
        var usdcBuyNftLogic = UsdcBuyNftLogic.attach(contracts.usdcBuyNftLogic);
    } else {
        usdcBuyNftLogic = await upgrades.deployProxy(UsdcBuyNftLogic, [
            contracts.fish,
            contracts.fishNft,
            contracts.pancakeFactory,
            contracts.pancakeRouter,
            contracts.multiSignature,
            contracts.multiSignatureToSToken,
            contracts.dev,
            contracts.op,
            contracts.sFISH,
            contracts.fishOracle,
            contracts.usdc], { initializer: 'initialize' });
        await usdcBuyNftLogic.deployed();
    }
    contracts.usdcBuyNftLogic = usdcBuyNftLogic.address;
    console.log("usdcBuyNftLogic:", contracts.usdcBuyNftLogic);

    //设置执行者
    await fish.setExecutor(contracts.fishNft, true); console.log("fish.setExecutor");
    await fish.setExecutor(contracts.usdcBuyNftLogic, true); console.log("fish.setExecutor");
    await fishNft.setExecutor(contracts.usdcBuyNftLogic, true); console.log("fishNft.setExecutor");


    //approve usdcBuyNftLogic 测试买入用
    await usdc.approve(contracts.usdcBuyNftLogic, '1000000000000000000000000000000');
    console.log("usdc.approve:usdcBuyNftLogic");



    console.log("////////////////////全部合约//////////////////////");
    console.log("contracts:", contracts);
    console.log("/////////////////////END/////////////////////");




}

main()
    .then(() => process.exit())
    .catch(error => {
        console.error(error);
        process.exit(1);
    })




