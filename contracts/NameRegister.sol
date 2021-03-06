// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.5;
pragma abicoder v2;

import "./interfaces/IERC20.sol";
import "./libraries/Ownable.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TransferHelper.sol";

contract NameRegister is Ownable {
    using SafeMath for uint;

    uint public lockTime;
    uint public lockAmount;

    address public immutable LockToken;
    
    mapping(bytes32 => NameLock) public NameList;
    mapping(address => bytes32[]) public UserNames;
    mapping(address => uint) public UserClaimed;
    struct NameLock {
        uint startTime;
        uint lockedAmount;
        address register;
    }

    event NameRegistered(bytes32 name, address indexed register, uint timeStamp);
    event NameRenewed(bytes32 name, address indexed register, uint timeStamp);
    event WithdrawToken(address indexed withdrawer, uint amount);

    constructor(address _token) {
        require(_token != address(0));
        LockToken = _token;
    }

    function setLockTime(uint _lockTime) public onlyOwner {
        require(_lockTime > 0);
        lockTime = _lockTime;
    }

    function setLockAmount(uint _lockAmount) public onlyOwner {
        require(_lockAmount > 0);
        lockAmount = _lockAmount;
    }

    function _renew(bytes32 _name) private {
        NameList[_name].startTime = block.timestamp;
    }

    function checkValid(bytes32 name) public view returns(bool) {
        NameLock memory info = NameList[name];
        return info.startTime > 0 && block.timestamp <= info.startTime.add(lockTime);
    }

    function nameOwner(bytes32 name) public view returns(address) {
        return checkValid(name) ? NameList[name].register : address(0x00);
    }

    function userClaimable() public view returns(uint _amount) {
        bytes32[] memory nameArr = UserNames[msg.sender];
        for(uint ii = 0; ii < nameArr.length; ii++) {
            if(!(checkValid(nameArr[ii]) && NameList[nameArr[ii]].register == msg.sender)) {
                _amount = _amount.add(NameList[nameArr[ii]].lockedAmount);
            }
        }
    }

    function checkBalance() public view returns(bool) {
        return IERC20( LockToken ).balanceOf(msg.sender) >= lockAmount;
    }

    function registerName(bytes32 name) public returns(bool) {
        require(lockAmount > 0 && lockTime > 0);

        require(name[0] != 0, "Name is empty");
        require(!checkValid(name), "Already registered name");

        require(checkBalance(), "Insufficient balance to lock");

        TransferHelper.safeTransferFrom(LockToken, msg.sender, address(this), lockAmount);

        NameList[name] = NameLock({
            startTime: block.timestamp,
            lockedAmount: lockAmount,
            register: msg.sender
        });

        UserNames[msg.sender].push(name);

        emit NameRegistered(name, msg.sender, block.timestamp);
        return true;
    }

    function renewName(bytes32 name) public returns(bool) {
        require(name[0] != 0, "Name is empty");
        require(checkValid(name), "This is not registered name");
        require(nameOwner(name) == msg.sender, "Not owner");

        _renew(name);

        emit NameRenewed(name, msg.sender, block.timestamp);
        return true;
    }

    function withdrawToken(uint amount) public {
        require(amount > 0);
        require(userClaimable() - UserClaimed[msg.sender] >= amount, "Insifficient withdrawable amount");

        UserClaimed[msg.sender] = UserClaimed[msg.sender].add(amount);
        TransferHelper.safeTransfer(LockToken, msg.sender, amount);

        emit WithdrawToken(msg.sender, amount);
    }
}