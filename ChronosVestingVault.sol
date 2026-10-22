// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

contract ChronosVestingVault {
    struct VestingSchedule {
        address beneficiary;
        uint256 totalAllocation;
        uint256 releasedAmount;
        uint256 startTimestamp;
        uint256 cliffDuration;
        uint256 totalDuration;
        bool revocable;
        bool isRevoked;
    }

    address payable public immutable vaultAdmin;
    string public vaultIdentifier;
    uint256 public scheduleCounter;
    uint256 public totalVestedBalance;
    bool public isVaultPaused;

    mapping(uint256 => VestingSchedule) public schedules;

    event ScheduleCreated(uint256 indexed scheduleId, address indexed beneficiary, uint256 allocation);
    event TokensReleased(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);
    event ScheduleRevoked(uint256 indexed scheduleId, uint256 unvestedAmountRefunded);
    event ScheduleToppedUp(uint256 indexed scheduleId, uint256 addedAmount);
    event VaultIdentifierUpdated(string newIdentifier);
    event VaultPauseSwitched(bool state);
    event UnallocatedSwept(address indexed recipient, uint256 amount);
    event BeneficiaryTransferred(uint256 indexed scheduleId, address indexed newBeneficiary);

    modifier onlyAdmin() {
        require(msg.sender == vaultAdmin, "ChronosVault: Caller is not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!isVaultPaused, "ChronosVault: Protocol paused");
        _;
    }

    constructor() {
        vaultAdmin = payable(msg.sender);
        vaultIdentifier = "Chronos Base Linear Vesting Core v1";
        isVaultPaused = false;
    }

    // 1. Создание вестинг-расписания с депозитом ETH
    function createVestingSchedule(
        address beneficiary,
        uint256 cliffDuration,
        uint256 totalDuration,
        bool revocable
    ) external payable onlyAdmin whenNotPaused returns (uint256) {
        require(msg.value > 0, "ChronosVault: Allocation must be positive");
        require(beneficiary != address(0), "ChronosVault: Zero beneficiary");
        require(totalDuration >= cliffDuration, "ChronosVault: Duration must exceed cliff");
        require(totalDuration > 0, "ChronosVault: Duration must be > 0");

        scheduleCounter++;
        schedules[scheduleCounter] = VestingSchedule({
            beneficiary: beneficiary,
            totalAllocation: msg.value,
            releasedAmount: 0,
            startTimestamp: block.timestamp,
            cliffDuration: cliffDuration,
            totalDuration: totalDuration,
            revocable: revocable,
            isRevoked: false
        });

        totalVestedBalance += msg.value;
        emit ScheduleCreated(scheduleCounter, beneficiary, msg.value);
        return scheduleCounter;
    }

    // 2. Дополнительное пополнение существующего вестинга
    function topUpSchedule(uint256 scheduleId) external payable onlyAdmin whenNotPaused {
        VestingSchedule storage s = schedules[scheduleId];
        require(scheduleId > 0 && scheduleId <= scheduleCounter, "ChronosVault: Invalid schedule");
        require(!s.isRevoked, "ChronosVault: Schedule revoked");
        require(msg.value > 0, "ChronosVault: Zero topup rejected");

        s.totalAllocation += msg.value;
        totalVestedBalance += msg.value;

        emit ScheduleToppedUp(scheduleId, msg.value);
    }

    // 3. Вывод доступных по графику разлоченных средств
    function releaseVestedFunds(uint256 scheduleId) external whenNotPaused {
        VestingSchedule storage s = schedules[scheduleId];
        require(scheduleId > 0 && scheduleId <= scheduleCounter, "ChronosVault: Invalid schedule");
        require(msg.sender == s.beneficiary || msg.sender == vaultAdmin, "ChronosVault: Unauthorized caller");
        require(!s.isRevoked, "ChronosVault: Schedule revoked");

        uint256 releasable = calculateReleasableAmount(scheduleId);
        require(releasable > 0, "ChronosVault: No funds available for release");

        s.releasedAmount += releasable;
        totalVestedBalance -= releasable;

        (bool sent, ) = payable(s.beneficiary).call{value: releasable}("");
        require(sent, "ChronosVault: Transfer failed");

        emit TokensReleased(scheduleId, s.beneficiary, releasable);
    }

    // 4. Отзыв вестинга с возвратом неразлоченного остатка администратору
    function revokeSchedule(uint256 scheduleId) external onlyAdmin {
        VestingSchedule storage s = schedules[scheduleId];
        require(scheduleId > 0 && scheduleId <= scheduleCounter, "ChronosVault: Invalid schedule");
        require(s.revocable, "ChronosVault: Not revocable");
        require(!s.isRevoked, "ChronosVault: Already revoked");

        uint256 releasable = calculateReleasableAmount(scheduleId);
        uint256 unvestedAmount = s.totalAllocation - s.releasedAmount - releasable;

        s.isRevoked = true;
        totalVestedBalance -= unvestedAmount;

        // Если были накоплены разлоченные средства — отправляем бенефициару
        if (releasable > 0) {
            s.releasedAmount += releasable;
            totalVestedBalance -= releasable;
            (bool sentBeneficiary, ) = payable(s.beneficiary).call{value: releasable}("");
            require(sentBeneficiary, "ChronosVault: Beneficiary payout failed");
        }

        // Остаток неразлоченных средств возвращается админу
        if (unvestedAmount > 0) {
            (bool sentAdmin, ) = vaultAdmin.call{value: unvestedAmount}("");
            require(sentAdmin, "ChronosVault: Refund transfer failed");
        }

        emit ScheduleRevoked(scheduleId, unvestedAmount);
    }

    // 5. Перенос прав бенефициара на новый адрес
    function changeBeneficiary(uint256 scheduleId, address newBeneficiary) external {
        VestingSchedule storage s = schedules[scheduleId];
        require(msg.sender == s.beneficiary || msg.sender == vaultAdmin, "ChronosVault: Forbidden");
        require(newBeneficiary != address(0), "ChronosVault: Zero address");
        require(!s.isRevoked, "ChronosVault: Schedule revoked");

        s.beneficiary = newBeneficiary;
        emit BeneficiaryTransferred(scheduleId, newBeneficiary);
    }

    // 6. Обновление дескриптора хранилища
    function updateIdentifier(string calldata newId) external onlyAdmin {
        require(bytes(newId).length > 0, "ChronosVault: Empty identifier");
        vaultIdentifier = newId;
        emit VaultIdentifierUpdated(newId);
    }

    // 7. Переключение паузы
    function setVaultPause(bool paused) external onlyAdmin {
        isVaultPaused = paused;
        emit VaultPauseSwitched(paused);
    }

    // 8. Вывод нераспределенных свободных средств
    function sweepSurplus() external onlyAdmin {
        uint256 balance = address(this).balance;
        uint256 surplus = balance > totalVestedBalance ? balance - totalVestedBalance : 0;
        if (surplus == 0 && balance > 0 && totalVestedBalance == 0) {
            surplus = balance;
        }
        require(surplus > 0, "ChronosVault: No surplus available");

        (bool sent, ) = vaultAdmin.call{value: surplus}("");
        require(sent, "ChronosVault: Sweep failed");

        emit UnallocatedSwept(vaultAdmin, surplus);
    }

    // Внутренний расчет доступного к выводу баланса
    function calculateReleasableAmount(uint256 scheduleId) public view returns (uint256) {
        VestingSchedule memory s = schedules[scheduleId];
        if (s.isRevoked || block.timestamp < s.startTimestamp + s.cliffDuration) {
            return 0;
        }
        if (block.timestamp >= s.startTimestamp + s.totalDuration) {
            return s.totalAllocation - s.releasedAmount;
        }

        uint256 elapsed = block.timestamp - s.startTimestamp;
        uint256 vestedTotal = (s.totalAllocation * elapsed) / s.totalDuration;
        return vestedTotal > s.releasedAmount ? vestedTotal - s.releasedAmount : 0;
    }
}