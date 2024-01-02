// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../src/AirDrop.sol";

contract Shares is Initializable, Ownable, ReentrancyGuard, ERC721, AirDrop{
     // total supply
    uint256 private _supply;
    // current tokenId
    uint256 private _tokenId; 

    string private _proxiedName;
    string private _proxiedSymbol;

    string private _baseUri;

    bool public allowRescueFund = true; 

    // === FT Model ====
    address public protocolFeeDestination;
    // pay for platform = 5%
    uint256 public protocolFeePercent = 50_000_000_000_000_000;
    address public sharesSubject;
    // pay for subject = 5%
    uint256 public subjectFeePercent = 50_000_000_000_000_000;
    uint256 public curveBase;

    event Trade(address trader, string symbol, address subject, bool isBuy, uint256 shareAmount, uint256 ethAmount, uint256 protocolEthAmount, uint256 subjectEthAmount, uint256 supply);

    constructor(address _owner, string memory _name, string memory _symbol) Ownable(_owner) ERC721(_name, _symbol) {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol,
        string memory _uri,
        address _sharesSubject,
        address _protocolFeeDestination,
        uint256 _curveBase
    ) public initializer {
        _proxiedName = _name;
        _proxiedSymbol = _symbol;
        _baseUri = _uri;

        sharesSubject = _sharesSubject;
        protocolFeeDestination = _protocolFeeDestination;
        curveBase = _curveBase;

        super._transferOwnership(_owner);
    }

    /**
    * @dev Set ShareNFT URI
    */
    function setTokenURI(
        string memory _uri
    ) public onlyOwner{
        _baseUri = _uri;
    }

    /**
    * @dev Set subject address
    */
    function setSharesSubject(
        address _sharesSubject
    ) public onlyOwner{
        sharesSubject = _sharesSubject;
    }

    /**
    * @dev not allow to rescue fund
    */
    function renounceRescueFund() public onlyOwner {
        allowRescueFund = false;
    }
    /**
    * @dev Set address to store protocol fee
    */
    function setFeeDestination(address _feeDestination) public onlyOwner {
        protocolFeeDestination = _feeDestination;
    }

    /**
    * @dev Set protocol fee percent
    */
    function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
        protocolFeePercent = _feePercent;
    }

    /**
    * @dev Set subject fee percent
    */
    function setSubjectFeePercent(uint256 _feePercent) public onlyOwner {
        subjectFeePercent = _feePercent;
    }

    /**
    * @dev Calculate price with supply 
    */
    function getPrice(uint256 supply) public view returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1) * (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 ? 0 : (supply) * (supply + 1) * (2 * (supply) + 1) / 6;

        uint256 summation = sum2 - sum1;
        return summation * 1 ether / curveBase;
    }

    /**
    * @dev Calculate buy price
    */
    function getBuyPrice() public view returns (uint256) {
        return getPrice(_supply);
    }

    /**
    * @dev Calculate sell price
    */
    function getSellPrice() public view returns (uint256) {
        return getPrice(_supply - 1);
    }

    /**
    * @dev calculate buy price with protocol fee and subject fee
    */
    function getBuyPriceAfterFee() public view returns (uint256) {
        uint256 price = getBuyPrice();
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        return price + protocolFee + subjectFee;
    }

    /**
    * @dev Calculate sell price with protocol fee and subject fee
    */
    function getSellPriceAfterFee() public view returns (uint256) {
        uint256 price = getSellPrice();
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        return price - protocolFee - subjectFee;
    }
    
    /**
    * @dev users buy share from contract
    */
    function mintShare() public payable nonReentrant { 
        // user only can mint one share in one transaction
        uint256 amount = 1;
        uint256 supply = _supply; 
        require(supply > 0 || super.owner() == msg.sender || sharesSubject == msg.sender, 
                "Only the owner/sponsor can buy the first share");
        uint256 price = getPrice(supply);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;
        require(msg.value >= price + protocolFee + subjectFee, "Insufficient payment");
        
        super._safeMint(msg.sender, _tokenId); // update balance automaticly
        _supply++;
        _tokenId++;

        emit Trade(msg.sender, _proxiedSymbol, sharesSubject, true, amount, price, protocolFee, subjectFee, supply + amount);
        (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success2, ) = sharesSubject.call{value: subjectFee}("");
        require(success1 && success2, "Unable to send funds");
    }
    
    /**
    * @dev Sell Share to contract
    */
    function burnShare(uint256 tokenId) public payable nonReentrant {
        uint256 amount = 1;
        uint256 supply = _supply;
        require(supply > amount, "Cannot sell the last share");
        uint256 price = getPrice(supply - 1);
        uint256 protocolFee = price * protocolFeePercent / 1 ether;
        uint256 subjectFee = price * subjectFeePercent / 1 ether;

        require(super.ownerOf(tokenId) == msg.sender, "Not holder");
        require(super.balanceOf(msg.sender) >= amount, "Insufficient shares");

        super._burn(tokenId);
        _supply = supply - 1;

        emit Trade(msg.sender, _proxiedSymbol, sharesSubject, false, amount, price, protocolFee, subjectFee, supply - amount);
        (bool success1, ) = msg.sender.call{value: price - protocolFee - subjectFee}("");
        (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success3, ) = sharesSubject.call{value: subjectFee}("");
        require(success1 && success2 && success3, "Unable to send funds");
    }
    

    /**
     * @dev All tokens share the same URI
     */
    function tokenURI(uint256 tokenId) public override view returns (string memory) {
        return _baseUri;
    }

    /**
     * @dev Get token name
     */
    function name() public view virtual override returns (string memory) {
        if (bytes(_proxiedName).length > 0) {
            return _proxiedName;
        }
        return super.name();
    }

    /**
     * @dev Get token symbol 
     */
    function symbol() public view virtual override returns (string memory) {
        if (bytes(_proxiedSymbol).length > 0) {
            return _proxiedSymbol;
        }
        return super.symbol();
    }


    /**
     * @dev Total supply of NFT
     */
    function totalSupply() public view returns (uint256) {
        return _supply;
    }

    /**
     * @dev latest tokenId of NFT
     */
    function currTokenId() public view returns (uint256) {
        return _tokenId;
    }


    /**
     * @dev Rescure fund of mistake deposit 
     */
    function rescueFund(address _recipient, address _tokenAddr, uint256 _tokenAmount) external onlyOwner{
        require(allowRescueFund == true, "Not allow for rescure fund");
        if (_tokenAmount > 0) {
            if (_tokenAddr == address(0)) {
                payable(_recipient).call{value: _tokenAmount}("");
            } else {
                IERC20(_tokenAddr).transfer(_recipient, _tokenAmount);
            }
        }
    }

    
}