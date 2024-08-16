// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
 */
interface IERC20 {
    // 返回代币的小数位数。大多数代币使用 18 位小数，表示代币的最小单位
    function decimals() external view returns (uint8);
    // 返回代币的名称
    function name() external view returns (string memory);
    // 返回代币的符号，比如 "MTK"
    function symbol() external view returns (string memory);
    /**
     * @dev Returns the amount of tokens in existence.
     */
    // 返回已发行的代币总量
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    // 返回指定地址 `account` 拥有的代币数量
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    // 从调用者的账户中转移 `amount` 数量的代币到 `recipient` 地址。
    // 返回一个布尔值，表示操作是否成功。
    // 触发 `Transfer` 事件。
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    // 返回 `spender` 被允许代表 `owner` 花费的剩余代币数量。
    // 默认情况下，这个值是 0。
    // 当 `approve` 或 `transferFrom` 被调用时，这个值会发生变化
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    // 设置 `spender` 被允许代表调用者花费的代币数量为 `amount`。
    // 返回一个布尔值，表示操作是否成功。
    // 注意：使用这个方法更改允许额度时，可能会有交易顺序导致的竞态条件问题（旧的和新的允许额度可能会同时生效）。一种可能的解决方案是先将允许额度设为 0，然后再设置为期望的值。
    // 触发 `Approval` 事件。
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    // 使用允许额度机制，将 `amount` 数量的代币从 `sender` 转移到 `recipient`。
    // 代币数量 `amount` 随后会从调用者的允许额度中扣除。
    // 返回一个布尔值，表示操作是否成功。
    // 触发 `Transfer` 事件。
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

      /**
     * EXTERNAL FUNCTION
     *
     * @dev change token name
     * @param _name token name
     * @param _symbol token symbol
     *
     */
    // 外部函数，用于更改代币的名称和符号。
    // 接受两个参数 `_name` 和 `_symbol`，分别表示新的代币名称和符号
    function changeTokenName(string calldata _name, string calldata _symbol)external;

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}