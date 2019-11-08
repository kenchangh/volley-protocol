pragma solidity >=0.4.21 <0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract CoveredOption is ERC20, ERC20Burnable, ERC20Detailed {
  using SafeMath for uint256;

  mapping (address => uint256) public collateralPool;
  uint256 public totalCollateral;

  address private _baseToken;
  address private _quoteToken;
  uint256 private _strikePrice;
  uint256 private _expiry;

  struct InitialOrder {
    address recipient;
    uint256 price;
    uint256 amount;
  }
  InitialOrder private initialOrder;

  constructor(
    // token details
    string memory name,
    string memory symbol,

    // option details
    address baseToken,
    address quoteToken,
    uint256 quoteStrikePrice,
    uint256 initialTokenPrice,
    uint256 initialTokenAmount,
    uint256 expiry

  ) ERC20Detailed(name, symbol, 18) public {

    // set option parameters
    require(expiry > now, "CoveredOption: expiry has to be after current time");

    _baseToken = baseToken;
    _quoteToken = quoteToken;
    _strikePrice = quoteStrikePrice;
    _expiry = expiry;
    initialOrder = InitialOrder(msg.sender, initialTokenPrice, initialTokenAmount);

    // update shares in the collateralPool
    depositCollateral(msg.sender, initialTokenAmount);

    // transfer baseToken from msg.sender to contract
    IERC20(baseToken).transferFrom(msg.sender, address(this), initialTokenAmount);

    // mint new token
    ERC20._mint(msg.sender, initialTokenAmount);
  }

  function closeOption(uint256 amount) public {
    require(amount > 0, "CoveredOption: amount cannot be 0");

    // receive shares from collateral pool
    (uint256 baseTokenAmount, uint256 quoteTokenAmount) = withdrawCollateral(msg.sender, amount);

    // redeem the collateral from collateral pool
    if (baseTokenAmount > 0) {
      IERC20(_baseToken).transferFrom(address(this), msg.sender, baseTokenAmount);
    }
    if (quoteTokenAmount > 0) {
      IERC20(_quoteToken).transferFrom(address(this), msg.sender, quoteTokenAmount);
    }
  }

  function exerciseOption(uint256 amount) public {
    require(amount > 0, "CoveredOption: amount cannot be 0");

    // burn option tokens and redeem the collateral
    ERC20Burnable.burnFrom(msg.sender, amount);

    uint256 quoteTokenAmount = _strikePrice.mul(amount);

    // transfer the quoteToken into the collateral pool
    IERC20(_quoteToken).transferFrom(msg.sender, address(this), quoteTokenAmount);

    // redeem the strike asset
    IERC20(_baseToken).transferFrom(address(this), msg.sender, amount);
  }

  function depositCollateral(address depositer, uint256 amount) internal {
    collateralPool[depositer] = collateralPool[depositer].add(amount);
    totalCollateral = totalCollateral.add(amount);
  }

  function withdrawCollateral(address depositer, uint256 amount) internal returns (uint256, uint256) {
    // get sender's % share of the collateral pool
    uint256 baseTokenReserve = IERC20(_baseToken).balanceOf(address(this));
    uint256 quoteTokenReserve = IERC20(_quoteToken).balanceOf(address(this));

    uint256 baseTokenAmount = amount.mul(baseTokenReserve).div(totalCollateral);
    uint256 quoteTokenAmount = amount.mul(quoteTokenReserve).div(totalCollateral);

    // update state
    collateralPool[depositer] = collateralPool[depositer].sub(amount);
    totalCollateral = totalCollateral.sub(amount);

    return (baseTokenAmount, quoteTokenAmount);
  }
}