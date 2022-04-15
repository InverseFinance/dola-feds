pragma solidity ^0.8.0;

import "src/IERC20.sol";

interface IYearnVault is IERC20{
    //Getter functions for public vars
    function token() external view returns (IERC20);
    function depositLimit() external view returns (uint);  // Limit for totalAssets the Vault can hold
    function debtRatio() external view returns (uint);  // Debt ratio for the Vault across all strategies (in BPS, <= 10k)
    function totalDebt() external view returns (uint);  // Amount of tokens that all strategies have borrowed
    function lastReport() external view returns (uint);  // block.timestamp of last report
    function activation() external view returns (uint);  // block.timestamp of contract deployment
    function lockedProfit() external view returns (uint); // how much profit is locked and cant be withdrawn
    function lockedProfitDegradation() external view returns (uint); // rate per block of degradation. DEGRADATION_COEFFICIENT is 100% per block

    //Function interfaces
    function deposit(uint _amount,  address recipient) external returns (uint);
    function withdraw(uint maxShares, address recipient, uint maxLoss) external returns (uint);
    function maxAvailableShares() external returns (uint);
    function pricePerShare() external view returns (uint);
    function totalAssets() external view returns (uint);
}
