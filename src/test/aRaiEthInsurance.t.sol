pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "../math/SafeMath.sol";

import {SAFEEngine} from 'geb/SAFEEngine.sol';
import {LiquidationEngine} from 'geb/LiquidationEngine.sol';
import {AccountingEngine} from 'geb/AccountingEngine.sol';
import {TaxCollector} from 'geb/TaxCollector.sol';
import 'geb/BasicTokenAdapters.sol';
import {OracleRelayer} from 'geb/OracleRelayer.sol';
import {EnglishCollateralAuctionHouse} from 'geb/CollateralAuctionHouse.sol';
import {GebSafeManager} from "geb-safe-manager/GebSafeManager.sol";

import {SAFESaviourRegistry} from "../SAFESaviourRegistry.sol";
import {aRaiEthInsurance} from "../saviours/aRaiEthInsurance.sol";

abstract contract Hevm {
  function warp(uint256) virtual public;
}
contract Feed {
    bytes32 public price;
    bool public validPrice;
    uint public lastUpdateTime;
    address public priceSource;

    constructor(uint256 price_, bool validPrice_) public {
        price = bytes32(price_);
        validPrice = validPrice_;
        lastUpdateTime = now;
    }
    function updatePriceSource(address priceSource_) external {
        priceSource = priceSource_;
    }
    function updateCollateralPrice(uint256 price_) external {
        price = bytes32(price_);
        lastUpdateTime = now;
    }
    function getResultWithValidity() external view returns (bytes32, bool) {
        return (price, validPrice);
    }
}
contract TestSAFEEngine is SAFEEngine {
    uint256 constant RAY = 10 ** 27;

    constructor() public {}

    function mint(address usr, uint wad) public {
        coinBalance[usr] += wad * RAY;
        globalDebt += wad * RAY;
    }
    function balanceOf(address usr) public view returns (uint) {
        return uint(coinBalance[usr] / RAY);
    }
}
contract TestAccountingEngine is AccountingEngine {
    constructor(address safeEngine, address surplusAuctionHouse, address debtAuctionHouse)
        public AccountingEngine(safeEngine, surplusAuctionHouse, debtAuctionHouse) {}

    function totalDeficit() public view returns (uint) {
        return safeEngine.debtBalance(address(this));
    }
    function totalSurplus() public view returns (uint) {
        return safeEngine.coinBalance(address(this));
    }
    function preAuctionDebt() public view returns (uint) {
        return subtract(subtract(totalDeficit(), totalQueuedDebt), totalOnAuctionDebt);
    }
}
contract FakeUser {

    fallback() external payable {}

    function doOpenSafe(
        GebSafeManager manager,
        bytes32 collateralType,
        address usr
    ) public returns (uint256) {
        return manager.openSAFE(collateralType, usr);
    }

    function doSafeAllow(
        GebSafeManager manager,
        uint safe,
        address usr,
        uint ok
    ) public {
        manager.allowSAFE(safe, usr, ok);
    }

    function doHandlerAllow(
        GebSafeManager manager,
        address usr,
        uint ok
    ) public {
        manager.allowHandler(usr, ok);
    }

    function doTransferSAFEOwnership(
        GebSafeManager manager,
        uint safe,
        address dst
    ) public {
        manager.transferSAFEOwnership(safe, dst);
    }

    function doModifySAFECollateralization(
        GebSafeManager manager,
        uint safe,
        int deltaCollateral,
        int deltaDebt
    ) public {
        manager.modifySAFECollateralization(safe, deltaCollateral, deltaDebt);
    }

    function doApproveSAFEModification(
        SAFEEngine safeEngine,
        address usr
    ) public {
        safeEngine.approveSAFEModification(usr);
    }

    function doSAFEEngineModifySAFECollateralization(
        SAFEEngine safeEngine,
        bytes32 collateralType,
        address safe,
        address collateralSource,
        address debtDst,
        int deltaCollateral,
        int deltaDebt
    ) public {
        safeEngine.modifySAFECollateralization(collateralType, safe, collateralSource, debtDst, deltaCollateral, deltaDebt);
    }

    function doProtectSAFE(
        GebSafeManager manager,
        uint safe,
        address liquidationEngine,
        address saviour
    ) public {
        manager.protectSAFE(safe, liquidationEngine, saviour);
    }

    function doDeposit(
        aRaiEthInsurance saviour,
        uint safe,
        uint amount
    ) public {
        saviour.deposit{value: amount}(safe);
    }

    function doWithdraw(
        aRaiEthInsurance saviour,
        uint safe,
        uint amount
    ) public {                
        saviour.withdraw(safe, amount);
    }

    function doSetDesiredCollateralizationRatio(
        aRaiEthInsurance saviour,
        uint safe,
        uint cRatio
    ) public {
        saviour.setDesiredCollateralizationRatio(safe, cRatio);
    }
}

