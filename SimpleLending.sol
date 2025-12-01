// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title SimpleP2PLending - Contrato didáctico de préstamos P2P con colateral e intereses
/// @notice Este contrato es educativo. NO usar en producción sin auditoría.
contract SimpleP2PLending {
    // --- Datos ---
    address public admin;
    uint256 public loanCounter;

    struct Loan {
        address borrower;      // quien solicita
        address lender;        // quien financia (0 si aun no financiada)
        uint256 principal;     // cantidad prestada (wei)
        uint256 collateral;    // cantidad enviada por el borrower al crear la solicitud (wei)
        uint256 interestBps;   // interes total en puntos base (ej. 500 = 5.00%)
        uint256 dueTimestamp;  // fecha limite de pago (timestamp)
        bool funded;           // si ya fue financiada
        bool repaid;           // si ya fue repagada
        bool liquidated;       // si se liquidó (colateral tomado por lender)
    }

    mapping(uint256 => Loan) public loans;

    // reentrancy guard sencillo
    uint256 private _status;
    modifier nonReentrant() {
        require(_status == 0, "ReentrancyGuard: reentrant call");
        _status = 1;
        _;
        _status = 0;
    }

    // eventos
    event LoanRequested(uint256 indexed loanId, address indexed borrower, uint256 principal, uint256 collateral, uint256 interestBps, uint256 dueTimestamp);
    event LoanFunded(uint256 indexed loanId, address indexed lender);
    event LoanRepaid(uint256 indexed loanId, address indexed borrower, uint256 amountPaid);
    event LoanLiquidated(uint256 indexed loanId, address indexed lender, uint256 collateralTaken);

    constructor() {
        admin = msg.sender;
        _status = 0;
        loanCounter = 0;
    }

    // 1) BORROWER: crear solicitud de prestamo (envia colateral)
    /// @notice Crear una solicitud de préstamo. El borrower envía el colateral con la tx.
    /// @param _principal Monto solicitado en wei (lo que quiere recibir cuando se financie)
    /// @param _durationDays Duración del préstamo en días
    /// @param _interestBps Interés total a pagar en puntos base (100 bps = 1%)
    function requestLoan(uint256 _principal, uint256 _durationDays, uint256 _interestBps) external payable nonReentrant returns (uint256) {
        require(_principal > 0, "Principal > 0");
        require(_durationDays > 0, "Duration > 0");
        require(msg.value > 0, "Enviar colateral en wei");

        loanCounter += 1;
        uint256 id = loanCounter;

        loans[id] = Loan({
            borrower: msg.sender,
            lender: address(0),
            principal: _principal,
            collateral: msg.value,
            interestBps: _interestBps,
            dueTimestamp: block.timestamp + (_durationDays * 1 days),
            funded: false,
            repaid: false,
            liquidated: false
        });

        emit LoanRequested(id, msg.sender, _principal, msg.value, _interestBps, loans[id].dueTimestamp);
        return id;
    }

    // 2) LENDER: financiar una solicitud
    /// @notice Financiar una solicitud existente. El valor enviado debe ser exactamente el principal.
    /// @param _loanId Id del préstamo a financiar
    function fundLoan(uint256 _loanId) external payable nonReentrant {
        Loan storage L = loans[_loanId];
        require(L.borrower != address(0), "Loan no existe");
        require(!L.funded, "Ya financiada");
        require(!L.repaid, "Ya repagada");
        require(msg.value == L.principal, "Enviar exacto principal");

        // Marcar como financiada y asignar lender
        L.lender = msg.sender;
        L.funded = true;

        // Transferir principal al borrower (cheque-efectos-interacciones)
        address payable toBorrower = payable(L.borrower);
        toBorrower.transfer(L.principal);

        emit LoanFunded(_loanId, msg.sender);
    }

    // 3) BORROWER: repagar prestamo (principal + interes)
    /// @notice Reembolsar préstamo: debe enviar principal + interés calculado como principal * interestBps / 10000
    /// @param _loanId Id del préstamo
    function repayLoan(uint256 _loanId) external payable nonReentrant {
        Loan storage L = loans[_loanId];
        require(L.borrower != address(0), "Loan no existe");
        require(L.funded, "No fue financiado");
        require(!L.repaid, "Ya repagado");
        require(!L.liquidated, "Fue liquidado");
        require(msg.sender == L.borrower, "Solo borrower puede pagar");

        uint256 interest = (L.principal * L.interestBps) / 10000;
        uint256 totalOwed = L.principal + interest;
        require(msg.value == totalOwed, "Enviar principal + interes exacto");

        // marcar repago
        L.repaid = true;

        // pagar al lender y devolver colateral al borrower (efectos antes de interactuar)
        address payable lenderPayable = payable(L.lender);
        address payable borrowerPayable = payable(L.borrower);

        // transferir al lender
        lenderPayable.transfer(totalOwed);

        // devolver colateral al borrower
        borrowerPayable.transfer(L.collateral);

        emit LoanRepaid(_loanId, L.borrower, totalOwed);
    }

    // 4) LENDER: liquidar (tomar colateral) si borrower no paga a tiempo
    /// @notice Permite al lender tomar el colateral si el préstamo venció y no fue repagado.
    /// @param _loanId Id del préstamo
    function liquidateLoan(uint256 _loanId) external nonReentrant {
        Loan storage L = loans[_loanId];
        require(L.borrower != address(0), "Loan no existe");
        require(L.funded, "No fue financiado");
        require(!L.repaid, "Ya repagado");
        require(!L.liquidated, "Ya liquidado");
        require(msg.sender == L.lender, "Solo lender puede liquidar");
        require(block.timestamp > L.dueTimestamp, "Aun no vencio");

        L.liquidated = true;

        // transferir colateral al lender
        address payable lenderPayable = payable(L.lender);
        lenderPayable.transfer(L.collateral);

        emit LoanLiquidated(_loanId, L.lender, L.collateral);
    }

    // 5) UTILIDADES / CONSULTAS
    function getLoan(uint256 _loanId) external view returns (
        address borrower,
        address lender,
        uint256 principal,
        uint256 collateral,
        uint256 interestBps,
        uint256 dueTimestamp,
        bool funded,
        bool repaid,
        bool liquidated
    ) {
        Loan storage L = loans[_loanId];
        return (L.borrower, L.lender, L.principal, L.collateral, L.interestBps, L.dueTimestamp, L.funded, L.repaid, L.liquidated);
    }

    // fallback para evitar que se envíe ETH sin intención
    receive() external payable {
        revert("No enviar ETH directamente");
    }

    fallback() external payable {
        revert("Fallback no permitido");
    }
    // SOLO PARA DEMO – Forzar que el prestamo este vencido
function forceLoanExpired(uint256 loanId) external {
    Loan storage loan = loans[loanId];
    require(msg.sender == loan.borrower, "Solo el borrower puede forzar demo");
    require(!loan.repaid && !loan.liquidated, "Prestamo ya cerrado");

    // forzamos que la fecha de vencimiento sea en el pasado
    loan.dueTimestamp = block.timestamp - 1; 
}
}
