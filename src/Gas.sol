// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./Ownable.sol";

uint256 constant MAX_TIER = 254;
uint256 constant TRADE_FLAG = 1;
uint256 constant BASIC_FLAG = 0;
uint256 constant DIVIDEND_FLAG = 1;

contract GasContract is Ownable {
    uint256 public totalSupply = 0; // cannot be updated
    uint256 public paymentCounter = 0;
    mapping(address => uint256) public balances;
    uint256 public tradePercent = 12;
    address public contractOwner;
    uint256 public tradeMode = 0;
    mapping(address => Payment[]) public payments;
    mapping(address => uint256) public whitelist;
    address[5] public administrators;
    bool public isReady = false;
    enum PaymentType {
        Unknown,
        BasicPayment,
        Refund,
        Dividend,
        GroupPayment
    }
    PaymentType constant defaultPayment = PaymentType.Unknown;

    History[] public paymentHistory; // when a payment was updated

    struct Payment {
        PaymentType paymentType;
        uint256 paymentID;
        bool adminUpdated;
        string recipientName; // max 8 characters
        address recipient;
        address admin; // administrators address
        uint256 amount;
    }

    struct History {
        uint256 lastUpdate;
        address updatedBy;
        uint256 blockNumber;
    }
    bool wasLastOdd = true;
    mapping(address => uint256) public isOddWhitelistUser;
    
    struct ImportantStruct {
        uint256 amount;
        bool paymentStatus;
    }
    mapping(address => ImportantStruct) public whiteListStruct;

    error UnauthorizedCaller();
    error AddressNotWhitelisted();
    error InvalidTier();
    error ZerothAddressNotAllowed();
    error InsufficientSenderBalance();
    error RecipientNameTooLong();
    error InvalidPaymentId();
    error InvalidAmount();
    error TierExceedsMaximumLimit(uint256 maxLimit);
    error ContractHacked();

    event AddedToWhitelist(address userAddress, uint256 tier);

    event supplyChanged(address indexed, uint256 indexed);
    event Transfer(address recipient, uint256 amount);
    event PaymentUpdated(
        address admin,
        uint256 ID,
        uint256 amount,
        string recipient
    );
    event WhiteListTransfer(address indexed);

    // TODO look at constructor
    constructor(address[] memory _admins, uint256 _totalSupply) {
        contractOwner = msg.sender;
        totalSupply = _totalSupply;

        for (uint256 ii = 0; ii < administrators.length; ii++) {
            if (_admins[ii] != address(0)) {
                administrators[ii] = _admins[ii];
                if (_admins[ii] == contractOwner) {
                    balances[contractOwner] = totalSupply;
                } else {
                    balances[_admins[ii]] = 0;
                }
                if (_admins[ii] == contractOwner) {
                    emit supplyChanged(_admins[ii], totalSupply);
                } else if (_admins[ii] != contractOwner) {
                    emit supplyChanged(_admins[ii], 0);
                }
            }
        }
    }

    function getPaymentHistory()
        public
        view
        returns (History[] memory paymentHistory_)
    {
        return paymentHistory;
    }

    function onlyAdminOrOwner(address sender) private view {
        if(sender != contractOwner || !checkForAdmin(sender)) {
            revert UnauthorizedCaller();
        }
    }

    function checkIfWhiteListed(uint256 usersTier) private pure {
        if(usersTier == 0) {
            revert AddressNotWhitelisted();
        }
        if(usersTier > 4) {
            revert InvalidTier();
        }
    }

    function checkForAdmin(address _user) public view returns (bool admin) {
        admin = false;

        for (uint256 ii = 0; ii < administrators.length; ii++) {
            if (administrators[ii] == _user) {
                admin = true;

                break;
            }
        }

        return admin;
    }

    function balanceOf(address _user) public view returns (uint256) {
        return balances[_user];
    }

    function getTradingMode() public pure returns (bool mode) {
        mode = false;

        if (TRADE_FLAG == 1 || DIVIDEND_FLAG == 1) {
            mode = true;
        } else {
            mode = false;
        }
        return mode;
    }


    function addHistory(address _updateAddress, bool _tradeMode)
        internal
        returns (bool status_, bool tradeMode_)
    {
        History memory history = History({
            blockNumber: block.number,
            lastUpdate: block.timestamp,
            updatedBy: _updateAddress
        });
        paymentHistory.push(history);
        return (true, _tradeMode);
    }

    function getPayments(address _user)
        external
        view
        returns (Payment[] memory payments_)
    {
        if(_user == address (0)) {
            revert ZerothAddressNotAllowed();
        }

        return payments[_user];
    }

    function transfer(
        address _recipient,
        uint256 _amount,
        string calldata _name
    ) public returns (bool status_) {
        if(balances[msg.sender] < _amount) {
            revert InsufficientSenderBalance();
        }
        if(bytes(_name).length > 8) {
            revert RecipientNameTooLong();
        }

        balances[msg.sender] -= _amount;
        balances[_recipient] += _amount;
        emit Transfer(_recipient, _amount);

        // update all the payment struct data together
        Payment memory payment = Payment({
            admin: address(0),
            adminUpdated: false,
            paymentType: PaymentType.BasicPayment,
            recipient: _recipient,
            amount: _amount,
            recipientName: _name,
            paymentID: ++paymentCounter
        });
        payments[msg.sender].push(payment);

        return true;
    }

    function updatePayment(
        address _user,
        uint256 _ID,
        uint256 _amount,
        PaymentType _type
    ) public {
        onlyAdminOrOwner(msg.sender);

        if(_user == address(0)) {
            revert ZerothAddressNotAllowed();
        }
        if(_ID == 0) {
            revert InvalidPaymentId();
        }
        if(_amount == 0) {
            revert InvalidAmount();
        }

        bool tradingMode = getTradingMode();

        for (uint256 ii = 0; ii < payments[_user].length; ii++) {
            if (payments[_user][ii].paymentID == _ID) {
                payments[_user][ii].adminUpdated = true;
                payments[_user][ii].admin = _user;
                payments[_user][ii].paymentType = _type;
                payments[_user][ii].amount = _amount;

                addHistory(_user, tradingMode);

                emit PaymentUpdated(
                    msg.sender,
                    _ID,
                    _amount,
                    payments[_user][ii].recipientName
                );

                break;
            }
        }
    }

    function addToWhitelist(address _userAddrs, uint256 _tier)
        public
    {
        onlyAdminOrOwner(msg.sender);

        if(_tier > MAX_TIER) {
            revert TierExceedsMaximumLimit(MAX_TIER);
        }

        whitelist[_userAddrs] = _tier;
        // this can get cleaned up
        if (_tier > 3) {
            whitelist[_userAddrs] -= _tier;
            whitelist[_userAddrs] = 3;
        } else if (_tier == 1) {
            whitelist[_userAddrs] -= _tier;
            whitelist[_userAddrs] = 1;
        } else {
            whitelist[_userAddrs] -= _tier;
            whitelist[_userAddrs] = 2;
        }
        if (wasLastOdd == true) {
            wasLastOdd = false;
            isOddWhitelistUser[_userAddrs] = 1;
        } else if (wasLastOdd == false) {
            wasLastOdd = true;
            isOddWhitelistUser[_userAddrs] = 0;
        } else {
            revert ContractHacked();
        }
        emit AddedToWhitelist(_userAddrs, _tier);
    }

    function whiteTransfer(
        address _recipient,
        uint256 _amount
    ) external {
        checkIfWhiteListed(whitelist[msg.sender]);

        whiteListStruct[msg.sender] = ImportantStruct(_amount, true);

        if(balances[msg.sender] < _amount) {
            revert InsufficientSenderBalance();
        }
        if(_amount < 3) {
            revert InvalidAmount();
        }

        balances[msg.sender] -= _amount;
        balances[_recipient] += _amount;
        balances[msg.sender] += whitelist[msg.sender];
        balances[_recipient] -= whitelist[msg.sender];
        
        emit WhiteListTransfer(_recipient);
    }

    function getPaymentStatus(address sender) public view returns (bool, uint256) {
        return (whiteListStruct[sender].paymentStatus, whiteListStruct[sender].amount);
    }

    receive() external payable {
        payable(msg.sender).transfer(msg.value);
    }


    fallback() external payable {
         payable(msg.sender).transfer(msg.value);
    }
}