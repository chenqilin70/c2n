// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Farm distributes the ERC20 rewards based on staked LP to each user.
//
// Cloned from https://github.com/SashimiProject/sashimiswap/blob/master/contracts/MasterChef.sol
// Modified by LTO Network to work for non-mintable ERC20.

contract FarmingC2N is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // 用户存了多少钱
        uint256 rewardDebt; // 奖励余额. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of ERC20s
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accERC20PerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accERC20PerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;             // 质押币的种类
        uint256 allocPoint;         //  分配给该资源池的分配点数。
        uint256 lastRewardTimestamp;    // 上一次奖励更新时间
        uint256 accERC20PerShare;   // 每个币累计的奖励点数
        uint256 totalDeposits; // 存入质押币的总量
    }


    // 用于奖励的token
    IERC20 public erc20;
    // 已经提取出去的奖励总额
    uint256 public paidOut;
    // 每秒奖励数量
    uint256 public rewardPerSecond;
    // 农场总体奖励数量
    uint256 public totalRewards;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // 每种质押币中，每个用户的信息
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // 总分配点数
    uint256 public totalAllocPoint;

    // The timestamp when farming starts.
    uint256 public startTimestamp;
    // The timestamp when farming ends.
    uint256 public endTimestamp;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    //构建的时候需要提供奖励币的种类 、 每秒奖励 和开始时间
    constructor(IERC20 _erc20, uint256 _rewardPerSecond, uint256 _startTimestamp) public {
        erc20 = _erc20;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _startTimestamp;
    }

    // 获取代币种类数
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // 向农场合约添加奖励金额
    function fund(uint256 _amount) public {
        require(block.timestamp < endTimestamp, "fund: too late, the farm is closed");
        erc20.safeTransferFrom(address(msg.sender), address(this), _amount);
        endTimestamp += _amount.div(rewardPerSecond);//相当于当前时间+根据奖励速率计算出的发放完奖励所需的时间
        totalRewards = totalRewards.add(_amount);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    // 添加新的质押币类型
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardTimestamp : lastRewardTimestamp,
        accERC20PerShare : 0,
        totalDeposits : 0
        }));
    }

    // Update the given pool's ERC20 allocation point. Can only be called by the owner.
    // 更新池子中点数 和 总点数
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // 查询用户存了多少币
    function deposited(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    // 查询待分配奖励
    function pending(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accERC20PerShare = pool.accERC20PerShare;

        uint256 lpSupply = pool.totalDeposits;

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;//计算奖励的截止时间
            uint256 timestampToCompare = pool.lastRewardTimestamp < endTimestamp ? pool.lastRewardTimestamp : endTimestamp;//
            uint256 nrOfSeconds = lastTimestamp.sub(timestampToCompare);//质押时间长度
            uint256 erc20Reward = nrOfSeconds.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);//质押时间 * 每秒奖励 * （代币类型点数/总点数） = 总奖励 * 点数占比 = 该类型代币获得的奖励总数
            accERC20PerShare = accERC20PerShare.add(erc20Reward.mul(1e36).div(lpSupply));// 一个币累计获得奖励 + （该类型代币获得的奖励总数/代币总余额）
        }
        return user.amount.mul(accERC20PerShare).div(1e36).sub(user.rewardDebt);//用户余额 * 每个币奖励数 - 用户已经奖励的数量
    }

    //  农场尚未支付的奖金总额。
    function totalPending() external view returns (uint256) {
        if (block.timestamp <= startTimestamp) {
            return 0;
        }

        uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;// 即将计算奖励的截止时间
        return rewardPerSecond.mul(lastTimestamp - startTimestamp).sub(paidOut);//  农场尚未支付的奖金总额 = （每秒获得奖励数量 * 计算奖励的截止时间）- 已经支付的奖励总额
    }

    // 更新所有代币池
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // 更新指定的代币池  主要是更新 累计每个代币的奖励 和 上一次计算奖励时间
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lastTimestamp = block.timestamp < endTimestamp ? block.timestamp : endTimestamp;//即将计算奖励截止时间

        if (lastTimestamp <= pool.lastRewardTimestamp) {//如果即将计算奖励的截止时间 < 上一次计算奖励的时间  则无需更新
            return;
        }
        uint256 lpSupply = pool.totalDeposits;

        if (lpSupply == 0) {// 如果这类币没有任何存入，则无需更新
            pool.lastRewardTimestamp = lastTimestamp;
            return;
        }

        uint256 nrOfSeconds = lastTimestamp.sub(pool.lastRewardTimestamp);// 质押时间
        uint256 erc20Reward = nrOfSeconds.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint); //质押时间*每秒奖励数 * （所持点数/总点数） = 总奖励*点数占比 = 当前币种的奖励

        pool.accERC20PerShare = pool.accERC20PerShare.add(erc20Reward.mul(1e36).div(lpSupply)); //当前币种的奖励 / 存入总数 = 每一个币获得的奖励数
        pool.lastRewardTimestamp = block.timestamp;
    }

    // 将 LP 代币存入农场，以获得 ERC20 分配。
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);// 当前用户余额 * 累计每个代币的奖励 - 用户已经获取的奖励
            erc20Transfer(msg.sender, pendingAmount);// 转账
        }

        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);//转账
        pool.totalDeposits = pool.totalDeposits.add(_amount);//增加代币池总余额

        user.amount = user.amount.add(_amount);//增加用户余额
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e36);//更新 新的余额 * 每个代币累计奖励额 = 用户获取的总奖励额
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Farm.
    // 包含两个功能，收取奖励，撤回质押
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: can't withdraw more than deposit");
        updatePool(_pid);

        // 计算奖励
        uint256 pendingAmount = user.amount.mul(pool.accERC20PerShare).div(1e36).sub(user.rewardDebt);

        erc20Transfer(msg.sender, pendingAmount);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accERC20PerShare).div(1e36);
        // 撤回流动性
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        pool.totalDeposits = pool.totalDeposits.sub(_amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // 提款时无需考虑奖励。仅限紧急情况。
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        pool.totalDeposits = pool.totalDeposits.sub(user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // 转账奖励币，同时更新总奖励提取额
    function erc20Transfer(address _to, uint256 _amount) internal {
        erc20.transfer(_to, _amount);
        paidOut += _amount;
    }
}
