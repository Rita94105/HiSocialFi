// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/proxy/Proxy.sol";

contract SharesProxy is Proxy {
    address private immutable _impl;

    constructor(address _logic, bytes memory _data) {
        (bool success, ) = _logic.delegatecall(_data);
        require(success, "Token failed to initialize");
        _impl = _logic;
    }

    function _implementation() internal view override returns (address) {
        return _impl;
    }
}
