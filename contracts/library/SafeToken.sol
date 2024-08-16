// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;


import "../interface/ERC20Interface.sol";

library SafeToken {
  /**
   *  功能: 返回当前合约的代币余额。
      实现: 调用 ERC20Interface 接口的 balanceOf 函数，传入当前合约地址 address(this)，获取余额。
   */
  function myBalance(address token) internal view returns (uint256) {
    return ERC20Interface(token).balanceOf(address(this));
  }

  /**
   *  功能: 返回指定用户在指定代币合约中的余额。
      实现: 调用 ERC20Interface 接口的 balanceOf 函数，传入用户地址 user，获取余额。
   */
  function balanceOf(address token, address user) internal view returns (uint256) {
    return ERC20Interface(token).balanceOf(user);
  }

  /**
   *  功能: 安全地将指定数量的代币授权给指定地址。
      实现: 使用 abi.encodeWithSelector 构造 approve 函数的调用数据，然后通过 call 调用代币合约。检查调用是否成功，并验证返回数据是否符合预期。如果调用失败，触发 require 语句，回滚交易。
   */
  function safeApprove(address token, address to, uint256 value) internal {
    // bytes4(keccak256(bytes('approve(address,uint256)')));
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeApprove");
  }

  /**
   * 功能: 安全地将指定数量的代币转移给指定地址。
     实现: 使用 abi.encodeWithSelector 构造 transfer 函数的调用数据，然后通过 call 调用代币合约。检查调用是否成功，并验证返回数据是否符合预期。如果调用失败，触发 require 语句，回滚交易。
   */
  function safeTransfer(address token, address to, uint256 value) internal {
    // bytes4(keccak256(bytes('transfer(address,uint256)')));
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransfer");
  }

  /**
   *  功能: 安全地从一个地址转移指定数量的代币到另一个地址。
      实现: 使用 abi.encodeWithSelector 构造 transferFrom 函数的调用数据，然后通过 call 调用代币合约。检查调用是否成功，并验证返回数据是否符合预期。如果调用失败，触发 require 语句，回滚交易。
   */
  function safeTransferFrom(address token, address from, address to, uint256 value) internal {
    // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
    require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransferFrom");
  }


}