library Errors{
    string public constant MATH_MULTIPLICATION_OVERFLOW = '48';
    string public constant MATH_ADDITION_OVERFLOW = '49';
    string public constant MATH_DIVISION_BY_ZERO = '50';
}

library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant halfWAD = WAD / 2;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    /**
    * @return One ray, 1e27
    **/
    function ray() internal pure returns (uint256) {
        return RAY;
    }

    /**
    * @return One wad, 1e18
    **/

    function wad() internal pure returns (uint256) {
        return WAD;
    }

    /**
    * @return Half ray, 1e27/2
    **/
    function halfRay() internal pure returns (uint256) {
        return halfRAY;
    }

    /**
    * @return Half ray, 1e18/2
    **/
    function halfWad() internal pure returns (uint256) {
        return halfWAD;
    }

    /**
    * @dev Multiplies two wad, rounding half up to the nearest wad
    * @param a Wad
    * @param b Wad
    * @return The result of a*b, in wad
    **/
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
        return 0;
        }

        require(a <= (uint256(-1) - halfWAD) / b, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * b + halfWAD) / WAD;
    }

    /**
    * @dev Divides two wad, rounding half up to the nearest wad
    * @param a Wad
    * @param b Wad
    * @return The result of a/b, in wad
    **/
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
        uint256 halfB = b / 2;

        require(a <= (uint256(-1) - halfB) / WAD, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * WAD + halfB) / b;
    }

    /**
    * @dev Multiplies two ray, rounding half up to the nearest ray
    * @param a Ray
    * @param b Ray
    * @return The result of a*b, in ray
    **/
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
        return 0;
        }

        require(a <= (uint256(-1) - halfRAY) / b, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * b + halfRAY) / RAY;
    }

    /**
    * @dev Divides two ray, rounding half up to the nearest ray
    * @param a Ray
    * @param b Ray
    * @return The result of a/b, in ray
    **/
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, Errors.MATH_DIVISION_BY_ZERO);
        uint256 halfB = b / 2;

        require(a <= (uint256(-1) - halfB) / RAY, Errors.MATH_MULTIPLICATION_OVERFLOW);

        return (a * RAY + halfB) / b;
    }

    /**
    * @dev Casts ray down to wad
    * @param a Ray
    * @return a casted to wad, rounded half up to the nearest wad
    **/
    function rayToWad(uint256 a) internal pure returns (uint256) {
        uint256 halfRatio = WAD_RAY_RATIO / 2;
        uint256 result = halfRatio + a;
        require(result >= halfRatio, Errors.MATH_ADDITION_OVERFLOW);

        return result / WAD_RAY_RATIO;
    }

    /**
    * @dev Converts wad up to ray
    * @param a Wad
    * @return a converted in ray
    **/
    function wadToRay(uint256 a) internal pure returns (uint256) {
        uint256 result = a * WAD_RAY_RATIO;
        require(result / WAD_RAY_RATIO == a, Errors.MATH_MULTIPLICATION_OVERFLOW);
        return result;
    }
}

contract LendingPool{
    
      function getReserveNormalizedIncome(address asset) external view returns (uint256){
          return 1;
      }
}

contract AToken is SafeMath{

    using WadRayMath for uint256;

    uint256 WAD = 10**18;

    mapping (address => uint) internal balances;

    address public UNDERLYING_ASSET_ADDRESS = address(0);
    LendingPool POOL;

    constructor(address poolAddress){
        POOL = LendingPool(poolAddress);
    }

    function mint(address owner) external payable{
        require(msg.value > 0);
        uint256 mintTokens = msg.value;
        balances[owner] = add(balances[owner], mintTokens);
    }

    function balanceOf(address owner) external view returns (uint256) {
        return balances[owner];
    }

    function scaledBalanceOf(address owner) external view returns (uint256) {
        return balances[owner];
    }

    function withdrawUnderlying(uint aTokenAmount, address payable owner){
        require(balances[owner] >= aTokenAmount, "Insufficient Balance");
        balances[owner] = sub(balances[owner], aTokenAmount);
        owner.transfer(aTokenAmount);
    }

}

