// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract DecaNFT is ERC721Upgradeable, OwnableUpgradeable, UUPSUpgradeable, ERC2981Upgradeable {
    using Strings for uint256;

    address public treasuryAddress;
    bytes32 private merkleRoot;

    string public baseTokenURI;
    string public prerevealTokenURI;

    bool public revealed;
    bool public paused;
    bool public whiteListingPeriod;
    bool public mintState;

    uint256 public startTokenId;
    uint256 public mintLimit;
    uint256 public mintPrice;
    uint256 public totalSupply;
    uint256 public constant MAX_ELEMENTS = 2024;
    uint256 public treasuryMintedCount;
    uint256 private constant MAX_TREASURY_MINT_LIMIT = 100;

    event TreasuryMint(
        address indexed recipient,
        uint256 quantity
    );

    event Mint(
        address indexed recipient,
        uint256 quantity,
        uint256 fromIndex
    );

    event MintStateChanged(
        bool state
    );

    function initialize(string memory baseURI, string memory _name, string memory _symbol) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init();
        __UUPSUpgradeable_init();
        setBaseURI(baseURI);
    }

    function _authorizeUpgrade(address) internal override onlyOwner{
    }

    //Base URI for all tokens
    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (revealed == false) {
            return prerevealTokenURI;
        }
        return super.tokenURI(tokenId);
    }

    // Pre-revealing image URI for all NFTs
    function setPrerevealTokenURI(string memory prerevealURI) public onlyOwner {
        prerevealTokenURI = prerevealURI;
    }

    // Toggle for showing default Image or individual images.
    function setRevealed(bool _revealed) public onlyOwner {
        revealed = _revealed;
    }

    // Set limit for NFT batch minting
    function setMintLimit(uint256 _mintLimit) external onlyOwner {
        mintLimit = _mintLimit;
    }

    // Set NFT mint availability
    function setMintState(bool _mintState) external onlyOwner {
        mintState = _mintState;
        emit MintStateChanged(mintState);
    }

    //Sets minimum minting price for one NFT
    function setMintPrice(uint _price) external onlyOwner {
        mintPrice = _price;
    }

    //Sets starting tokenId for this chain
    function setStartTokenId(uint _startTokenId) external onlyOwner {
        startTokenId = _startTokenId;
    }
    
    //Setting WhiteListing Round
    function enableWhiteListing(bool _whiteListingPeriod) external onlyOwner {
        whiteListingPeriod = _whiteListingPeriod;
    }

    // Users can mint NFTs calling this function
    // Mint multiple NFTs at once with merkle proof
    // Merkle proof can be unnecessary if not whitelisting period.
    function mintNFT(uint256 _quantity, bytes32[] memory proof) public payable {
        uint256 supply = totalSupply;
        address _sender = msg.sender;
        require(msg.sender == owner() || msg.value >= mintPrice * _quantity, "Must send required eth to mint.");
        require(_quantity > 0, "Quantity cannot be zero.");
        require(mintState, "Mint is not available.");
        require(!paused, "Contract is paused.");
        require(supply + _quantity <= MAX_ELEMENTS, "Reached max total supply.");
        require(mintLimit == 0 || _quantity <= mintLimit, "Mint limit exceeded.");

        if (whiteListingPeriod) {
            require(validateAddress(proof, msg.sender) == true, "Invalid minter.");
        }

        for (uint256 i = 1; i <= _quantity; i++) {
            _safeMint(_sender, startTokenId + supply + i);
        }
        totalSupply += _quantity;
        emit Mint(_sender, _quantity, supply);

        (bool success, ) = payable(treasuryAddress).call{value: msg.value}("");
        require(success);
    }

    // Set address for treasury wallet
    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    // Mint certain number of NFTs to a treasury wallet
    function treasuryMint(uint256 _quantity) external onlyOwner {
        require(treasuryAddress != address(0), 'Treasury Address should be set up.');
        
        uint256 supply = totalSupply;
        require(_quantity > 0, "Quantity cannot be zero.");
        require(supply + _quantity <= MAX_ELEMENTS, "Reached max total supply.");
        require(treasuryMintedCount + _quantity <= MAX_TREASURY_MINT_LIMIT, "Reached treasury mint limit.");
        require(mintLimit == 0 || _quantity <= mintLimit, "Mint limit exceeded.");
        for (uint256 i = 1; i <= _quantity; i++) {
            _safeMint(treasuryAddress, startTokenId + supply + i);
        }
        totalSupply += _quantity;
        emit Mint(treasuryAddress, _quantity, supply);
        treasuryMintedCount += _quantity;
    }

    // ERC2981 Royalty START
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721Upgradeable, ERC2981Upgradeable) returns (bool) {
        // Supports the following `interfaceId`s:
        // - IERC165: 0x01ffc9a7
        // - IERC721: 0x80ac58cd
        // - IERC721Metadata: 0x5b5e139f
        // - IERC2981: 0x2a55205a
        return
        ERC721Upgradeable.supportsInterface(interfaceId) ||
        ERC2981Upgradeable.supportsInterface(interfaceId);
    }

    //Sets default royalty percent and address
    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }
    // ERC2981 Royalty END

    //Extracts token ids owned by certain address
    function walletOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        uint256[] memory tokensId = new uint256[](tokenCount);

        if(tokenCount == 0){
            return tokensId;
        }

        uint256 key = 0;
        for (uint256 i = 1; i <= MAX_ELEMENTS; i++) {
            if(_exists(i) && ownerOf(i) == _owner){
                tokensId[key] = i;
                key++;
                if(key == tokenCount){break;}
            }
        }

        return tokensId;
    }

    function pause() external onlyOwner{
        paused = true;
    }
    
    function unpause() external onlyOwner{
        paused = false;
    }
    
    function setMerkleRoot(bytes32 newRoot) public onlyOwner() returns (bytes32) {
        merkleRoot = newRoot;
        return merkleRoot;
    }

    function validateAddress(
        bytes32[] memory _merkleProof,
        address addr
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(addr));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }
}