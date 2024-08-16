require('@nomiclabs/hardhat-ethers');

module.exports = {
  solidity: {
    version: "0.8.24", // 或者你的合约使用的 Solidity 版本
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true // 启用 Intermediate Representation 编译
    }
  }
};
