// deploy.ts
import { ethers } from "hardhat";

async function main() {
  console.log("Deploying contract...");
  // Compiling the contract
  const Token = await ethers.getContractFactory("ReachDistribution");
  // Deploying the contract
  const token = await Token.deploy();
  await token.waitForDeployment();
  const address = await token.getAddress();
  console.log(`Token deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
