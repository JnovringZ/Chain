// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract airdrop is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    //Executor
    mapping(address => bool) public executor;

    // constructor(string memory name_, string memory symbol_)
    //     ERC20Upgradeable(name_, symbol_)
    // {}

    function initialize() external initializer {
        __Ownable_init();
        // __ERC20_init(_name, _symbol);
    }

    function setExecutor(address _address, bool _type) external onlyOwner returns (bool) {
        executor[_address] = _type;
        return true;
    }

    modifier onlyExecutor() {
        require(executor[msg.sender], "executor: caller is not the executor");
        _;
    }

    //管理人员可以指定某些钱包地址, 对应的每个钱包地址各自空投多少token
    function beginAirdrop(
        address _erc20,
        address[] memory _users,
        uint256[] memory _amounts
    ) public returns (bool) {
        //输入的人数 和 需要发送的人数是否一致
        require(_users.length == _amounts.length, "input err");
        // 计算总共多少token
        uint256 allAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            allAmount += _amounts[i];
        }

        // 把一定数量的token全部发送到airdrop contract
        IERC20Upgradeable(_erc20).safeTransferFrom(msg.sender, address(this), allAmount);

        // 然后空投合约按顺序给用户列表发送对应数量空投
        for (uint256 i = 0; i < _amounts.length; i++) {
            IERC20Upgradeable(_erc20).safeTransfer(_users[i], _amounts[i]);
        }
        return true;
    }
}
