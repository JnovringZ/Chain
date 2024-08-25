// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Pair.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Factory.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Router02.sol";
import "./libraries/IOracle.sol";

library Math {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
interface IFISH {
    function mint(address account_, uint256 amount_) external returns (bool);
}
interface IFISHNFT {
    function totalSupply() external view returns (uint256);

    function mintFromExecutor(
        address _to,
        uint256 _seed,
        uint256 _remainingReward
    ) external returns (bool);
}

contract usdcBuyNftLogic is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMath for uint256;

    uint256 public exchangeRate; //Fish Token的价格
    IOracle public oracle; //价格预言机合约地址
    address public sFISH;
    address public multiSignature;
    address public multiSignatureToSToken;
    address public dev; //开发者地址
    address public op; //运营团队地址
    IUniswapV2Router02 public Router; //Uniswap的路由器
    IUniswapV2Factory public Factory; //Uniswap的工厂合约
    IERC20Upgradeable public USDC;
    uint256 public maxSellAmt; //最大售出数量
    IFISH public FISH; ///FISH Token的地址
    IFISHNFT public FISHNFT; ///FISH NFT的地址
    uint256 public ROI; //投资回报率 = (收益-成本)/成本*100%
    uint256 public PRECISION; ///百分比分母:目的是为了数值更精确
    uint256 public direction; //方向, 用来设置ROI是涨还是跌
    uint256 public stepSize; //步长, 用来设置ROI涨/跌的幅度
    uint256 public TargetROI; //目标投资回报率
    uint256 public price; //NFT的价格
    mapping(address => uint256) public whitelistLevel; //白名单等级: 一级打九折, 二级打八折,...
    mapping(uint256 => uint256) public whitelistDiscount; //对应的等级打对应的折
    uint256 public toLiquidityPec; //x刀买NFT之后, 分到流动性的比例
    uint256 public toDevPec; //x刀买NFT之后, 分到开发者的比例
    uint256 public toOpPec; //x刀买NFT之后, 分到运营团队的比例
    bool public stateOpen; //是否能够购买的状态

    bool public addLiquidityOpen; //是否开放添加流动性
    bytes public oracleData; //预言机的数据

    function initialize(
        IFISH _FISH,
        IFISHNFT _FISHNFT,
        IUniswapV2Factory _Factory,
        IUniswapV2Router02 _Router,
        address _multiSignature,
        address _multiSignatureToSToken,
        address _dev,
        address _op,
        address _sFISH,
        IOracle _oracle,
        IERC20Upgradeable _USDC
    ) external initializer {
        __Ownable_init();
        USDC = _USDC;
        oracle = _oracle;
        dev = _dev;
        op = _op;
        multiSignature = _multiSignature;
        multiSignatureToSToken = _multiSignatureToSToken;
        Router = _Router;
        Factory = _Factory;
        FISH = _FISH;
        FISHNFT = _FISHNFT;
        sFISH = _sFISH;
        PRECISION = 10000;
        ROI = 10000;
        direction = 0;
        stepSize = 100;
        TargetROI = 1000;
        price = 100 * 1e18;
        whitelistDiscount[0] = 10000;
        whitelistDiscount[1] = 9000;
        whitelistDiscount[2] = 8000;
        maxSellAmt = 1000;
        toLiquidityPec = 5000;
        toDevPec = 1500;
        toOpPec = 1500;
        addLiquidityOpen = false;
        stateOpen = false;
    }

    //排序两个代币地址大小, 地址小的放在前面, 地址大的放在后面
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: identical_address");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: zero_address");
    }

    //更新ROI, 根据方向的不同和步长的不同调整ROI
    function updateRoi() internal returns (bool) {
        if (direction == 1) {
            if (ROI < TargetROI) {
                ROI = ROI.add(stepSize);
            }
        } else if (direction == 2) {
            if (ROI > TargetROI) {
                ROI = ROI.sub(stepSize);
            }
        } else {}
        return true;
    }

    //更新 预言机地址 和 预言机相关数据
    function setOracle(
        IOracle _newOracle,
        bytes memory _newOracleData
    ) public onlyOwner returns (bool) {
        oracle = _newOracle;
        oracleData = _newOracleData;
        return true;
    }
