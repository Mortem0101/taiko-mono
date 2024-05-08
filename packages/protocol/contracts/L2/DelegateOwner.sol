// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../common/EssentialContract.sol";
import "../common/LibStrings.sol";
import "../bridge/IBridge.sol";

/// @title DelegateOwner
/// @notice This contract will be the owner of all essential contracts deployed on the L2 chain.
/// @dev Notice that when sending the message on the owner chain, the gas limit of the message must
/// not be zero, so on this chain, some EOA can help execute this transaction.
/// @custom:security-contact security@taiko.xyz
contract DelegateOwner is EssentialContract, IMessageInvocable {
    /// @notice The owner chain ID.
    uint64 public l1ChainId;

    /// @notice The next transaction ID.
    uint64 public nextTxId;

    /// @notice The real owner on L1, supposedly the DAO.
    address public realOwner;

    uint256[48] private __gap;

    /// @notice Emitted when a message is invoked.
    /// @param txId The transaction ID.
    /// @param target The target address.
    /// @param isDelegateCall True if the call is a `delegatecall`.
    /// @param selector The function selector.
    event MessageInvoked(
        uint64 indexed txId, address indexed target, bool isDelegateCall, bytes4 indexed selector
    );

    error DO_DRY_RUN_SUCCEEDED();
    error DO_INVALID_PARAM();
    error DO_INVALID_TX_ID();
    error DO_PERMISSION_DENIED();
    error DO_TARGET_CALL_REVERTED();

    /// @notice Initializes the contract.
    /// @param _realOwner The real owner on L1 that can send a cross-chain message to invoke
    /// `onMessageInvocation`.
    /// @param _addressManager The address of the {AddressManager} contract.
    /// @param _l1ChainId The L1 chain's ID.
    function init(
        address _realOwner,
        address _addressManager,
        uint64 _l1ChainId
    )
        external
        initializer
    {
        // This contract's owner will be itself.
        __Essential_init(address(this), _addressManager);

        if (_realOwner == address(0) || _l1ChainId == 0 || _l1ChainId == block.chainid) {
            revert DO_INVALID_PARAM();
        }

        realOwner = _realOwner;
        l1ChainId = _l1ChainId;
    }

    function acceptOwnership(address target) external {
        Ownable2StepUpgradeable(target).acceptOwnership();
    }

    /// @inheritdoc IMessageInvocable
    /// @dev Do not guard with nonReentrant as this function may re-enter the contract as _data
    /// represents calls to address(this).
    function onMessageInvocation(bytes calldata _data)
        external
        payable
        onlyFromNamed(LibStrings.B_BRIDGE)
    {
        IBridge.Context memory ctx = IBridge(msg.sender).context();
        if (ctx.srcChainId != l1ChainId || ctx.from != realOwner) {
            revert DO_PERMISSION_DENIED();
        }
        _invokeCall(_data, true);
    }

    /// @notice Dry run a message invocation but always revert.
    /// If this tx is reverted with DO_TRY_RUN_SUCCEEDED, the try run is successful.
    function dryRunMessageInvocation(bytes calldata _data) external payable {
        _invokeCall(_data, false);
        revert DO_DRY_RUN_SUCCEEDED();
    }

    function decodeMessageData(bytes calldata _data)
        public
        pure
        returns (uint64, address, bool, bytes memory)
    {
        return abi.decode(_data, (uint64, address, bool, bytes));
    }

    function _authorizePause(address, bool) internal pure override notImplemented { }

    function _invokeCall(bytes calldata _data, bool _verifyTxId) private {
        (uint64 txId, address target, bool isDelegateCall, bytes memory txdata) =
            decodeMessageData(_data);

        if (_verifyTxId && txId != nextTxId++) revert DO_INVALID_TX_ID();

        (bool success,) = isDelegateCall //
            ? target.delegatecall(txdata)
            : target.call{ value: msg.value }(txdata);

        if (!success) revert DO_TARGET_CALL_REVERTED();
        emit MessageInvoked(txId, target, isDelegateCall, bytes4(txdata));
    }
}
