// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IMultiSignature{
    // 用于检查某个交易是否已通过多签名验证
    function getValidSignature(bytes32 msghash,uint256 lastIndex) external view returns(uint256);
}

contract multiSignatureClient{
    // 存储多签名合约地址的存储槽位置
    uint256 private constant multiSignaturePositon = uint256(keccak256("org.multiSignature.storage"));
    // 验证多签名时的初始比较值
    uint256 private constant defaultIndex = 0;

    constructor(address multiSignature) {
        require(multiSignature != address(0), "multiSignatureClient : Multiple signature contract address is zero!");
        saveValue(multiSignaturePositon, uint256(uint160(multiSignature)));
    }


    // 从存储槽中获取多签名合约的地址
    function getMultiSignatureAddress() public view returns (address) {
        return address(uint160(getValue(multiSignaturePositon)));
    }

    modifier validCall(){
        checkMultiSignature();
        _;
    }

    // 检查当前交易是否通过多签名验证
    function checkMultiSignature() internal view {
        uint256 value;
        assembly {
            value := callvalue()
        }
        bytes32 msgHash = keccak256(abi.encodePacked(msg.sender, address(this)));
        address multiSign = getMultiSignatureAddress();
//        uint256 index = getValue(uint256(msgHash));

        // 证该交易是否已被批准
        uint256 newIndex = IMultiSignature(multiSign).getValidSignature(msgHash,defaultIndex);
        // 如果返回的 newIndex 大于 defaultIndex，则表示交易已被批准
        require(newIndex > defaultIndex, "multiSignatureClient : This tx is not aprroved");
//        saveValue(uint256(msgHash),newIndex);
    }

    function saveValue(uint256 position,uint256 value) internal
    {
        assembly {
            sstore(position, value)
        }
    }

    function getValue(uint256 position) internal view returns (uint256 value) {
        assembly {
            value := sload(position)
        }
    }
}