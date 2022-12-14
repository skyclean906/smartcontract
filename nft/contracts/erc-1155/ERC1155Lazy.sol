// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./ERC1155Upgradeable.sol";
import "../interface/IERC1155LazyMint.sol";
import "./Mint1155Validator.sol";
import "./ERC1155BaseURI.sol";
import "../interface/IMETASALTERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract ERC1155Lazy is IERC1155LazyMint, ERC1155BaseURI, Mint1155Validator, OwnableUpgradeable {
    using SafeMathUpgradeable for uint;

    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;
    bytes4 private constant _INTERFACE_ID_ERC1155 = 0xd9b67a26;
    bytes4 private constant _INTERFACE_ID_ERC1155_METADATA_URI = 0x0e89341c;
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    
    mapping(uint256 => address) public creators;
    mapping (uint256 => uint256) public royaltyFees;
    mapping(uint => uint) private supply;
    mapping(uint => uint) private minted;
    address public metasaltToken;
    uint256 public MetasaltTokenCreateRewardValue;

    function __ERC1155Lazy_init_unchained(address _metaSaltToken, uint256 _erc20CreateRewardValue) internal initializer {
        metasaltToken = _metaSaltToken;
        MetasaltTokenCreateRewardValue = _erc20CreateRewardValue;
    }

    function setMetaSaltToken(address _metaSaltToken) public onlyOwner{
        metasaltToken = _metaSaltToken;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165Upgradeable, ERC165Upgradeable) returns (bool) {
        return interfaceId == LibERC1155LazyMint._INTERFACE_ID_MINT_AND_TRANSFER
        || interfaceId == _INTERFACE_ID_ERC165
        || interfaceId == _INTERFACE_ID_ERC2981
        || interfaceId == _INTERFACE_ID_ERC1155
        || interfaceId == _INTERFACE_ID_ERC1155_METADATA_URI;
    }

    function transferFromOrMint(
        LibERC1155LazyMint.Mint1155Data memory data,
        address from,
        address to,
        uint256 amount
    ) override external {
        uint balance = balanceOf(from, data.tokenId);
        uint left = amount;
        if (balance != 0) {
            uint transfer = amount;
            if (balance < amount) {
                transfer = balance;
            }
            safeTransferFrom(from, to, data.tokenId, transfer, "");
            left = amount - transfer;
        }
        if (left > 0) {
            mintAndTransfer(data, to, left);
        }
    }

    function _saveRoyaltyFee(uint tokenId, uint _royaltyFee) internal {                
        royaltyFees[tokenId] = _royaltyFee;        
    }

    function mintAndTransfer(LibERC1155LazyMint.Mint1155Data memory data, address to, uint256 _amount) public override virtual {
        address minter = address(data.tokenId >> 96);
        address sender = _msgSender();

        require(minter == sender || isApprovedForAll(minter, sender), "ERC1155: transfer caller is not approved");
        require(_amount > 0, "amount incorrect");

        if (supply[data.tokenId] == 0) {
            require(minter == data.creator, "tokenId incorrect");
            require(data.supply > 0, "supply incorrect");            

            address creator = data.creator;
            if (creator != sender) {
                bytes32 hash = LibERC1155LazyMint.hash(data);
                validate(creator, hash, data.signature);
            }

            _saveSupply(data.tokenId, data.supply);
            _saveRoyaltyFee(data.tokenId, data.royaltyFee);
            _saveCreator(data.tokenId, data.creator);
            _setTokenURI(data.tokenId, data.tokenURI);
            IMETASALTERC20(metasaltToken).increaseRewardERC1155(data.creator, MetasaltTokenCreateRewardValue);
        }

        _mint(to, data.tokenId, _amount, "");
        if (minter != to) {
            emit TransferSingle(sender, address(0), minter, data.tokenId, _amount);
            emit TransferSingle(sender, minter, to, data.tokenId, _amount);
        } else {
            emit TransferSingle(sender, address(0), to, data.tokenId, _amount);
        }
    }

    function _mint(address account, uint256 id, uint256 amount, bytes memory data) internal virtual override {
        uint newMinted = amount.add(minted[id]);
        require(newMinted <= supply[id], "more than supply");
        minted[id] = newMinted;

        require(account != address(0), "ERC1155: mint to the zero address");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), account, _asSingletonArray(id), _asSingletonArray(amount), data);

        _balances[id][account] = _balances[id][account].add(amount);

        _doSafeTransferAcceptanceCheck(operator, address(0), account, id, amount, data);
    }

    function _saveSupply(uint tokenId, uint _supply) internal {
        require(supply[tokenId] == 0);
        supply[tokenId] = _supply;
        emit Supply(tokenId, _supply);
    }

    function _saveCreator(uint tokenId, address _creator) internal {
        require(_creator != address(0x0), "Account should be present");                
        emit Creator(tokenId, _creator);
    }

    function getCreator(uint256 _id) external view returns (address) {
        return creators[_id];
    }

    function _addMinted(uint256 tokenId, uint amount) internal {
        minted[tokenId] += amount;
    }

    function _getMinted(uint256 tokenId) internal view returns (uint) {
        return minted[tokenId];
    }

    function _getSupply(uint256 tokenId) internal view returns (uint) {
        return supply[tokenId];
    }

    uint256[50] private __gap;
}
