// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

//import "src/IMetaPool.sol";
import "src/IERC20.sol";
import "src/IMetaPool.sol";
import "src/IZapDepositor3pool.sol";

abstract contract CurvePoolAdapter {

    IERC20 dola;
    address crvMetapool;
    IZapDepositor3pool zapDepositor;
    uint constant PRECISION = 10_000;
    uint immutable CRVPRECISION;

    constructor(address dola_, address crvMetapool_, address zapDepositor_, uint CRVPRECISION_){
        dola = IERC20(dola_);
        crvMetapool = crvMetapool_;
        zapDepositor = IZapDepositor3pool(zapDepositor_);
        CRVPRECISION = CRVPRECISION_;
        //Approve max uint256 spend for crvMetapool, from this address
        dola.approve(zapDepositor_, type(uint256).max);
        IERC20(crvMetapool_).approve(zapDepositor_, type(uint256).max);
    }
    event log_uint(uint);
    /**
    @notice Function for depositing into curve metapool.

    @param amountDola Amount of dola to be deposited into metapool

    @param allowedSlippage Max allowed slippage. 1 = 0.0001%

    @return Amount of Dola-3CRV tokens bought
    */
    function metapoolDeposit(uint256 amountDola, uint allowedSlippage) internal returns(uint256){
        //TODO: Should this be corrected for 3CRV virtual price?
        uint[4] memory amounts = [amountDola, 0, 0 , 0];
        uint minCrvLPOut = amountDola * 10**18 / IMetaPool(crvMetapool).get_virtual_price() * (PRECISION - allowedSlippage) / PRECISION;
        return zapDepositor.add_liquidity(crvMetapool, amounts, minCrvLPOut);
    }

    /**
    @notice Function for depositing into curve metapool.

    @param amountDola Amount of dola to be withdrawn from the metapool

    @param allowedSlippage Max allowed slippage. 1 = 0.0001%

    @return Amount of Dola tokens received
    */
    function metapoolWithdraw(uint amountDola, uint allowedSlippage) internal returns(uint256){
        //TODO: May be more accurate ways to calculate this
        uint[4] memory amounts = [amountDola, 0, 0 , 0];
        uint amountCrvLp = zapDepositor.calc_token_amount(crvMetapool, amounts, false);
        require(amountDola > amountCrvLp*IMetaPool(crvMetapool).get_virtual_price() / 10**18 * (PRECISION - allowedSlippage) / PRECISION, "LOSS EXCEED WITHDRAW MAX LOSS");
        uint dolaMinOut = amountDola * (PRECISION - allowedSlippage) / PRECISION;
        return zapDepositor.remove_liquidity_one_coin(crvMetapool, amountCrvLp, 0, dolaMinOut);
    }

    function lpForDola(uint amountDola) internal view returns(uint256){
        uint[4] memory amounts = [amountDola, 0, 0 , 0];
        return zapDepositor.calc_token_amount(crvMetapool, amounts, false);
    }
}
