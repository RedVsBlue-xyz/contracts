import { ethers } from 'hardhat';

async function main() {
  const redVsBlue = await ethers.deployContract('RedVsBlue');

  await redVsBlue.waitForDeployment();

  console.log('Bubbles Contract Deployed at ' + redVsBlue.target);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});