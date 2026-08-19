// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Mevcut işletme haritasından yalnızca kimlik doğrulaması için gereken görünüm
interface IIsletmeHaritasiKimlik {
    struct Isletme {
        address odemeAdresi;
        string ad;
        string kategori;
        int32 enlemE6;
        int32 boylamE6;
        bytes32 kayitKimligi;
        bool onayli;
        bool aktif;
    }

    function isletmeBilgisi(uint256 id) external view returns (Isletme memory);
}

/// @title Relay doğrulanmış işletme kimliği
/// @notice Yönetici onaylı aktif işletmenin kendi cüzdanına aldığı, devredilemez
/// ERC-721 kimliğidir. NFT tek başına yeterli değildir: ödeme yetkisi kontrolü
/// sırasında işletmenin haritada hâlâ aktif olduğu da yeniden okunur.
contract IsletmeKimligi {
    string public constant name = "Relay Verified Merchant";
    string public constant symbol = "RVM";

    IIsletmeHaritasiKimlik public immutable isletmeHaritasi;

    mapping(uint256 tokenId => address sahip) private _sahipler;
    mapping(address sahip => uint256 adet) public balanceOf;
    mapping(address isletme => uint256 tokenId) public isletmeKimligi;

    error SifirAdresKullanilamaz();
    error IsletmeOnayliVeAktifDegil();
    error SadeceIsletmeSahibi();
    error KimlikZatenAlinmis();
    error KimlikBulunamadi();
    error IsletmeKimligiDevredilemez();

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    constructor(address isletmeHaritasiAdresi) {
        if (isletmeHaritasiAdresi == address(0)) revert SifirAdresKullanilamaz();
        isletmeHaritasi = IIsletmeHaritasiKimlik(isletmeHaritasiAdresi);
    }

    /// @notice İşletme, haritadaki işletme kimliğini token kimliği olarak alır.
    function kimlikAl(uint256 isletmeId) external {
        IIsletmeHaritasiKimlik.Isletme memory isletme = isletmeHaritasi.isletmeBilgisi(isletmeId);
        if (msg.sender != isletme.odemeAdresi) revert SadeceIsletmeSahibi();
        if (!isletme.onayli || !isletme.aktif) revert IsletmeOnayliVeAktifDegil();
        if (_sahipler[isletmeId] != address(0) || isletmeKimligi[msg.sender] != 0) revert KimlikZatenAlinmis();

        _sahipler[isletmeId] = msg.sender;
        balanceOf[msg.sender] = 1;
        isletmeKimligi[msg.sender] = isletmeId;
        emit Transfer(address(0), msg.sender, isletmeId);
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address sahip = _sahipler[tokenId];
        if (sahip == address(0)) revert KimlikBulunamadi();
        return sahip;
    }

    /// @notice Ödeme isteği oluşturulurken kullanılacak güncel yetki kontrolü.
    function dogrulanmisIsletmeMi(address hesap) external view returns (bool) {
        uint256 isletmeId = isletmeKimligi[hesap];
        if (isletmeId == 0 || _sahipler[isletmeId] != hesap) return false;

        try isletmeHaritasi.isletmeBilgisi(isletmeId) returns (IIsletmeHaritasiKimlik.Isletme memory isletme) {
            return isletme.odemeAdresi == hesap && isletme.onayli && isletme.aktif;
        } catch {
            return false;
        }
    }

    /// @notice Cüzdanların NFT standardını tanıması için ERC-165 / ERC-721 kimlikleri
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == 0x80ac58cd;
    }

    // Kimlik satılamaz veya başka cüzdana aktarılamaz.
    function approve(address, uint256) external pure { revert IsletmeKimligiDevredilemez(); }
    function setApprovalForAll(address, bool) external pure { revert IsletmeKimligiDevredilemez(); }
    function transferFrom(address, address, uint256) external pure { revert IsletmeKimligiDevredilemez(); }
    function safeTransferFrom(address, address, uint256) external pure { revert IsletmeKimligiDevredilemez(); }
    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert IsletmeKimligiDevredilemez();
    }
    function getApproved(uint256 tokenId) external view returns (address) {
        ownerOf(tokenId);
        return address(0);
    }
    function isApprovedForAll(address, address) external pure returns (bool) { return false; }
}
