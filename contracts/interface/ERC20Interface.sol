// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

// 定义一个 ERC20 标准接口
interface ERC20Interface {

  // 定义一个名为 `balanceOf` 的函数，接受一个 `user` 地址作为参数，返回该地址的代币余额。
  // 该函数标记为 `external`，意味着它只能被外部合约或账户调用，不能被内部函数调用。
  // `view` 关键字表示该函数不会修改区块链上的状态，只进行读取操作。
  function balanceOf(address user) external view returns (uint256);
}
