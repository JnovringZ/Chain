pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract whiteList is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    address public aTOKEN; //从白名单是不会给token, 而是给其他的token
    address public usdc; //用于冲白名单的token
    uint256 public minAmt; //最少购买数量
    uint256 public maxAmt; //最多购买数量
    uint256 public salePrice;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public toTalAmount;
    uint256 public sell; //销量
    address public multiSignature; //多签地址
    mapping(address => bool) public whiteListed;
    mapping(address => bool) public bought;

    function initialize(
        address _multiSignature,
        address _aTOKEN,
        address _usdc,
        uint256 _minAmt,
        uint256 _maxAmt,
        uint256 _toTalAmount,
        uint256 _salePrice,
        uint256 _startTime,
        uint256 _endTime
    ) external initializer {
        __Ownable_init();
        aTOKEN = _aTOKEN;
        usdc = _usdc;
        salePrice = _salePrice;
        startTime = _startTime;
        endTime = _endTime;
        multiSignature = _multiSignature;
        minAmt = _minAmt;
        maxAmt = _maxAmt;
        toTalAmount = _toTalAmount;
    }

    function whiteListBuyers(address[] memory _buyers) public onlyOwner returns (bool) {
        for (uint256 i; i < _buyers.length; i++) {
            whiteListed[_buyers[i]] = true;
        }
        return true;
    }

    function participate(uint256 usdc_amt) public {
        sell = sell.add(usdc_amt);
        require(sell <= toTalAmount, "Exceeds monetary target");
        require(whiteListed[msg.sender] == true, "No whitelist");
        require(usdc_amt >= minAmt, "Less than minimum value");
        require(usdc_amt <= maxAmt, "Greater than maximum value");
        require(startTime < block.timestamp, "Did not start");
        require(block.timestamp < endTime, "Sale Finish");
        require(bought[msg.sender] == false, "Participated");
        bought[msg.sender] = true;
        IERC20Upgradeable(usdc).safeTransferFrom(msg.sender, address(this), usdc_amt); //发送usdc, 发送人->当前合约, 发送usdc_amt个
        IERC20Upgradeable(usdc).safeTransfer(multiSignature, usdc_amt); //当前合约把usdc发送给多签
        IERC20Upgradeable(aTOKEN).safeTransfer(msg.sender, uint256(1e18).mul(usdc_amt).div(salePrice)); //当前地址发送aTOKEN 到msg.sender,发送aTOKEN的数量个
    }
}
