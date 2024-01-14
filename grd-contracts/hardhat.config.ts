import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@nomiclabs/hardhat-ethers";
import { configDotenv } from "dotenv";
configDotenv();

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  networks: {
    hardhat: {
      forking: {
        url: `https://mainnet.infura.io/v3/${process.env.INFURA_KEY}}`,
        blockNumber: 13100000,
      },
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_KEY}}`,
      accounts: [`0x${process.env.PRIVATE_KEY}`], // Replace with your private key
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.INFURA_KEY}}`,
      accounts: [`0x${process.env.PRIVATE_KEY}`], // Replace with your private key
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.INFURA_KEY}}`,
      accounts: [`0x${process.env.PRIVATE_KEY}`], // Replace with your private key
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
