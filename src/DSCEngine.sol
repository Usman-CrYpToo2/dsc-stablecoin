// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import {DStablecoin} from "./DStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
     
     
    error DSCEngine_moreThanZero();
    error DSCEngine_tokensAndPriceFeedLengthMustBeSame();
    error DSCEngine_zeroAddress();
    error DSCEngine_tokenNotAllowed();
    error DSCEngine_transferFailed();
    error DSCEngine_BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine_PositionIsHealthy(uint256 userHealthFactor);
    error DSCEngine_HealthFactorIsNotImproved();

    using OracleLib for AggregatorV3Interface;

    uint256 private constant ADDITIONAL_FEES_PRECISION = 1e10;
   uint256 private constant PRECISION = 1e18;
   uint256 public liquidationThreshold = 50;
   uint256 private constant LIQUIDATION_PRECISION = 100;
   uint256 private constant MIN_HEALTH_FACTOR = 1e18;
   uint256 private liquidationBonus = 10;


    DStablecoin immutable private DSC;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 balance)) public s_CollateralDeposits;
    mapping(address user => uint256 amount) public s_DscMinted;
    address[] private s_CollateralTokens;
    


    event Event_depositCollateral(address indexed user, address indexed token, uint256 indexed amount);
    event Event_CollateralRedeemed(address indexed from, address indexed to,  address indexed collateralToken,  uint256 amount);

    modifier moreThanZero(uint256 amount) {
         if (amount == 0) {
             revert DSCEngine_moreThanZero();
         }
         _;
    }

    modifier isTokenAllowed(address tokenCollateralAddress) {
         if ( s_priceFeeds[tokenCollateralAddress] == address(0)) {
             revert DSCEngine_tokenNotAllowed();
         }
         _;
    }

     constructor(address[] memory tokens, address[] memory priceFeeds, address dscAddress) {
         if ( tokens.length != priceFeeds.length) {
             revert DSCEngine_tokensAndPriceFeedLengthMustBeSame();
         }

         if(dscAddress == address(0)) {
             revert DSCEngine_zeroAddress();
         }   

         DSC = DStablecoin(dscAddress);

         for(uint256 i = 0; i < tokens.length; i++) {
             s_priceFeeds[tokens[i]] = priceFeeds[i];
             s_CollateralTokens.push(tokens[i]);
         }

     }
     function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external  {
          depositCollateral(tokenCollateralAddress, amountCollateral);
          mintDsc(amountDscToMint);
     }

     function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) public  isTokenAllowed(tokenCollateralAddress) nonReentrant moreThanZero(amountCollateral)  {
          s_CollateralDeposits[msg.sender][tokenCollateralAddress] += amountCollateral;

         emit  Event_depositCollateral(msg.sender, tokenCollateralAddress, amountCollateral);
         
         bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
         
         if(!success) {
             revert DSCEngine_transferFailed();
         }
     }

     function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
         burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
     }

     function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public isTokenAllowed(tokenCollateralAddress) moreThanZero(amountCollateral) nonReentrant() {
     
         _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
          _revertIfHealthFactorIsBroken(msg.sender);

     }


     function mintDsc(uint256 amountDscToMint ) public moreThanZero(amountDscToMint) nonReentrant {
          s_DscMinted[msg.sender] += amountDscToMint;
          _revertIfHealthFactorIsBroken(msg.sender);
          DSC.mint(msg.sender, amountDscToMint);

     }

     function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) nonReentrant {
         _burnDsc(amountDscToBurn, msg.sender, msg.sender);
         _revertIfHealthFactorIsBroken(msg.sender);
     }

     function liquidate(address collateralToken, address user,uint256 debtToCover) external isTokenAllowed(collateralToken) moreThanZero(debtToCover) nonReentrant() {
          uint256 startingUserHealthFactor = _healthFactor(user);
          if(startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
             revert DSCEngine_PositionIsHealthy(startingUserHealthFactor);
          }
           
          uint256 tokenAmountFromDebtCoverd = getTokenAmountFromUsd(collateralToken, debtToCover);
          
          uint256 bonusCollateral = (tokenAmountFromDebtCoverd * liquidationBonus) / LIQUIDATION_PRECISION;
          
          uint256 totalCollateralToredeemed = tokenAmountFromDebtCoverd + bonusCollateral ;

        _redeemCollateral(collateralToken, totalCollateralToredeemed, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor =  _healthFactor(user);
        if(endingUserHealthFactor <= startingUserHealthFactor) {
             revert DSCEngine_HealthFactorIsNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);

     }

     function getTokenAmountFromUsd(address collateralToken, uint256 usdAmountInWei ) public view returns(uint256){
         AggregatorV3Interface priceFeeds = AggregatorV3Interface(s_priceFeeds[collateralToken]);
         (, int256 price, , , ) = priceFeeds.stalePriceCheck();
         
         // 100 / 200 = 0.5 eth
         return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEES_PRECISION);
     }

     function getHealthFactor() external view {}

  

     function _revertIfHealthFactorIsBroken(address user) internal view {
           uint256 userHealthFactor = _healthFactor(user);
           if ( userHealthFactor <  MIN_HEALTH_FACTOR) {
              revert DSCEngine_BreaksHealthFactor(userHealthFactor);
           }
     }


    function _healthFactor(address user) private view returns (uint256) {
          (uint256 totalDscMinted, uint256 collateralValueInUsd ) = _getAccountInformation(user);
          if(totalDscMinted == 0) return type(uint256).max;
           uint256 collateralAdjustedForThreshold = (collateralValueInUsd * liquidationThreshold) / LIQUIDATION_PRECISION;
           return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;


           // $500 -> eth 
           // 100 -> dcs
           // (500 * 50 )/ 100 = (250 / 100) > 1  

           // 500_000_000_000_000_000_000 -> $500 eth
           // 100_000_000_000_000_000_000 -> $100 dcs
           // (500_000_000_000_000_000_000 * 50 ) / 100 = ()

     }

     function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to ) private  {
            s_CollateralDeposits[from][tokenCollateralAddress] -= amountCollateral;
          emit Event_CollateralRedeemed( from , to , tokenCollateralAddress, amountCollateral);
          bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
           if(!success) {
             revert DSCEngine_transferFailed();
         }
     }

     function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address from ) private {
         s_DscMinted[onBehalfOf] -= amountDscToBurn;
         IERC20(DSC).transferFrom(from, address(this), amountDscToBurn);
         DSC.burn(amountDscToBurn);
     }

     function _getAccountInformation(address user) public view returns(uint256 totalDscMinted, uint256 collateralValueInUsd) {
            totalDscMinted = s_DscMinted[user];
           collateralValueInUsd = getAccountCollateralValue(user);

     }

     function getUsdValue(address collateralToken, uint256 amount ) public view returns(uint256) {
       AggregatorV3Interface pricefeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);
        (,int256 price ,,,) = pricefeed.stalePriceCheck();
        return(((uint256(price) * ADDITIONAL_FEES_PRECISION ) * amount) / PRECISION);

     }

     function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd) {
          for(uint256 i = 0; i < s_CollateralTokens.length; i++) {
             address collateralToken = s_CollateralTokens[i];
             uint256 amount = s_CollateralDeposits[user][collateralToken];
             totalCollateralValueInUsd += getUsdValue(collateralToken, amount);
          }
     }


    
}