//-----(风灵月影)--------(风灵月影)------(风灵月影)-------(风灵月影)-------
    function setToLiquidityPec(
        uint256 _toLiquidityPec
    ) public onlyOwner returns (bool) {
        toLiquidityPec = _toLiquidityPec;
        return true;
    }

    function setToDevPec(uint256 _toDevPec) public onlyOwner returns (bool) {
        toDevPec = _toDevPec;
        return true;
    }

    function setAddLiquidityOpen(bool _bool) public onlyOwner returns (bool) {
        addLiquidityOpen = _bool;
        return true;
    }

    function setToOpPec(uint256 _toOpPec) public onlyOwner returns (bool) {
        toOpPec = _toOpPec;
        return true;
    }

    function setDev(address _dev) public onlyOwner returns (bool) {
        dev = _dev;
        return true;
    }

    function setOp(address _op) public onlyOwner returns (bool) {
        op = _op;
        return true;
    }

    function setMultiSignature(
        address _multiSignature
    ) public onlyOwner returns (bool) {
        multiSignature = _multiSignature;
        return true;
    }

    function setMultiSignatureToSToken(
        address _multiSignatureToSToken
    ) public onlyOwner returns (bool) {
        multiSignatureToSToken = _multiSignatureToSToken;
        return true;
    }

    function setStateOpen(bool _bool) public onlyOwner returns (bool) {
        stateOpen = _bool;
        return true;
    }

    function setMaxSellAmt(uint256 _val) public onlyOwner returns (bool) {
        maxSellAmt = _val;
        return true;
    }

    function setROI(uint256 _val) public onlyOwner returns (bool) {
        ROI = _val;
        return true;
    }

    function setDirection(uint256 _val) public onlyOwner returns (bool) {
        direction = _val;
        return true;
    }

    function setStepSize(uint256 _val) public onlyOwner returns (bool) {
        stepSize = _val;
        return true;
    }

    function setTargetROI(uint256 _val) public onlyOwner returns (bool) {
        TargetROI = _val;
        return true;
    }

    function setPrice(uint256 _val) public onlyOwner returns (bool) {
        price = _val;
        return true;
    }

    function setWhitelistLevel(
        address _user,
        uint256 _lev
    ) public onlyOwner returns (bool) {
        whitelistLevel[_user] = _lev;
        return true;
    }

    function setWhitelistDiscount(
        uint256 _val,
        uint256 _lev
    ) public onlyOwner returns (bool) {
        whitelistDiscount[_val] = _lev;
        return true;
    }


    // 更新Fish在DEX上的价格
    function updateExchangeRate() public returns (bool updated, uint256 rate) {
        (updated, rate) = oracle.get(oracleData);
        if (updated) {
            exchangeRate = rate;
        } else {
            // Return the old rate if fetching wasn't successful
            rate = exchangeRate;
        }
    }

    function peekSpot() public view returns (uint256) {
        return oracle.peekSpot("0x");
    }

    //输入一种Token, 获得另一种Token
    function getAmountOut(
        uint256 amountIn, //输入的Token数量
        uint256 reserveIn, //Pool中输入Token的储备量
        uint256 reserveOut //Pool中输出Token的储备量
    ) internal pure returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn.mul(997); //扣除手续费0.3%之后的输入Token的量
        uint256 numerator = amountInWithFee.mul(reserveOut); //扣除手续费之后实际输入Token的储备量 * 输出Token储备量
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee); //输入Token的储备量 + 扣除手续费之后的输入Token的量
        amountOut = numerator / denominator; //用户可获得的输出Token的数量
    }

    //--功能function----功能function----功能function----功能function
    function buyNft(uint256 _amt) public returns (bool) {
        uint256 amt = _amt;
        //防止外部合约调用, 只能个人钱包去调用.为了防止黑客攻击
        //(黑客在合约中执行buyNft, 然后检查是否买到高级的Nft, 如果是的话买到就手
        //如果不是,就require出来, 不执行下一步了.这样黑客就可以仅付手续费就能刷高级Nft)
        require(tx.origin == _msgSender(), "Only EOA");

        //需要的USDC数量: amount = NFT价格 * 数量 * 白名单里的账户等级折扣/百分比分母
        uint256 amount = price
            .mul(amt)
            .mul(whitelistDiscount[whitelistLevel[msg.sender]])
            .div(PRECISION);

        //调用者转移amount数量的USDC到这个合约地址
        IERC20Upgradeable(address(USDC)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        //USDC分配到Pool中的总数量
        uint256 amountUSDCToLiquidity = amount.mul(toLiquidityPec).div(PRECISION);
        //USDC分配到dev中的数量
        uint256 amountUSDCToDev = amount.mul(toDevPec).div(PRECISION);
        //USDC分配到 运营团队 中的数量
        uint256 amountUSDCToOP = amount.mul(toOpPec).div(PRECISION);
        //剩余的USDC全部分给sFish代币
        uint256 amountUSDCToSFISH = amount
            .sub(amountUSDCToLiquidity)
            .sub(amountUSDCToDev)
            .sub(amountUSDCToOP);

        //获得代币对Pool的地址 = Factory.getPair(地址,地址) , 获得USDC/FISH代币对的Pool地址
        address pairAddress = Factory.getPair(address(USDC), address(FISH));
        // (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pairAddress)
        //     .getReserves();~

        //只需要地址小的代币(不知道是哪个)
        (address token0, ) = sortTokens(address(USDC), address(FISH));

        //项目发行的话, 买一个币就添加一次流动性
        if (addLiquidityOpen) {
            //safeApprove必须先设置0(即取消Router合约对USDC的授权), 才能重新授权, approve的话可以直接设置其他值
            IERC20Upgradeable(address(USDC)).safeApprove(address(Router), 0);
            IERC20Upgradeable(address(USDC)).safeApprove(
                address(Router),
                type(uint256).max
            );
            //同USDC
            IERC20Upgradeable(address(FISH)).safeApprove(address(Router), 0);
            IERC20Upgradeable(address(FISH)).safeApprove(
                address(Router),
                type(uint256).max
            );

            ///用USDC买FISH 用来组LP
            calAndSwap(
                IUniswapV2Pair(pairAddress),
                address(FISH),
                address(USDC),
                amountUSDCToLiquidity
            );

            uint256 addLiquidityForUSDC = IERC20Upgradeable(address(USDC))
                .balanceOf(address(this))
                .sub(amountUSDCToDev)
                .sub(amountUSDCToOP)
                .sub(amountUSDCToSFISH);

            Router.addLiquidity(
                address(USDC),
                address(FISH),
                addLiquidityForUSDC,
                IERC20Upgradeable(address(FISH)).balanceOf(address(this)),
                0,
                0,
                multiSignature,
                block.timestamp + 1000
            );
        } else {
            ///项目如果还没发行, 先把token放入多签 到时候统一添加流动性
            USDC.safeTransfer(address(multiSignature), amountUSDCToLiquidity);
        }
        USDC.safeTransfer(address(dev), amountUSDCToDev);
        USDC.safeTransfer(address(op), amountUSDCToOP);

        if (stateOpen) {
            (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pairAddress)
                .getReserves();
            (reserve0, reserve1) = address(USDC) == token0
                ? (reserve0, reserve1)
                : (reserve1, reserve0);
            //可获得的Fish Token
            uint256 amountFish = getAmountOut(
                amountUSDCToSFISH,
                reserve0,
                reserve1
            );
            (uint256 amount0Out, uint256 amount1Out) = address(USDC) == token0
                ? (uint256(0), amountFish)
                : (amountFish, uint256(0));
            USDC.safeTransfer(address(pairAddress), amountUSDCToSFISH);
            IUniswapV2Pair(pairAddress).swap(
                amount0Out,
                amount1Out,
                address(this),
                new bytes(0)
            );
            IERC20Upgradeable(address(FISH)).safeTransfer(
                address(sFISH),
                IERC20Upgradeable(address(FISH)).balanceOf(address(this))
            );
        } else {
            USDC.safeTransfer(
                address(multiSignatureToSToken),
                amountUSDCToSFISH
            );
        }

        (, uint256 rate) = updateExchangeRate();
        updateRoi();
        for (uint256 i = 0; i < amt; i++) {
            FISHNFT.mintFromExecutor(
                msg.sender,
                block.timestamp + i,
                (((price * rate) / 1e18) * (ROI + PRECISION)) / PRECISION
            );
        }
        return true;
    }

    /// Compute amount and swap between borrowToken and tokenRelative.
    ///在提供流动性的时候优化代币的交换比例, 确保最大程度利用流动性池的资金
    ///计算并执行代币swap, 将USDC转换为流动性池中的另一种代币
    function calAndSwap(
        IUniswapV2Pair lpToken,
        address tokenA,
        address tokenB,
        uint256 amountUSDCToLiquidity
    ) internal {
        (uint256 token0Reserve, uint256 token1Reserve, ) = lpToken.getReserves();
        (uint256 debtReserve, uint256 relativeReserve) = address(FISH) ==
            lpToken.token0()
            ? (token0Reserve, token1Reserve)
            : (token1Reserve, token0Reserve);
        (uint256 swapAmt, bool isReversed) = optimalDeposit(
            0,
            amountUSDCToLiquidity,
            debtReserve,
            relativeReserve
        );

        if (swapAmt > 0) {
            address[] memory path = new address[](2);
            (path[0], path[1]) = isReversed
                ? (tokenB, tokenA)
                : (tokenA, tokenB);
            Router.swapExactTokensForTokens(
                swapAmt,
                0,
                path,
                address(this),
                block.timestamp
            );
        }
    }

    ///计算最优的代币交换数量，以便在流动性池中进行添加流动性操作。
    function optimalDeposit(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256 swapAmt, bool isReversed) {
        if (amtA.mul(resB) >= amtB.mul(resA)) {
            swapAmt = _optimalDepositA(amtA, amtB, resA, resB);
            isReversed = false;
        } else {
            swapAmt = _optimalDepositA(amtB, amtA, resB, resA);
            isReversed = true;
        }
    }

    ///计算最优的代币交换金额
    function _optimalDepositA(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256) {
        require(amtA.mul(resB) >= amtB.mul(resA), "Reversed");

        uint256 a = 997;
        uint256 b = uint256(1997).mul(resA);
        uint256 _c = (amtA.mul(resB)).sub(amtB.mul(resA));
        uint256 c = _c.mul(1000).div(amtB.add(resB)).mul(resA);

        uint256 d = a.mul(c).mul(4);
        uint256 e = Math.sqrt(b.mul(b).add(d));

        uint256 numerator = e.sub(b);
        uint256 denominator = a.mul(2);

        return numerator.div(denominator);
    }
}










































