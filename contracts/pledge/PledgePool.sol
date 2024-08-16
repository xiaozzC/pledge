// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../library/SafeTransfer.sol";
import "../interface/IDebtToken.sol";
import "../interface/IBscPledgeOracle.sol";
import "../interface/IUniswapV2Router02.sol";
import "../multiSignature/multiSignatureClient.sol";


contract PledgePool is ReentrancyGuard, SafeTransfer, multiSignatureClient{

    using SafeMath for uint256;
    using SafeERC20 for uint256; 

    // 内部使用的精度因子，用于计算中以标准化数值
    uint256 constant internal calDecimal = 1e18;
    // 基于佣金和利息的精度因子， 1e8（表示百分比）
    uint256 constant internal baseDecimal = 1e8;
    // 最小金额，设定为 100 个单位，乘以 calDecimal（即 100e18）
    uint256 public minAmount = 100e18;
    // 表示一年为 365 天，用于时间相关的计算
    uint256 constant baseYear = 365 days;

    // 池的不同状态，包括匹配（MATCH）、执行（EXECUTION）、完成（FINISH）、清算（LIQUIDATION）和未完成（UNDONE）
    enum PoolState{ MATCH, EXECUTION, FINISH, LIQUIDATION, UNDONE }
    // 默认状态为 MATCH，通常表示池在匹配阶段
    PoolState constant defaultChoice = PoolState.MATCH;
    // 全局暂停标志，当为 true 时，表示合约可能暂停执行某些操作
    bool public globalPaused = false;

    // 表示 PancakeSwap 交换路由合约的地址，用于代币交换
    address public swapRouter;
    // 用于接收费用的地址
    address payable public feeAddress;
    // 价格预言机合约的地址，通常用于获取资产价格
    IBscPledgeOracle public oracle;
    //借出和借入的手续费
    uint256 public lendFee;
    uint256 public borrowFee;

    // 借贷池的基本信息
    struct PoolBaseInfo{
        uint256 settleTime;       //结算时间
        uint256 endTime;          //结束时间
        uint256 interestRate;     //固定利率，以 baseDecimal 为单位
        uint256 maxSupply;        //池的最大供应量
        uint256 lendSupply;       //当前借出的实际存款
        uint256 borrowSupply;     //当前借入的实际存款
        uint256 martgageRate;     //池的抵押率
        address lendToken;        //借出的代币地址
        address borrowToken;      //借入的代币地址
        PoolState state;          //当前池的状态
        IDebtToken spCoin;        //用于表示特殊债务代币的 ERC20 地址
        IDebtToken jpCoin;        
        uint256 autoLiquidateThreshold; //自动清算阈值
    }
    PoolBaseInfo[] public poolBaseInfo;

    // 每个借贷池的数据
    struct PoolDataInfo{
        uint256 settleAmountLend;       //出借者的实际出资总额
        uint256 settleAmountBorrow;     //借入者实际借入的总额
        uint256 finishAmountLend;       //出借者在结束时应得的总额
        uint256 finishAmountBorrow;     //借入者在结束时应付的总额
        uint256 liquidationAmounLend;   //实际清算的金额
        uint256 liquidationAmounBorrow; //清算时的偿还总额
    }
    PoolDataInfo[] public poolDataInfo;

    
    // 用户在某个池中的借入信息
    struct BorrowInfo {
        uint256 stakeAmount;          //用户的当前质押金额
        uint256 refundAmount;         //多余的退款金额
        bool hasNoRefund;             //是否已经退款
        bool hasNoClaim;              //是否已经已领取
    }
    mapping (address => mapping (uint256 => BorrowInfo)) public userBorrowInfo;

    // 用户在某个池中的借出信息,结构与 BorrowInfo 类似
    struct LendInfo {
        uint256 stakeAmount;          
        uint256 refundAmount;         
        bool hasNoRefund;             
        bool hasNoClaim;              
    }
    mapping (address => mapping (uint256 => LendInfo)) public userLendInfo;

    // event
    event DepositLend(address indexed from,address indexed token,uint256 amount,uint256 mintAmount);
    event RefundLend(address indexed from, address indexed token, uint256 refund);
    event ClaimLend(address indexed from, address indexed token, uint256 amount);
    event WithdrawLend(address indexed from,address indexed token,uint256 amount,uint256 burnAmount);
    event DepositBorrow(address indexed from,address indexed token,uint256 amount,uint256 mintAmount);
    event RefundBorrow(address indexed from, address indexed token, uint256 refund);
    event ClaimBorrow(address indexed from, address indexed token, uint256 amount);
    event WithdrawBorrow(address indexed from,address indexed token,uint256 amount,uint256 burnAmount);
    event Swap(address indexed fromCoin,address indexed toCoin,uint256 fromValue,uint256 toValue);
    event EmergencyBorrowWithdrawal(address indexed from, address indexed token, uint256 amount);
    event EmergencyLendWithdrawal(address indexed from, address indexed token, uint256 amount);
    event StateChange(uint256 indexed pid, uint256 indexed beforeState, uint256 indexed afterState);

    event SetFee(uint256 indexed newLendFee, uint256 indexed newBorrowFee);
    event SetSwapRouterAddress(address indexed oldSwapAddress, address indexed newSwapAddress);
    event SetFeeAddress(address indexed oldFeeAddress, address indexed newFeeAddress);
    event SetMinAmount(uint256 indexed oldMinAmount, uint256 indexed newMinAmount);

    /**
     * 
     * @param _oracle 价格预言机合约的地址
     * @param _swapRouter 去中心化交易所的路由合约地址
     * @param _feeAddress 接收手续费的地址
     * @param _multiSignature 多签名合约的地址，用于验证交易的合法性
     */
    constructor(
        address _oracle,
        address _swapRouter,
        address payable _feeAddress,
        address _multiSignature
    ) multiSignatureClient(_multiSignature) {
        require(_oracle != address(0), "Is zero address");
        require(_swapRouter != address(0), "Is zero address");
        require(_feeAddress != address(0), "Is zero address");

        oracle = IBscPledgeOracle(_oracle);
        swapRouter = _swapRouter;
        feeAddress = _feeAddress;
        lendFee = 0;
        borrowFee = 0;
    }

    // 设置借贷相关的费用
    function setFee(uint256 _lendFee,uint256 _borrowFee) validCall external{
        lendFee = _lendFee;
        borrowFee = _borrowFee;
        emit SetFee(_lendFee, _borrowFee);
    }
    
    // 设置交换路由器的地址，于去中心化交易所的代币交换
    function setSwapRouterAddress(address _swapRouter) validCall external{
        require(_swapRouter != address(0),"Is zero address");
        emit SetSwapRouterAddress(swapRouter, _swapRouter);
        swapRouter = _swapRouter;
    }

    // 设置接收手续费地址
    function setFeeAddress(address payable _feeAddress) validCall external{
        require(_feeAddress != address(0),"Is zero address");
        emit SetFeeAddress(feeAddress, _feeAddress);
        feeAddress = _feeAddress;
    }

    // 设置最小金额
    function setMinAmount(uint256 _minAmount) validCall external{
        emit SetMinAmount(minAmount, _minAmount);
        minAmount = _minAmount;
    }

    // 借贷池长度
    function poolLength() external view returns (uint256) {
        return poolBaseInfo.length;
    }

     /**
     * @dev set Pause
     */
    function setPause() public validCall {
        globalPaused = !globalPaused;
    }

    // 创建新的资金池，并初始化资金池的基本信息和相关数据
    function createPoolInfo(uint256 _settleTime,uint256 _endTime, uint64 _interestRate,
                        uint256 _maxSupply, uint256 _martgageRate, address _lendToken, address _borrowToken,
                    address _spToken, address _jpToken, uint256 _autoLiquidateThreshold) public validCall{
        // 结束时间大于结算时间 
        require(_endTime > _settleTime,"createPool:end time grate than settle time");
        // 确保债务代币的合约地址是有效的
        require(_jpToken != address(0) && _spToken != address(0),"createPool:is zero address");

        poolBaseInfo.push(PoolBaseInfo({
            settleTime: _settleTime,
            endTime: _endTime,
            interestRate: _interestRate,
            maxSupply: _maxSupply,
            lendSupply:0,
            borrowSupply:0,
            martgageRate: _martgageRate,
            lendToken:_lendToken,
            borrowToken:_borrowToken,
            state: defaultChoice,
            spCoin: IDebtToken(_spToken),
            jpCoin: IDebtToken(_jpToken),
            autoLiquidateThreshold:_autoLiquidateThreshold
        }));

        poolDataInfo.push(PoolDataInfo({
            settleAmountLend:0,
            settleAmountBorrow:0,
            finishAmountLend:0,
            finishAmountBorrow:0,
            liquidationAmounLend:0,
            liquidationAmounBorrow:0
        }));
    }

    // 确保合约的相关功能在全局暂停状态下不可用
    modifier notPause() {
        require(globalPaused == false, "Stake has been suspended");
        _;
    }

    // 检查当前时间 block.timestamp 是否小于指定池 poolBaseInfo[_pid].settleTime
    modifier timeBefore(uint256 _pid) {
        require(block.timestamp < poolBaseInfo[_pid].settleTime, "Less than this time");
        _;
    }

    // 检查当前时间 block.timestamp 是否大于指定池 poolBaseInfo[_pid].settleTime
    modifier timeAfter(uint256 _pid) {
        require(block.timestamp > poolBaseInfo[_pid].settleTime, "Greate than this time");
        _;
    }

    // 检查指定池的状态 poolBaseInfo[_pid].state 是否为匹配
    modifier stateMatch(uint256 _pid) {
        require(poolBaseInfo[_pid].state == PoolState.MATCH, "state: Pool status is not equal to match");
        _;
    }

    // 检查指定池的状态是否为执行（EXECUTION）、完成（FINISH）、清算（LIQUIDATION）
    modifier stateNotMatchUndone(uint256 _pid) {
        require(poolBaseInfo[_pid].state == PoolState.EXECUTION || poolBaseInfo[_pid].state == PoolState.FINISH || poolBaseInfo[_pid].state == PoolState.LIQUIDATION,"state: not match and undone");
        _;
    }

    // 检查指定池的状态是否为完成（FINISH）、清算（LIQUIDATION）
    modifier stateFinishLiquidation(uint256 _pid) {
        require(poolBaseInfo[_pid].state == PoolState.FINISH || poolBaseInfo[_pid].state == PoolState.LIQUIDATION,"state: finish liquidation");
        _;
    }

    // 检查指定池的状态是否为未完成
    modifier stateUndone(uint256 _pid) {
        require(poolBaseInfo[_pid].state == PoolState.UNDONE,"state: state must be undone");
        _;
    }

    // 获取指定资金池的当前状态
    function getPoolState(uint256 _pid) public view returns (uint256) {
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        return uint256(pool.state);
    }

    /**
     *  用户存款
     * @param _pid 池的索引
     * @param _stakeAmount 用户存入的金额
     */
    function depositLend(uint256 _pid, uint256 _stakeAmount) external payable nonReentrant notPause timeBefore(_pid) stateMatch(_pid){
        // limit of time and state
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        // Boundary conditions 确保 _stakeAmount 不超过池的最大供应量 maxSupply 减去当前的 lendSupply
        require(_stakeAmount <= (pool.maxSupply).sub(pool.lendSupply), "depositLend: the quantity exceeds the limit");
        // 获取实际支付金额 amount，并确保这个金额大于最小金额 minAmount
        uint256 amount = getPayableAmount(pool.lendToken,_stakeAmount);
        require(amount > minAmount, "depositLend: less than min amount");

        // Save lend user information
        // 表示用户还没有索赔或退款
        lendInfo.hasNoClaim = false;
        lendInfo.hasNoRefund = false;

        // 如果池的 lendToken 是地址 0（即用户存入的是 ETH）
        if (pool.lendToken == address(0)){
            // 将用户的存款 msg.value 增加到 lendInfo.stakeAmount
            lendInfo.stakeAmount = lendInfo.stakeAmount.add(msg.value);
            pool.lendSupply = pool.lendSupply.add(msg.value);
        } else {
            // 将 _stakeAmount 增加到 lendInfo.stakeAmount
            lendInfo.stakeAmount = lendInfo.stakeAmount.add(_stakeAmount);
            pool.lendSupply = pool.lendSupply.add(_stakeAmount);
        }
        emit DepositLend(msg.sender, pool.lendToken, _stakeAmount, amount);
    }

    /**
     * 处理用户的退款操作
     * @param _pid 池的索引
     */
    function refundLend(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];

        // 确保用户的 stakeAmount 大于 0，表示用户有存款
        require(lendInfo.stakeAmount > 0,"refundLend: not pledged");
        // 确保池的可退款金额（lendSupply 减去已结算的金额 settleAmountLend）大于 0
        require(pool.lendSupply.sub(data.settleAmountLend) > 0, "refundLend: not refund");
        // 确保用户之前没有申请过退款，hasNoRefund 为 false
        require(!lendInfo.hasNoRefund, "refundLend: repeat refund");

        // 计算用户在池中的份额比例
        uint256 userShare = lendInfo.stakeAmount.mul(calDecimal).div(pool.lendSupply);
        // 实际退款金额,池的可退款金额乘以用户的份额比例
        uint256 refundAmount = (pool.lendSupply.sub(data.settleAmountLend)).mul(userShare).div(calDecimal);
        // 将计算出的 refundAmount 退还给用户
        _redeem(payable(msg.sender),pool.lendToken,refundAmount);

        // update user info
        // 表示用户已经申请过退款
        lendInfo.hasNoRefund = true;
        // 将已退款金额增加 refundAmount
        lendInfo.refundAmount = lendInfo.refundAmount.add(refundAmount);
        emit RefundLend(msg.sender, pool.lendToken, refundAmount);
    }

    /**
     * 存款人从池子中提取本金和利息，适用于池子状态为 FINISH（完成）或 LIQUIDATION（清算）时
     * @param _pid 池的索引
     * @param _spAmount 要销毁的 SP 代币数量
     */
    function withdrawLend(uint256 _pid,uint256 _spAmount) external nonReentrant notPause stateFinishLiquidation(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];

        require(_spAmount > 0, 'withdrawLend: withdraw amount is zero');
        // 调用 SP 代币的 burn 方法，销毁指定数量的 SP 代币
        pool.spCoin.burn(msg.sender,_spAmount);   
        // 在结算时的总 SP 代币数量
        uint256 totalSpAmount = data.settleAmountLend;
        // spShare 计算为 _spAmount 占 totalSpAmount 的比例，并调整为 calDecimal 的比例
        uint256 spShare = _spAmount.mul(calDecimal).div(totalSpAmount);

        // 处理池子状态为 FINISH（完成）
        if(pool.state == PoolState.FINISH){
            require(block.timestamp > pool.endTime, "withdrawLend: less than end time");
            // 计算赎回金额: 基于 finishAmountLend 和 spShare 计算用户的赎回金额
            uint256 redeemAmount = data.finishAmountLend.mul(spShare).div(calDecimal);
            // 将计算出的 refundAmount 退还给用户
            _redeem(payable(msg.sender), pool.lendToken, redeemAmount);
            emit WithdrawLend(msg.sender, pool.lendToken, redeemAmount, _spAmount);
        }

        // 处理池子状态为 LIQUIDATION（清算）
        if(pool.state == PoolState.LIQUIDATION){
            require(block.timestamp > pool.settleTime, "withdrawLend: less than match time");
            uint256 redeemAmount = data.liquidationAmounLend.mul(spShare).div(calDecimal);
            _redeem(payable(msg.sender), pool.lendToken, redeemAmount);
            emit WithdrawLend(msg.sender, pool.lendToken, redeemAmount, _spAmount);
        }
    }

    /**
     * @dev 紧急撤回借出的资金
     * @notice 池的状态必须是未完成的
     * @param _pid 池的索引
     */
    function emergencyLendWithdrawal(uint256 _pid) external nonReentrant notPause stateUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        // 确保池中有借出的资金可以撤回
        require(pool.lendSupply > 0 , "emergencLend: not withdrawal");

        LendInfo storage lendInfo = userLendInfo[msg.sender][_pid];
        // 确保用户有质押的金额
        require(lendInfo.stakeAmount > 0,"refundLend: not pledged");
        // 确保用户还没有进行过退款操作
        require(!lendInfo.hasNoRefund,"refundLend: again refund");

        // 执行赎回操作，将借出的资金返还给用户
        _redeem(payable(msg.sender), pool.lendToken, lendInfo.stakeAmount);

        // 更新用户的借出信息，标记为已经退款
        lendInfo.hasNoRefund = true;

        emit EmergencyBorrowWithdrawal(msg.sender, pool.lendToken, lendInfo.stakeAmount);
    }

    /**
     * @dev 借款人的质押操作(借款人在借款前将一定数量的代币或以太币存入池中作为担保)
     * @param _pid 是池的索引
     * @param _stakeAmount 是用户质押的金额
     */
    function depositBorrow(uint256 _pid,uint256 _stakeAmount) external payable nonReentrant notPause timeBefore(_pid) stateMatch(_pid){
        //基本信息
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];

        // 获取实际支付的金额
        uint256 amount = getPayableAmount(pool.borrowToken, _stakeAmount);

        // 确保质押的金额大于零
        require(amount > 0 ,"depositBorrow: deposit amount is zero");

        // 更新信息
        borrowInfo.hasNoRefund = false;
        borrowInfo.hasNoClaim = false;
        
        if(pool.lendToken == address(0)){
            // 如果质押的代币是以太币，使用msg.value来更新金额
            borrowInfo.stakeAmount = borrowInfo.stakeAmount.add(msg.value);
            pool.borrowSupply = pool.borrowSupply.add(msg.value);
        }else{
            // 如果质押的是其他代币，使用传入的参数更新金额
            borrowInfo.stakeAmount = borrowInfo.stakeAmount.add(_stakeAmount);
            pool.borrowSupply = pool.borrowSupply.add(_stakeAmount);
        }
        emit DepositBorrow(msg.sender, pool.borrowToken, _stakeAmount, amount);
    }

    /**
     * @dev 退还借款人的多余质押金额
     * @notice 资金池的状态必须不等于匹配或未完成
     * @param _pid 资金池的状态
     */
    function refundBorrow(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];

        // 检查资金池中是否有多余的借款金额可退还
        require(pool.borrowSupply.sub(data.settleAmountBorrow) > 0 ,"refundBorrow: not refund");
        // 确保用户在资金池中有质押的金额
        require(borrowInfo.stakeAmount > 0,"refundBorrow: not pledged");
        // 确保用户尚未进行过退款操作
        require(!borrowInfo.hasNoRefund , "refundBorrow: again refund");

        // 计算用户份额
        uint256 userShare = borrowInfo.stakeAmount.mul(calDecimal).div(pool.borrowSupply);
        // 计算用户应退还的金额
        uint256 refundAmount = (pool.borrowSupply.sub(data.settleAmountBorrow)).mul(userShare).div(calDecimal);

        // 执行退款操作
        _redeem(payable(msg.sender), pool.borrowToken, refundAmount);

        // 更新用户信息
        borrowInfo.hasNoRefund = true;
        borrowInfo.refundAmount = borrowInfo.refundAmount.add(refundAmount);

        emit RefundBorrow(msg.sender, pool.borrowToken, refundAmount);
    }

    /**
     * @dev 借款人领取 sp_token 和借款资金
     * @notice 资金池状态必须不等于匹配和未完成
     * @param _pid 资金池的状态
     */
    function claimBorrow(uint256 _pid) external nonReentrant notPause timeAfter(_pid) stateNotMatchUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];

        // 确保用户在资金池中有质押金额
        require(borrowInfo.stakeAmount > 0 ,"claimBorrow: not claim jp_token");
        //  确保用户尚未领取过 jp_token 和借款资金
        require(!borrowInfo.hasNoClaim , "claimBorrow: again claim");

        //  计算资金池中总的 jp_token 数量，基于借出的资金总量 settleAmountLend 和质押率 martgageRate
        uint256 totalJpAmount = data.settleAmountLend.mul(pool.martgageRate).div(baseDecimal);

        // 计算用户份额
        uint256 userShare = borrowInfo.stakeAmount.mul(calDecimal).div(pool.borrowSupply);
        // 计算用户应领取的 jp_token 数量
        uint256 jpAmount = totalJpAmount.mul(userShare).div(calDecimal);

        // 生成（mint） jp_token 并分发给用户
        pool.jpCoin.mint(msg.sender, jpAmount);

        // 领取借款资金
        uint256 borrowAmount = data.settleAmountLend.mul(userShare).div(calDecimal);

        _redeem(payable(msg.sender), pool.lendToken, borrowAmount);

        borrowInfo.hasNoClaim = true;
        
        emit ClaimBorrow(msg.sender, pool.lendToken, borrowAmount);
    }

    /**
     * @dev 借款人提取剩余保证金
     * @param _pid 资金池的索引
     * @param _jpAmount 是用户销毁的 JP 代币数量
     */
    function withdrawBorrow(uint _pid,uint _jpAmount) external nonReentrant notPause stateFinishLiquidation(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];

        require(_jpAmount > 0 ,"withdrawBorrow: withdraw amount is zero");
        
        // 销毁 JP 代币
        pool.jpCoin.burn(msg.sender, _jpAmount);

        // 计算资金池中总的 JP 代币数量
        uint256 totalJpAmount = data.settleAmountLend.mul(pool.martgageRate).div(baseDecimal);
        uint256 jpShare = _jpAmount.mul(calDecimal).div(totalJpAmount);

        if(pool.state == PoolState.FINISH){
            // 确保当前时间已经超过资金池的结束时间
            require(block.timestamp > pool.endTime, "withdrawBorrow: less than end time");

            // 计算可提取的金额
            uint256 redeemAmount = jpShare.mul(data.finishAmountBorrow).div(calDecimal);

            _redeem(payable(msg.sender), pool.borrowToken, redeemAmount);

            emit WithdrawBorrow(msg.sender, pool.borrowToken, _jpAmount, redeemAmount);
        }

        if(pool.state == PoolState.LIQUIDATION){
            // 确保当前时间已经超过资金池的结算时间
            require(block.timestamp > pool.settleTime ,"withdrawBorrow: less than match time");

            uint256 redeemAmount = jpShare.mul(data.liquidationAmounBorrow).div(calDecimal);

            _redeem(payable(msg.sender), pool.borrowToken, redeemAmount);

            emit WithdrawBorrow(msg.sender, pool.borrowToken, _jpAmount, redeemAmount);
        }

    }

    /**
     * @dev 借款人的紧急撤资操作
     * @notice 在极端情况下执行，例如总存款为 0 或总保证金为 0
     * @param _pid 资金池的索引
     */
    function emergencyBorrowWithdrawal(uint256 _pid) external nonReentrant notPause stateUndone(_pid){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];

        // 确保资金池的借款供应量大于 0
        require(pool.borrowSupply > 0,"emergencyBorrow: not withdrawal");

        //借款人信息
        BorrowInfo storage borrowInfo = userBorrowInfo[msg.sender][_pid];
        // 确保借款人有质押金额
        require(borrowInfo.stakeAmount > 0,"refundBorrow: not pledged");
        // 确保借款人还没有退款
        require(!borrowInfo.hasNoRefund, "refundBorrow: again refund");

        _redeem(payable(msg.sender), pool.borrowToken, borrowInfo.stakeAmount);

        emit EmergencyBorrowWithdrawal(msg.sender, pool.borrowToken, borrowInfo.stakeAmount);
    }

    /**
     * @dev 是否可以结算
     * @param _pid 资金池的索引
     */
    function checkoutSettle(uint256 _pid) public view returns(bool){
        return block.timestamp > poolBaseInfo[_pid].settleTime;
    }

    /**
     * 获取最新的预言机价格
     * @param _pid 资金池的索引
     */
    function getUnderlyingPriceView(uint256 _pid) public view returns(uint[2] memory){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        uint256[] memory assets = new uint256[](2);
        assets[0] = uint256(uint160(pool.lendToken));
        assets[1] = uint256(uint160(pool.borrowToken));
        uint256[]memory prices = oracle.getPrices(assets);
        return [prices[0],prices[1]];
    }
    

    /**
     * 结算
     * @param _pid 资金池的索引
     */
    function settle(uint256 _pid) public validCall{
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];

        // 确保当前时间已经超过资金池的结算时间
        require(block.timestamp > pool.settleTime, "settle: less than settleTime");
        // 确保资金池的状态为匹配（MATCH）
        require(pool.state == PoolState.MATCH, "settle: pool state must be match");

        if(pool.lendSupply > 0 && pool.borrowSupply > 0){
            // 获取基础资产的价格
            uint256[2] memory prices = getUnderlyingPriceView(_pid);
            // 总保证金价值 = 保证金额 * 保证金价格
            uint256 totalValue = pool.borrowSupply.mul(prices[1].mul(calDecimal).div(prices[0])).div(calDecimal);
            // 转换为稳定币的价值
            uint256 actualValue = totalValue.mul(baseDecimal).div(pool.martgageRate);

            if(pool.lendSupply > actualValue){
                // 当借贷供应量大于实际价值时
                data.settleAmountLend = actualValue;
                data.settleAmountBorrow = pool.lendSupply;
            }else{
                 // 当借贷供应量小于实际价值时
                 data.settleAmountLend = pool.lendSupply;
                 data.settleAmountBorrow = pool.lendSupply.mul(pool.martgageRate).div(prices[1].mul(baseDecimal).div(prices[0]));

            }

            pool.state = PoolState.EXECUTION;
            emit StateChange(_pid,uint256(PoolState.MATCH),uint256(PoolState.EXECUTION));
        }else{
            // 极端情况下，借贷供应量或借款供应量为 0
            pool.state = PoolState.UNDONE;
            data.settleAmountLend = pool.lendSupply;
            data.settleAmountBorrow = pool.borrowSupply;
            emit StateChange(_pid, uint256(PoolState.MATCH), uint256(PoolState.UNDONE));
        }

    }

    function checkoutFinish(uint256 _pid) public view returns(bool){
        return block.timestamp > poolBaseInfo[_pid].endTime;
    }

     /**
     * @dev Get the swap path
     */
    function _getSwapPath(address _swapRouter,address token0,address token1) internal pure returns (address[] memory path){
        IUniswapV2Router02 IUniswap = IUniswapV2Router02(_swapRouter);
        path = new address[](2);
        path[0] = token0 == address(0) ? IUniswap.WETH() : token0;
        path[1] = token1 == address(0) ? IUniswap.WETH() : token1;
    }

    // 根据期望的输出金额来计算所需的输入金额
    function _getAmountIn(address _swapRouter,address token0,address token1,uint256 amountOut) internal view returns (uint256){
        IUniswapV2Router02 IUniswap = IUniswapV2Router02(_swapRouter);
        address[] memory path = _getSwapPath(swapRouter,token0,token1);
        uint[] memory amounts = IUniswap.getAmountsIn(amountOut, path);
        return amounts[0];
    }

    /**
     * @dev Approve
     */
    function _safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeApprove");
    }

    /**
      * @dev Swap
      */
    function _swap(address _swapRouter,address token0,address token1,uint256 amount0) internal returns (uint256) {
        // 如果不是原生代币（地址为 0），则进行授权
        if (token0 != address(0)){
            _safeApprove(token0, address(_swapRouter), type(uint256).max);
        }
        if (token1 != address(0)){
            _safeApprove(token1, address(_swapRouter), type(uint256).max);
        }

        // 实例化 Uniswap V2 路由器合约
        IUniswapV2Router02 IUniswap = IUniswapV2Router02(_swapRouter);
        // 获取代币交换路径
        address[] memory path = _getSwapPath(_swapRouter,token0,token1);
        uint256[] memory amounts;

        // 根据交易类型选择适当的交换函数
        if(token0 == address(0)){
            // 如果 token0 是原生代币（如 ETH），则调用 swapExactETHForTokens
            amounts = IUniswap.swapExactETHForTokens{value:amount0}(0, path,address(this), block.timestamp+30);
        }else if(token1 == address(0)){
            // 如果 token1 是原生代币（如 ETH），则调用 swapExactTokensForETH
            amounts = IUniswap.swapExactTokensForETH(amount0,0, path, address(this), block.timestamp+30);
        }else{
            // 否则调用 swapExactTokensForTokens 进行代币之间的交换
            amounts = IUniswap.swapExactTokensForTokens(amount0,0, path, address(this), block.timestamp+30);
        }
        emit Swap(token0,token1,amounts[0],amounts[amounts.length-1]);
        // 返回交换后获得的代币数量
        return amounts[amounts.length-1];
    }

    function _sellExactAmount(address _swapRouter, address token0, address token1, uint256 amountout) 
        internal returns (uint256, uint256) {
        
        // 使用三元运算符检查 `amountout` 是否大于 0
        // 如果 `amountout` 大于 0，调用 `_getAmountIn` 函数来计算所需输入的 `token0` 数量，并将结果赋值给 `amountSell`
        // 如果 `amountout` 小于等于 0，则 `amountSell` 设置为 0
        uint256 amountSell = amountout > 0 ? _getAmountIn(swapRouter, token0, token1, amountout) : 0;
        
        // 调用 `_swap` 函数执行代币交换操作，并返回实际用于交换的 `token0` 数量和最终获得的 `token1` 数量
        return (amountSell, _swap(_swapRouter, token0, token1, amountSell));
    }


    /**
     * 完成
     * @param _pid 资金池的索引
     */
    function finish(uint256 _pid) public validCall{
        // 获取资金池的基础信息和数据信息
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];

        // 确保当前时间已经超过资金池的结束时间
        require(block.timestamp > pool.endTime, "finish: less than end time");
        // 确保资金池的状态为执行状态
        require(pool.state == PoolState.EXECUTION,"finish: pool state must be execution");

        // 提取借款和贷款的代币地址
        (address token0, address token1) = (pool.borrowToken, pool.lendToken);

        // 计算时间比率：((结束时间 - 结算时间) * baseDecimal) / 365天
        uint256 timeRatio = ((pool.endTime.sub(pool.settleTime)).mul(baseDecimal)).div(baseYear);

        // 计算利息：时间比率 * 利率 * 结算时的贷款金额
        uint256 interest = timeRatio.mul(pool.interestRate.mul(data.settleAmountLend)).div(1e16);

        // 计算贷款总额：结算时的贷款金额 + 利息
        uint256 lendAmount = data.settleAmountLend.add(interest);

        // 计算销售金额
        uint256 sellAmount = lendAmount.mul(lendFee.add(baseDecimal)).div(baseDecimal);

        // 执行代币交换操作
        (uint256 amountSell,uint256 amountIn) = _sellExactAmount(swapRouter, token0, token1, sellAmount);

        // 确保实际收到的贷款金额不低于计算的贷款总额
        require(amountIn >= lendAmount, "finish: Slippage is too high");

        if (amountIn > lendAmount) {
            // 如果实际收到的金额超过贷款总额，计算手续费
            uint256 feeAmount = amountIn.sub(lendAmount);
            
            // 将超出部分作为手续费返还给费用地址
            _redeem(feeAddress, pool.lendToken, feeAmount);
            
            // 更新最终的贷款金额（扣除手续费后的金额）
            data.finishAmountLend = amountIn.sub(feeAmount);
        } else {
            // 如果没有多余金额，则直接将收到的金额设置为最终贷款金额
            data.finishAmountLend = amountIn;
        }

        // 计算剩余的借款金额
        uint256 remianNowAmount = data.settleAmountBorrow.sub(amountSell);

        // 扣除借款费用后，更新剩余的借款金额
        uint256 remianBorrowAmount = redeemFees(borrowFee, pool.borrowToken, remianNowAmount);
        data.finishAmountBorrow = remianBorrowAmount;

        // 更新资金池状态为完成
        pool.state = PoolState.FINISH;
        
        // 触发状态改变事件
        emit StateChange(_pid, uint256(PoolState.EXECUTION), uint256(PoolState.FINISH));
    
    }

    /**
     * 计算和处理费用
     * @param feeRatio 费用比例
     * @param token 费用对应的代币地址
     * @param amount 总金额
     */
    function redeemFees(uint256 feeRatio,address token,uint256 amount) internal returns (uint256){
        uint256 fee = amount.mul(feeRatio)/baseDecimal;

        // 如果费用大于 0，则执行费用的赎回
        if (fee>0){
            _redeem(feeAddress,token, fee);
        }
        // 返回扣除费用后的金额
        return amount.sub(fee);
    }

    /**
     * 检查是否满足清算条件
     */
    function checkoutLiquidate(uint256 _pid) external view returns(bool){
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        PoolDataInfo storage data = poolDataInfo[_pid];

        // 获取当前的价格
        uint256[2] memory prices = getUnderlyingPriceView(_pid);

        // 当前保证金价值是通过将 settleAmountBorrow（借款金额）乘以第二个代币的价格，再除以第一个代币的价格来计算的。calDecimal 用于确保计算的精度
        uint256 borrowValueNow = data.settleAmountBorrow.mul(prices[1].mul(calDecimal).div(prices[0])).div(calDecimal);

        // 计算清算阈值
        uint256 valueThreshold = data.settleAmountLend.mul(baseDecimal.add(pool.autoLiquidateThreshold)).div(baseDecimal);

        // 判断当前保证金价值是否低于清算阈值
        return borrowValueNow < valueThreshold;

    }

    /**
     * 清算
     */
    function liquidate(uint256 _pid) public validCall {
        PoolDataInfo storage data = poolDataInfo[_pid];
        PoolBaseInfo storage pool = poolBaseInfo[_pid];
        require(block.timestamp > pool.settleTime, "now time is less than match time");
        require(pool.state == PoolState.EXECUTION,"liquidate: pool state must be execution");

        // 获取要交易的代币
        (address token0, address token1) = (pool.borrowToken, pool.lendToken);

        // 计算时间比例 = ((结束时间 - 结算时间) * baseDecimal) / 365 天
        uint256 timeRatio = ((pool.endTime.sub(pool.settleTime)).mul(baseDecimal)).div(baseYear);
        
        // 计算利息 = 时间比例 * 利率 * settleAmountLend
        uint256 interest = timeRatio.mul(pool.interestRate.mul(data.settleAmountLend)).div(1e16);

        // 计算总的借款金额 = settleAmountLend + 利息
        uint256 lendAmount = data.settleAmountLend.add(interest);

        // 计算卖出金额，包含费用
        uint256 sellAmount = lendAmount.mul(lendFee.add(baseDecimal)).div(baseDecimal);

         // 执行卖出操作，得到卖出数量和交易金额
        (uint256 amountSell, uint256 amountIn) = _sellExactAmount(swapRouter, token0, token1, sellAmount);

        // 处理滑点，amountIn - lendAmount 可能小于0
        if (amountIn > lendAmount) {
            //如果 amountIn 大于 lendAmount，计算费用并从清算金额中扣除费用
            uint256 feeAmount = amountIn.sub(lendAmount);
            // 处理借款费用
            _redeem(feeAddress, pool.lendToken, feeAmount);
            data.liquidationAmounLend = amountIn.sub(feeAmount);
        } else {
            data.liquidationAmounLend = amountIn;
        }

        // 计算清算借款金额和处理费用
        uint256 remianNowAmount = data.settleAmountBorrow.sub(amountSell);
        uint256 remianBorrowAmount = redeemFees(borrowFee, pool.borrowToken, remianNowAmount);
        data.liquidationAmounBorrow = remianBorrowAmount;
        
        // 更新池状态
        pool.state = PoolState.LIQUIDATION;
        
        // 发出状态更改事件
        emit StateChange(_pid, uint256(PoolState.EXECUTION), uint256(PoolState.LIQUIDATION));
    
    }


}