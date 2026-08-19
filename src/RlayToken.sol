// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Token basma yetkisinin güncel yöneticiyi izlemesi için gereken arayüz
interface IRlayYetkilendirme {
    function yonetimDurumu() external view returns (address yoneticiAdresi, address[6] memory konseyAdresleri);
}

/// @title Relay topluluklarında kullanılacak sade ERC-20 tokenı
/// @notice Standart transfer fonksiyonları bütün EVM cüzdanlarıyla uyumludur.
/// Yeni RLAY yalnızca Yetkilendirme sözleşmesindeki güncel yönetici tarafından basılır.
contract RlayToken {
    string public constant name = "Relay Token";
    string public constant symbol = "RLAY";
    uint8 public constant decimals = 18;
    uint256 public constant MAKSIMUM_ARZ = 100_000_000 ether;

    IRlayYetkilendirme public immutable yetkilendirme;
    uint256 public totalSupply;

    mapping(address hesap => uint256 miktar) public balanceOf;
    mapping(address sahip => mapping(address harcayan => uint256 miktar)) public allowance;

    error SifirAdresKullanilamaz();
    error SadeceYonetici();
    error YetersizBakiye();
    error YetersizHarcamaIzni();
    error MaksimumArzAsildi();

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(address yetkilendirmeAdresi) {
        if (yetkilendirmeAdresi == address(0)) revert SifirAdresKullanilamaz();
        yetkilendirme = IRlayYetkilendirme(yetkilendirmeAdresi);
    }

    /// @notice Güncel yönetici belirtilen cüzdana yeni RLAY basar
    function tokenBas(address alici, uint256 miktar) external {
        (address yonetici,) = yetkilendirme.yonetimDurumu();
        if (msg.sender != yonetici) revert SadeceYonetici();
        if (alici == address(0)) revert SifirAdresKullanilamaz();
        if (totalSupply + miktar > MAKSIMUM_ARZ) revert MaksimumArzAsildi();

        totalSupply += miktar;
        balanceOf[alici] += miktar;
        emit Transfer(address(0), alici, miktar);
    }

    function transfer(address alici, uint256 miktar) external returns (bool) {
        _transfer(msg.sender, alici, miktar);
        return true;
    }

    function approve(address harcayan, uint256 miktar) external returns (bool) {
        if (harcayan == address(0)) revert SifirAdresKullanilamaz();
        allowance[msg.sender][harcayan] = miktar;
        emit Approval(msg.sender, harcayan, miktar);
        return true;
    }

    function transferFrom(address gonderen, address alici, uint256 miktar) external returns (bool) {
        uint256 izin = allowance[gonderen][msg.sender];
        if (izin < miktar) revert YetersizHarcamaIzni();
        allowance[gonderen][msg.sender] = izin - miktar;
        emit Approval(gonderen, msg.sender, izin - miktar);
        _transfer(gonderen, alici, miktar);
        return true;
    }

    function _transfer(address gonderen, address alici, uint256 miktar) private {
        if (alici == address(0)) revert SifirAdresKullanilamaz();
        uint256 bakiye = balanceOf[gonderen];
        if (bakiye < miktar) revert YetersizBakiye();

        balanceOf[gonderen] = bakiye - miktar;
        balanceOf[alici] += miktar;
        emit Transfer(gonderen, alici, miktar);
    }
}
