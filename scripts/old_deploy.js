const { ethers, upgrades } = require("hardhat");

function sleep(time) {
  return new Promise((resolve) => setTimeout(resolve, time));
}

const contracts = {
  // test
  testUSDC: "",
};

async function main() {
  const [deployer] = await ethers.getSigners();

  var now = Math.round(new Date() / 1000);
  console.log("部署人：", deployer.address);
  return;

  // //假U
  // const USDCERC20 = await ethers.getContractFactory('testERC20');
  // testUSDC = await USDCERC20.deploy('name', 'name');

  // contracts.testUSDC = testUSDC.address;
  // console.log("usdc:", contracts.testUSDC);
  // await testUSDC.setExecutor(deployer.address, true); console.log("setExecutor "); await sleep(1000);

  // console.log("////////////////////全部合约//////////////////////");
  // console.log("contracts:", contracts);
  // console.log("/////////////////////END/////////////////////");

  // return;
}

main()
  .then(() => process.exit())
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

//npx hardhat run --network polygon scripts/old_deploy.js
