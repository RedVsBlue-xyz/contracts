import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';

require('dotenv').config();

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.20',
  },
  networks: {
    arbitrumGoerli: {
      url: 'https://goerli-rollup.arbitrum.io/rpc',
      chainId: 421613,
      accounts: [process.env.WALLET_KEY as string],
    },
    arbitrumOne: {
      url: 'https://arb1.arbitrum.io/rpc',
      accounts: [process.env.MAINNET_KEY as string],
    },
    arbitrumSepolia: {
      url: 'https://sepolia-rollup.arbitrum.io/rpc',
      accounts: [process.env.WALLET_KEY as string],
    }
  },
  defaultNetwork: 'hardhat',
  etherscan: {
    apiKey: {
     "base-goerli": "PLACEHOLDER_STRING",
     "arbitrumGoerli": process.env.ARBISCAN_API_KEY as string,
      "arbitrumOne": process.env.ARBISCAN_API_KEY as string,
      "arbitrumSepolia": process.env.ARBISCAN_API_KEY as string
    },
    customChains: [
      {
        network: "base-goerli",
        chainId: 84531,
        urls: {
         apiURL: "https://api-goerli.basescan.org/api",
         browserURL: "https://goerli.basescan.org"
        }
      },
      {
        network: "arbitrumSepolia",
        chainId: 421611,
        urls: {
         apiURL: "https://api-sepolia.basescan.org/api",
         browserURL: "https://sepolia.basescan.org"
        }
      }
    ]
  },
};

export default config;