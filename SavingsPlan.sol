// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SavingsPlan {
    address public owner;
    address public recipient;
    uint256 public depositAmount;
    uint256 public intervalDays;
    uint256 public lastTransferTime;

    event Deposit(address indexed sender, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);
    event AutomaticTransfer(address indexed sender, address indexed recipient, uint256 amount);

    constructor(address _recipient, uint256 _intervalDays) {
        owner = msg.sender;
        recipient = _recipient;
        intervalDays = _intervalDays;
    }

    // Depositar fondos en el contrato
    function deposit() external payable {
        require(msg.sender == owner, "Solo el dueno puede depositar");
        depositAmount += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    // Retirar fondos manualmente
    function withdraw(uint256 amount) external {
        require(msg.sender == owner, "Solo el dueno puede retirar");
        require(depositAmount >= amount, "Fondos insuficientes");
        depositAmount -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }

    // Cambiar el beneficiario de las transferencias automáticas
    function setRecipient(address _newRecipient) external {
        require(msg.sender == owner, "Solo el dueno puede cambiar el beneficiario");
        recipient = _newRecipient;
    }

    // Función para simular la transferencia automática (ejecutada manualmente en Remix)
    function executeAutomaticTransfer() external {
        require(msg.sender == owner, "Solo el dueno puede ejecutar");
        require(block.timestamp >= lastTransferTime + (intervalDays * 1 days), "Tiempo de espera no cumplido");
        require(depositAmount > 0, "No hay fondos para transferir");

        uint256 transferAmount = depositAmount / 10; // Ejemplo: transferir 10% del depósito
        depositAmount -= transferAmount;
        payable(recipient).transfer(transferAmount);
        lastTransferTime = block.timestamp;

        emit AutomaticTransfer(owner, recipient, transferAmount);
    }

    // Función para consultar el saldo del contrato
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
   // SOLO PARA DEMO: Función para simular el paso del tiempo
    function setTimeForDemo() external {
    require(msg.sender == owner, "Solo el dueno puede modificar el tiempo");
    // Forzamos que lastTransferTime sea 2 días atrás (para cumplir el intervalo de 1 día)
    lastTransferTime = block.timestamp - (intervalDays * 1 days) - 1;
}
}
