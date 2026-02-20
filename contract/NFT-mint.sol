// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Custom errors for gas efficiency
error UsernameAlreadyUsed();
error UsernameDoesNotExist();
error InvalidMintCost();
error InvalidSalePrice();
error TokenDoesNotExist();
error NotTokenOwner();
error NFTNotForSale();
error CannotBuyOwnNFT();
error InvalidTokenAddress();

/// @title UsernameNFT — ERC721 Username NFT with built-in marketplace
/// @author CAW Team
/// @notice Allows users to mint unique username NFTs paid with CAW tokens and trade them on-chain
contract UsernameNFT is ERC721, Ownable, ReentrancyGuard {
    struct NFTMetadata {
        uint256 tokenId;
        string username;
        uint256 salePrice;
        string metadataURI;
    }

    mapping(string => address) private usernameToOwner;
    mapping(uint256 => string) private tokenIdToUsername;
    mapping(string => NFTMetadata) private nftMetadata;
    
    /// @notice The CAW ERC20 token used for payments
    IERC20 public immutable cwnToken; // solhint-disable-line immutable-vars-naming
    /// @notice Base cost to mint a new username NFT
    uint256 public baseMintCost;
    uint256 private nextTokenId;

    /// @notice Emitted when a new username NFT is minted
    /// @param tokenId The ID of the newly minted token
    /// @param owner The address that minted the NFT
    /// @param username The registered username
    /// @param salePrice The initial sale price set by the minter
    event NFTCreated(uint256 indexed tokenId, address indexed owner, string username, uint256 indexed salePrice);
    /// @notice Emitted when an NFT is sold on the marketplace
    /// @param tokenId The ID of the sold token
    /// @param from The seller address
    /// @param to The buyer address
    /// @param price The sale price paid
    event NFTSold(uint256 indexed tokenId, address indexed from, address indexed to, uint256 price);

    constructor(address _cwnTokenAddress) ERC721("CAW", "tCAW") {
        if (_cwnTokenAddress == address(0)) revert InvalidTokenAddress();
        cwnToken = IERC20(_cwnTokenAddress);
        baseMintCost = 0.005 ether;
        nextTokenId = 1;
    }

    /// @notice Updates the mint cost for an existing username NFT (owner only)
    /// @param username The username to update
    /// @param mintCost The new cost in CAW tokens
    function setMintCost(string calldata username, uint256 mintCost) external onlyOwner {
        if (usernameToOwner[username] == address(0)) revert UsernameDoesNotExist();
        if (mintCost == 0) revert InvalidMintCost();
        
        nftMetadata[username].salePrice = mintCost;
    }

    /// @notice Mints a new username NFT. Caller must approve CAW token spending first.
    /// @param username The unique username to register
    /// @param metadataURI The metadata URI for the NFT
    /// @param mintCost The amount of CAW tokens to pay
    function createNFT(string calldata username, string calldata metadataURI, uint256 mintCost) external nonReentrant {
        if (usernameToOwner[username] != address(0)) revert UsernameAlreadyUsed();
        if (mintCost == 0) revert InvalidMintCost();

        usernameToOwner[username] = msg.sender;
        
        uint256 currentTokenId = nextTokenId;
        tokenIdToUsername[currentTokenId] = username;

        nftMetadata[username] = NFTMetadata({
            tokenId: currentTokenId,
            username: username,
            salePrice: mintCost,
            metadataURI: metadataURI
        });

        nextTokenId++;

        // Important: User must call cwnToken.approve(address(this), mintCost) BEFORE calling createNFT
        cwnToken.transferFrom(msg.sender, address(this), mintCost);
        
        _safeMint(msg.sender, currentTokenId);
        
        emit NFTCreated(currentTokenId, msg.sender, username, mintCost);
    }

    /// @notice Checks if a username is available for minting
    /// @param username The username to check
    /// @return True if the username is available
    function checkUsernameAvailability(string calldata username) external view returns (bool) {
        return usernameToOwner[username] == address(0);
    }

    /// @notice Lists an NFT for sale at a specified price
    /// @param tokenId The token ID to list
    /// @param salePrice The sale price in CAW tokens
    function sellNFT(uint256 tokenId, uint256 salePrice) external {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (salePrice == 0) revert InvalidSalePrice();

        string memory username = tokenIdToUsername[tokenId];
        nftMetadata[username].salePrice = salePrice;
    }

    /// @notice Buys an NFT listed for sale. Caller must approve CAW token spending first.
    /// @param tokenId The token ID to buy
    function buyNFT(uint256 tokenId) external nonReentrant {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        
        string memory username = tokenIdToUsername[tokenId];
        uint256 salePrice = nftMetadata[username].salePrice;
        
        if (salePrice == 0) revert NFTNotForSale();

        address seller = ownerOf(tokenId);
        if (seller == msg.sender) revert CannotBuyOwnNFT();

        // Checks-Effects-Interactions Pattern
        // 1. Effect: Reset sale price before transfer
        nftMetadata[username].salePrice = 0;

        // 2. Interaction: Transfer tokens
        cwnToken.transferFrom(msg.sender, seller, salePrice);
        
        // 3. Interaction: Transfer NFT
        _safeTransfer(seller, msg.sender, tokenId, "");
        
        emit NFTSold(tokenId, seller, msg.sender, salePrice);
    }

    /// @notice Returns metadata for all minted NFTs
    /// @return Array of NFTMetadata structs
    function getAllNFTs() external view returns (NFTMetadata[] memory) {
        uint256 totalNFTs = nextTokenId - 1;
        NFTMetadata[] memory allMetadata = new NFTMetadata[](totalNFTs);
        
        // solhint-disable-next-line gas-strict-inequalities
        for (uint256 i = 1; i <= totalNFTs; i++) {
            string memory username = tokenIdToUsername[i];
            allMetadata[i - 1] = nftMetadata[username];
        }
        
        return allMetadata;
    }
    
    /// @notice Returns the metadata URI for a given token
    /// @param tokenId The token ID to query
    /// @return The metadata URI string
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        string memory username = tokenIdToUsername[tokenId];
        return nftMetadata[username].metadataURI;
    }

    /// @notice Returns the username associated with a token ID
    /// @param tokenId The token ID to query
    /// @return The username string
    function getUsername(uint256 tokenId) public view returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        return tokenIdToUsername[tokenId];
    }

    /// @notice Returns the current mint/sale cost for a username
    /// @param username The username to query
    /// @return The cost in CAW tokens
    function getMintCost(string calldata username) external view returns (uint256) {
        if (usernameToOwner[username] == address(0)) revert UsernameDoesNotExist();
        return nftMetadata[username].salePrice;
    }

    /// @notice Returns the current sale price for a username
    /// @param username The username to query
    /// @return The sale price in CAW tokens
    function getSalePrice(string calldata username) external view returns (uint256) {
        if (usernameToOwner[username] == address(0)) revert UsernameDoesNotExist();
        return nftMetadata[username].salePrice;
    }

    /// @notice Returns the profile image URI for a token
    /// @param tokenId The token ID to query
    /// @return The metadata URI string
    function getProfileImageURI(uint256 tokenId) external view returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        string memory username = tokenIdToUsername[tokenId];
        return nftMetadata[username].metadataURI;
    }
}
