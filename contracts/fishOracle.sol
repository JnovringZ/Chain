// SPDX-License-Identifier: AGPL-3.0-only
// Using the same Copyleft License as in the original Repository
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;
import "./libraries/IOracle.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Factory.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./libraries/FixedPoint.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// solhint-disable not-rely-on-time

// adapted from https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/examples/ExampleSlidingWindowOracle.sol
interface IAggregator {
    function latestAnswer() external view returns (int256 answer);
}

library BoringMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a + b) >= b, "BoringMath: Add Overflow");
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a - b) <= a, "BoringMath: Underflow");
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b == 0 || (c = a * b) / b == a, "BoringMath: Mul Overflow");
    }

    function to128(uint256 a) internal pure returns (uint128 c) {
        require(a <= type(uint128).max, "BoringMath: uint128 Overflow");
        c = uint128(a);
    }

    function to64(uint256 a) internal pure returns (uint64 c) {
        require(a <= type(uint64).max, "BoringMath: uint64 Overflow");
        c = uint64(a);
    }

    function to32(uint256 a) internal pure returns (uint32 c) {
        require(a <= type(uint32).max, "BoringMath: uint32 Overflow");
        c = uint32(a);
    }
}

contract FISHOracle is Initializable {
    using FixedPoint for *;
    using BoringMath for uint256;
    uint256 public constant PERIOD = 1 minutes;
    // IAggregator public constant AVAX_USD = IAggregator(0x0A77230d17318075983913bC2145DB16C7366156);
    IUniswapV2Pair public FISH_USDC;
    address public FISH;

    function initialize(
        IUniswapV2Pair _FISH_USDC,
        address _FISH
    ) external initializer {
        FISH_USDC = _FISH_USDC;
        FISH = _FISH;
    }

    struct PairInfo {
        uint256 priceCumulativeLast;
        uint32 blockTimestampLast;
        uint144 priceAverage;
    }
    PairInfo public pairInfo;

    function _get(uint32 blockTimestamp) public view returns (uint256) {
        (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        ) = FISH_USDC.getReserves();
        uint256 priceCumulative = address(FISH) == FISH_USDC.token0()
            ? FISH_USDC.price0CumulativeLast()
            : FISH_USDC.price1CumulativeLast();
        (reserve0, reserve1) = address(FISH) == FISH_USDC.token0()
            ? (reserve1, reserve0)
            : (reserve0, reserve1);
        priceCumulative +=
            uint256(FixedPoint.fraction(reserve0, reserve1)._x) *
            (blockTimestamp - blockTimestampLast);
        return priceCumulative;
    }

    // Get the latest exchange rate 更新最新Oracle价格, if no valid (recent) rate is available, return false
    function get(bytes calldata data) external returns (bool, uint256) {
        uint32 blockTimestamp = uint32(block.timestamp);
        if (pairInfo.blockTimestampLast == 0) {
            pairInfo.blockTimestampLast = blockTimestamp;
            pairInfo.priceCumulativeLast = _get(blockTimestamp);
            return (false, 0);
        }
        uint32 timeElapsed = blockTimestamp - pairInfo.blockTimestampLast; // overflow is desired
        if (timeElapsed < PERIOD) {
            return (true, pairInfo.priceAverage);
        }
        uint256 priceCumulative = _get(blockTimestamp);
        pairInfo.priceAverage = uint144(
            1e54 /
                (
                    uint256(1e18).mul(
                        uint256(
                            FixedPoint
                                .uq112x112(
                                    uint224(
                                        (priceCumulative -
                                            pairInfo.priceCumulativeLast) /
                                            timeElapsed
                                    )
                                )
                                .mul(1e18)
                                .decode144()
                        )
                    ) /*.mul(uint256(AVAX_USD.latestAnswer())) / 1e9*/
                )
        );
        pairInfo.blockTimestampLast = blockTimestamp;
        pairInfo.priceCumulativeLast = priceCumulative;
        return (true, pairInfo.priceAverage);
    }

    // Check the last exchange rate without any state changes 防止砸盘保护价格不会下降太厉害
    function peek(bytes calldata data) public view returns (bool, uint256) {
        uint32 blockTimestamp = uint32(block.timestamp);
        if (pairInfo.blockTimestampLast == 0) {
            return (false, 0);
        }
        uint32 timeElapsed = blockTimestamp - pairInfo.blockTimestampLast; // overflow is desired
        if (timeElapsed < PERIOD) {
            return (true, pairInfo.priceAverage);
        }
        uint256 priceCumulative = _get(blockTimestamp);
        uint144 priceAverage = uint144(
            1e54 /
                (
                    uint256(1e18).mul(
                        uint256(
                            FixedPoint
                                .uq112x112(
                                    uint224(
                                        (priceCumulative -
                                            pairInfo.priceCumulativeLast) /
                                            timeElapsed
                                    )
                                )
                                .mul(1e18)
                                .decode144()
                        )
                    ) /*.mul(uint256(AVAX_USD.latestAnswer())) / 1e9*/
                )
        );
        return (true, priceAverage);
    }

    // Check the current spot exchange rate without any state changes 没有通过Oracle的, 有人砸盘的话, 价格就随之变化跳水
    function peekSpot(
        bytes calldata data
    ) external view returns (uint256 rate) {
        (uint256 reserve0, uint256 reserve1, ) = FISH_USDC.getReserves(); //reserve是经过补0过后的

        (reserve0, reserve1) = address(FISH) == FISH_USDC.token0()
            ? (reserve1, reserve0)
            : (reserve0, reserve1);
        rate = 1e54 / (uint256(1e18).mul(reserve0.mul(1e18) / reserve1));
    }

    function name(bytes calldata) public view returns (string memory) {
        return "FISH_USDC Oracle";
    }

    function symbol(bytes calldata) public view returns (string memory) {
        return "FISH";
    }
}
