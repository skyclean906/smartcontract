// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;
import "./ERC721Upgradeable.sol";
import "./interface/IERC721LazyMint.sol";
import "./Mint721Validator.sol";
import "./interface/IMETASALTERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract ERC721Lazy is IERC721LazyMint, ERC721Upgradeable, Mint721Validator, OwnableUpgradeable {
    using SafeMathUpgradeable for uint;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.UintToAddressMap;

    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
    bytes4 private constant _INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;

    // tokenId => creators
    mapping(uint256 => address) private creators;
    mapping(uint256 => uint) private royaltyFees;
    address public metasaltToken;
    uint256 public MetasaltTokenCreateRewardValue;

    function __ERC721Lazy_init_unchained(address _metaSaltToken, uint256 _erc20CreateRewardValue) internal initializer {
        metasaltToken = _metaSaltToken;
        MetasaltTokenCreateRewardValue = _erc20CreateRewardValue;
    }

    function setMetaSaltToken(address _metaSaltToken) public onlyOwner{
        metasaltToken = _metaSaltToken;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165Upgradeable, ERC165Upgradeable) returns (bool) {
        return interfaceId == LibERC721LazyMint._INTERFACE_ID_MINT_AND_TRANSFER
        || interfaceId == _INTERFACE_ID_ERC165
        || interfaceId == _INTERFACE_ID_ERC721
        || interfaceId == _INTERFACE_ID_ERC721_METADATA
        || interfaceId == _INTERFACE_ID_ERC721_ENUMERABLE;
    }

    function transferFromOrMint(
        LibERC721LazyMint.Mint721Data memory data,
        address from,
        address to
    ) override external {
        if (_exists(data.tokenId)) {
            safeTransferFrom(from, to, data.tokenId);
        } else {
            mintAndTransfer(data, to);
        }
    }

    function mintAndTransfer(LibERC721LazyMint.Mint721Data memory data, address to) public override virtual {
        address creator = address(uint160(data.tokenId >> 96));

        require(data.creator == creator, "ERC721MetaSalt: tokenId is not correct.");

        address sender = _msgSender();
        require(data.creator == sender || isApprovedForAll(data.creator, sender), "ERC721: transfer caller is not owner nor approved");

        bytes32 hash = LibERC721LazyMint.hash(data);
        if (data.creator != sender) {
            validate(data.creator, hash, data.signature);
        }

        _safeMint(to, data.tokenId);        
        _saveCreator(data.tokenId, data.creator);
        _saveRoyaltyFee(data.tokenId, data.royaltyFee);
        _setTokenURI(data.tokenId, data.tokenURI);        
        IMETASALTERC20(metasaltToken).increaseRewardERC721(data.creator, MetasaltTokenCreateRewardValue);
        emit Creator(data.tokenId, data.creator, data.royaltyFee);
    }

    function _mint(address to, uint256 tokenId) internal virtual override {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_burned(tokenId), "token already burned");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        address minter = address(uint160(tokenId >> 96));
        if (minter != to) {
            emit Transfer(address(0), minter, tokenId);
            emit Transfer(minter, to, tokenId);
        } else {
            emit Transfer(address(0), to, tokenId);
        }
    }

    function _saveCreator(uint tokenId, address _creator) internal {        
        require(_creator != address(0x0), "Account should be present");
        creators[tokenId] = _creator;        
    }

    function getCreator(uint256 _id) external view returns (address) {
        return creators[_id];
    }

    function _saveRoyaltyFee(uint tokenId, uint _royaltyFee) internal {                
        royaltyFees[tokenId] = _royaltyFee;        
    }

    function getRoyaltyFee(uint256 _id) external view returns (uint) {
        return royaltyFees[_id];
    }

    function encode(LibERC721LazyMint.Mint721Data memory data)
        external
        view
        returns (bytes memory)
    {
        return abi.encode(address(this), data);
    }
        
    uint256[50] private __gap;
}