contract WETH9_ {
    string public name     = "Wrapped Ether";
    string public symbol   = "WETH";
    uint8  public decimals = 18;

    event  Approval(address indexed src, address indexed guy, uint wad);
    event  Transfer(address indexed src, address indexed dst, uint wad);
    event  Deposit(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);

    mapping (address => uint)                       public  balanceOf;
    mapping (address => mapping (address => uint))  public  allowance;

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        Deposit(msg.sender, msg.value);
    }
    function withdraw(uint wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        msg.sender.transfer(wad);
        Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint) {
        return address(this).balance;
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        Transfer(src, dst, wad);

        return true;
    }
}

contract WETHGateway {

    using WadRayMath for uint256;

    AToken aToken;

    constructor(address aTokenAddress){
        aToken = AToken(aTokenAddress);
    }

    fallback() external payable {}

    function depositETH(
        address lendingPool,
        address onBehalfOf,
        uint16 referralCode
    ) external payable{

        require(msg.value>0, "Required amount");
        aToken.mint{value: msg.value}(onBehalfOf);


    }

    function withdrawETH(
        address lendingPool,
        uint256 amount,
        address payable onBehalfOf
    ){
        aToken.withdrawUnderlying(amount, onBehalfOf);
    }

}


contract aRaiEthInsuranceTest is DSTest, SafeMath {
    Hevm hevm;
    using WadRayMath for uint256;

    TestSAFEEngine safeEngine;
    TestAccountingEngine accountingEngine;
    LiquidationEngine liquidationEngine;
    OracleRelayer oracleRelayer;
    TaxCollector taxCollector;

    BasicCollateralJoin collateralA;
    EnglishCollateralAuctionHouse collateralAuctionHouse;

    GebSafeManager safeManager;

    LendingPool pool;

    Feed goldFSM;
    Feed goldMedian;

    WETH9_ gold;
    AToken aEth;

    WETHGateway wethGateway;
    aRaiEthInsurance saviour;
    SAFESaviourRegistry saviourRegistry;

    FakeUser alice;
    address me;

    // Saviour parameters
    uint256 saveCooldown = 1 days;
    uint256 keeperPayout = 0.5 ether;
    uint256 minKeeperPayoutValue = 0.01 ether;
    uint256 payoutToSAFESize = 40;
    uint256 defaultDesiredCollateralizationRatio = 300;
    uint256 WAD = 10**18;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    fallback() external payable {}

    function getScaledBalance(uint amount) internal returns(uint256){
        return amount.rayMul(pool.getReserveNormalizedIncome(aEth.UNDERLYING_ASSET_ADDRESS()));
    }

    // Default actions/scenarios
    function default_modify_collateralization(uint256 safe, address safeHandler) internal {
        gold.deposit{value: 100 ether}();
        gold.approve(address(collateralA), 100 ether);
        collateralA.join(address(safeHandler), 100 ether);
        alice.doModifySAFECollateralization(safeManager, safe, 40 ether, 100 ether);
    }
    function default_liquidate_safe(address safeHandler) internal {
        goldMedian.updateCollateralPrice(3 ether);
        goldFSM.updateCollateralPrice(3 ether);
        oracleRelayer.updateCollateralPrice("gold");

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(111 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        // the full SAFE is liquidated
        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", me);
        assertEq(lockedCollateral, 0);
        assertEq(generatedDebt, 0);
        // all debt goes to the accounting engine
        assertEq(accountingEngine.totalQueuedDebt(), rad(100 ether));
        // auction is for all collateral
        (,uint amountToSell,,,,,, uint256 amountToRaise) = collateralAuctionHouse.bids(auction);
        assertEq(amountToSell, 40 ether);
        assertEq(amountToRaise, rad(110 ether));
    }
    function default_repay_all_debt(uint256 safe, address safeHandler) internal {
        alice.doModifySAFECollateralization(safeManager, safe, 0, -100 ether);
    }
    function default_save(uint256 safe, address safeHandler, uint desiredCRatio) internal {
        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, desiredCRatio);
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));

        goldMedian.updateCollateralPrice(3 ether);
        goldFSM.updateCollateralPrice(3 ether);
        oracleRelayer.updateCollateralPrice("gold");

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());

        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertTrue(saviour.canSave(safeHandler));

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(111 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint256 preSaveKeeperBalance = address(this).balance;
        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        assertEq(auction, 0);
        assertEq(address(this).balance - preSaveKeeperBalance, saviour.keeperPayout());

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", safeHandler);
        assertEq(lockedCollateral * 3E27 * 100 / (generatedDebt * oracleRelayer.redemptionPrice()), desiredCRatio);
    }
    function default_save(uint256 safe, address safeHandler) internal {
        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));

        goldMedian.updateCollateralPrice(3 ether);
        goldFSM.updateCollateralPrice(3 ether);
        oracleRelayer.updateCollateralPrice("gold");
        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());

        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertTrue(saviour.canSave(safeHandler));

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(111 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        assertEq(auction, 0);

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", safeHandler);
        assertEq(lockedCollateral * 3E27 * 100 / (generatedDebt * oracleRelayer.redemptionPrice()), saviour.defaultDesiredCollateralizationRatio());
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new TestSAFEEngine();
        safeEngine = safeEngine;


        goldFSM    = new Feed(3.75 ether, true);
        goldMedian = new Feed(3.75 ether, true);
        goldFSM.updatePriceSource(address(goldMedian));

        oracleRelayer = new OracleRelayer(address(safeEngine));
        oracleRelayer.modifyParameters("gold", "orcl", address(goldFSM));
        oracleRelayer.modifyParameters("gold", "safetyCRatio", ray(1.5 ether));
        oracleRelayer.modifyParameters("gold", "liquidationCRatio", ray(1.5 ether));
        safeEngine.addAuthorization(address(oracleRelayer));

        accountingEngine = new TestAccountingEngine(
          address(safeEngine), address(0x1), address(0x2)
        );
        safeEngine.addAuthorization(address(accountingEngine));

        taxCollector = new TaxCollector(address(safeEngine));
        taxCollector.initializeCollateralType("gold");
        taxCollector.modifyParameters("primaryTaxReceiver", address(accountingEngine));
        safeEngine.addAuthorization(address(taxCollector));

        liquidationEngine = new LiquidationEngine(address(safeEngine));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));

        safeEngine.addAuthorization(address(liquidationEngine));
        accountingEngine.addAuthorization(address(liquidationEngine));

        gold = new WETH9_();

        pool = new LendingPool();

        aEth = new AToken(address(pool));

        wethGateway = new WETHGateway(address(aEth));

        safeEngine.initializeCollateralType("gold");
        collateralA = new BasicCollateralJoin(address(safeEngine), "gold", address(gold));
        safeEngine.addAuthorization(address(collateralA));

        safeEngine.modifyParameters("gold", "safetyPrice", ray(1 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
        safeEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        collateralAuctionHouse = new EnglishCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), "gold");
        collateralAuctionHouse.addAuthorization(address(liquidationEngine));

        liquidationEngine.addAuthorization(address(collateralAuctionHouse));
        liquidationEngine.modifyParameters("gold", "collateralAuctionHouse", address(collateralAuctionHouse));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1 ether);

        safeEngine.addAuthorization(address(collateralAuctionHouse));
        safeEngine.approveSAFEModification(address(collateralAuctionHouse));

        safeManager = new GebSafeManager(address(safeEngine));
        oracleRelayer.updateCollateralPrice("gold");

        saviourRegistry = new SAFESaviourRegistry(saveCooldown);
        saviour = new aRaiEthInsurance(
            address(collateralA),
            address(liquidationEngine),
            address(oracleRelayer),
            address(safeEngine),
            address(safeManager),
            address(saviourRegistry),
            keeperPayout,
            minKeeperPayoutValue,
            payoutToSAFESize,
            defaultDesiredCollateralizationRatio,
            address(aEth),
            address(wethGateway)
        );
        saviourRegistry.toggleSaviour(address(saviour));
        liquidationEngine.connectSAFESaviour(address(saviour));

        me    = address(this);
        alice = new FakeUser();

        payable(address(alice)).transfer(500 ether);

    }

    function test_deposit_as_owner() public {
        assertEq(liquidationEngine.safeSaviours(address(saviour)), 1);

        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        payable(address(alice)).transfer(200 ether);
        alice.doDeposit(saviour, safe, 200 ether);

        assertEq(aEth.balanceOf(address(saviour)), 200 ether);
        assertEq(saviour.collateralCover(safeHandler), getScaledBalance(200 ether));
    }
    function test_deposit_as_random() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        gold.approve(address(saviour), 500 ether);
        saviour.deposit{value: 500 ether}(safe);

        assertEq(aEth.balanceOf(address(saviour)), 500 ether);
        assertEq(saviour.collateralCover(safeHandler), getScaledBalance(500 ether));
    }
    function testFail_deposit_after_repaying_debt() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        saviour.deposit{value: 250 ether}(safe);

        default_repay_all_debt(safe, safeHandler);
        saviour.deposit{value: 250 ether}(safe);
    }
    function testFail_deposit_when_no_debt() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        saviour.deposit{value: 500 ether}(safe);
    }
    function testFail_deposit_when_not_engine_approved() public {
        liquidationEngine.disconnectSAFESaviour(address(saviour));

        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        saviour.deposit{value: 250 ether}(safe);
    }
    function test_deposit_then_withdraw_as_owner() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        payable(address(alice)).transfer(500 ether);
        alice.doDeposit(saviour, safe, 500 ether);

        alice.doWithdraw(saviour, safe, 100 ether);
        assertEq(aEth.balanceOf(address(saviour)), 400 ether);
        assertEq(saviour.collateralCover(safeHandler), getScaledBalance(400 ether));

        alice.doWithdraw(saviour, safe, 400 ether);
        assertEq(aEth.balanceOf(address(saviour)), 0);
        assertEq(saviour.collateralCover(safeHandler), 0);
    }
    function test_withdraw_when_safe_has_no_debt() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);

        payable(address(alice)).transfer(500 ether);
        alice.doDeposit(saviour, safe, 500 ether);

        default_repay_all_debt(safe, safeHandler);
        alice.doWithdraw(saviour, safe, 500 ether);
        assertEq(aEth.balanceOf(address(saviour)), 0);
        assertEq(saviour.collateralCover(safeHandler), 0);
    }
    function test_deposit_then_withdraw_as_approved() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);
        uint256 preBalance = address(this).balance;
        payable(address(alice)).transfer(500 ether);
        alice.doDeposit(saviour, safe, 500 ether);

        assertEq(address(this).balance, sub(preBalance, 500 ether));

        alice.doSafeAllow(safeManager, safe, address(this), 1);
        saviour.withdraw(safe, 250 ether);

        assertEq(address(this).balance, sub(preBalance, 250 ether));
        assertEq(aEth.balanceOf(address(saviour)), 250 ether);
        assertEq(saviour.collateralCover(safeHandler), getScaledBalance(250 ether));
    }
    function testFail_deposit_then_withdraw_as_non_approved() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_modify_collateralization(safe, safeHandler);
        uint256 preBalance = address(this).balance;

        payable(address(alice)).transfer(500 ether);
        alice.doDeposit(saviour, safe, 500 ether);

        assertEq(address(this).balance, sub(preBalance, 500 ether));
        saviour.withdraw(safe, 250 ether);
    }
    function test_set_desired_cratio_by_owner() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        alice.doSetDesiredCollateralizationRatio(saviour, safe, 151);
        assertEq(saviour.desiredCollateralizationRatios("gold", safeHandler), 151);
    }
    function test_set_desired_cratio_by_approved() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        alice.doSafeAllow(safeManager, safe, address(this), 1);
        saviour.setDesiredCollateralizationRatio(safe, 151);
        assertEq(saviour.desiredCollateralizationRatios("gold", safeHandler), 151);
    }
    function testFail_set_desired_cratio_by_unauthed() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        saviour.setDesiredCollateralizationRatio(safe, 151);
    }
    function testFail_set_desired_cratio_above_max_limit() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        alice.doSafeAllow(safeManager, safe, address(this), 1);
        saviour.setDesiredCollateralizationRatio(safe, saviour.MAX_CRATIO() + 1);
    }
    function test_liquidate_no_saviour_set() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);
        default_liquidate_safe(safeHandler);
    }
    function test_add_remove_saviour_from_manager() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));
        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(0));
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(0));
    }
    function test_liquidate_add_saviour_with_no_cover() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, 200);

        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));
        assertTrue(!saviour.canSave(safeHandler));
        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertEq(saviour.tokenAmountUsedToSave(safeHandler), 13333333333333333333);

        default_liquidate_safe(safeHandler);
    }
    function test_liquidate_cover_only_for_keeper_payout() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, 200);

        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));
        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertEq(saviour.getKeeperPayoutValue(), 1.875 ether);

        payable(address(alice)).transfer(saviour.keeperPayout());
        alice.doDeposit(saviour, safe, saviour.keeperPayout());

        assertTrue(!saviour.canSave(safeHandler));
        default_liquidate_safe(safeHandler);
    }
    function test_liquidate_cover_only_no_keeper_payout() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, 200);
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler));
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler));

        assertTrue(!saviour.canSave(safeHandler));
        default_liquidate_safe(safeHandler);
    }
    function test_liquidate_keeper_payout_value_small() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);

        default_modify_collateralization(safe, safeHandler);

        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(saviour));
        alice.doSetDesiredCollateralizationRatio(saviour, safe, 200);
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));

        goldMedian.updateCollateralPrice(0.02 ether - 1);
        goldFSM.updateCollateralPrice(0.02 ether - 1);

        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(saviour));
        assertEq(saviour.getKeeperPayoutValue(), 9999999999999999);

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());

        assertTrue(!saviour.keeperPayoutExceedsMinValue());
        assertTrue(saviour.canSave(safeHandler));

        // Liquidate with the current 0.02 ether - 1 price
        oracleRelayer.updateCollateralPrice("gold");

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(111 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        // the full SAFE is liquidated
        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", me);
        assertEq(lockedCollateral, 0);
        assertEq(generatedDebt, 0);
        // all debt goes to the accounting engine
        assertEq(accountingEngine.totalQueuedDebt(), rad(100 ether));
        // auction is for all collateral
        (,uint amountToSell,,,,,, uint256 amountToRaise) = collateralAuctionHouse.bids(auction);
        assertEq(amountToSell, 40 ether);
        assertEq(amountToRaise, rad(110 ether));
    }
    function test_successfully_save_small_cratio() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler, 200);
    }
    function test_successfully_save_max_cratio() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler, saviour.MAX_CRATIO());
    }
    function test_successfully_save_default_cratio() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler);
    }
    function test_liquidate_twice_in_row_same_saviour() public {
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler, 155);

        // Add collateral and try to save again
        goldMedian.updateCollateralPrice(2 ether);
        goldFSM.updateCollateralPrice(2 ether);
        oracleRelayer.updateCollateralPrice("gold");

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        alice.doDeposit(saviour, safe, saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());

        assertTrue(saviour.keeperPayoutExceedsMinValue());
        assertTrue(saviour.canSave(safeHandler));

        // Can't save because the SAFE saviour registry break time hasn't elapsed
        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        assertEq(auction, 1);
    }
    function test_liquidate_twice_in_row_different_saviours() public {
        // Create a new saviour and set it up
        aRaiEthInsurance secondSaviour = new aRaiEthInsurance(
            address(collateralA),
            address(liquidationEngine),
            address(oracleRelayer),
            address(safeEngine),
            address(safeManager),
            address(saviourRegistry),
            keeperPayout,
            minKeeperPayoutValue,
            payoutToSAFESize,
            defaultDesiredCollateralizationRatio,
            address(aEth),
            address(wethGateway)
        );
        saviourRegistry.toggleSaviour(address(secondSaviour));
        liquidationEngine.connectSAFESaviour(address(secondSaviour));

        // Save the safe with the original saviour first
        uint safe = alice.doOpenSafe(safeManager, "gold", address(alice));
        address safeHandler = safeManager.safes(safe);
        default_save(safe, safeHandler, 155);

        // Try to save with the second saviour afterwards
        alice.doProtectSAFE(safeManager, safe, address(liquidationEngine), address(secondSaviour));
        assertEq(liquidationEngine.chosenSAFESaviour("gold", safeHandler), address(secondSaviour));

        goldMedian.updateCollateralPrice(1.5 ether);
        goldFSM.updateCollateralPrice(1.5 ether);
        oracleRelayer.updateCollateralPrice("gold");

        payable(address(alice)).transfer(saviour.tokenAmountUsedToSave(safeHandler) + saviour.keeperPayout());
        alice.doDeposit(secondSaviour, safe, secondSaviour.tokenAmountUsedToSave(safeHandler) + secondSaviour.keeperPayout());

        assertTrue(secondSaviour.keeperPayoutExceedsMinValue());
        assertTrue(secondSaviour.canSave(safeHandler));

        // Can't save because the SAFE saviour registry break time hasn't elapsed
        uint auction = liquidationEngine.liquidateSAFE("gold", safeHandler);
        assertEq(auction, 1);
    }
}