import { ethers } from 'hardhat';

async function main() {
  const colorClash = await ethers.deployContract('ColorClash');

  await colorClash.waitForDeployment();

  console.log('Colors Contract Deployed at ' + colorClash.target);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});