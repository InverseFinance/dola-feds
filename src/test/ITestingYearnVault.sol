pragma solidity ^0.8.0;

import "src/IYearnVault.sol";

interface ITestingYearnVault is IYearnVault {
    function setDepositLimit(uint limit) external;
}
