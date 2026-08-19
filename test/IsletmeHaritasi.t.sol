// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IsletmeHaritasi} from "../src/IsletmeHaritasi.sol";
import {Yetkilendirme} from "../src/Yetkilendirme.sol";

interface VmHarita {
    function prank(address gonderen) external;
    function expectRevert(bytes4 hata) external;
}

contract IsletmeHaritasiTest {
    VmHarita private constant vm = VmHarita(address(uint160(uint256(keccak256("hevm cheat code")))));

    address private constant YONETICI = address(0x100);
    address private constant UYE_1 = address(0x101);
    address private constant UYE_2 = address(0x102);
    address private constant UYE_3 = address(0x103);
    address private constant UYE_4 = address(0x104);
    address private constant UYE_5 = address(0x105);
    address private constant UYE_6 = address(0x106);
    address private constant YENI_YONETICI = address(0x200);
    address private constant ISLETME = address(0x300);
    address private constant YETKISIZ = address(0x999);

    bytes32 private constant NFC_1 = keccak256("relay-nfc-isletme-1");

    Yetkilendirme private yetkilendirme;
    IsletmeHaritasi private harita;

    function setUp() public {
        yetkilendirme = new Yetkilendirme(YONETICI, UYE_1, UYE_2, UYE_3, UYE_4, UYE_5, UYE_6);
        harita = new IsletmeHaritasi(address(yetkilendirme));
    }

    function testBasvuruOnaydanOnceHaritadaGorunmez() public {
        uint256 id = _basvuruYap();

        require(id == 1);
        require(harita.isletmeSayisi() == 1);
        require(harita.aktifIsletmeSayisi() == 0);
        IsletmeHaritasi.Isletme memory isletme = harita.isletmeBilgisi(id);
        require(isletme.odemeAdresi == ISLETME);
        require(!isletme.onayli);
        require(!isletme.aktif);
    }

    function testYoneticiOnaylayincaHaritadaGorunur() public {
        uint256 id = _basvuruYap();
        vm.prank(YONETICI);
        harita.isletmeOnayla(id);

        require(harita.aktifIsletmeSayisi() == 1);
        (uint256 okunanId, address odemeAdresi, string memory ad,, int32 enlemE6, int32 boylamE6, bytes32 nfc) =
            harita.aktifIsletme(0);
        require(okunanId == id);
        require(odemeAdresi == ISLETME);
        require(keccak256(bytes(ad)) == keccak256(bytes("Rlay Kahve")));
        require(enlemE6 == 41_008_900);
        require(boylamE6 == 28_978_500);
        require(nfc == NFC_1);
    }

    function testKonseyUyesiIsletmeOnaylayamaz() public {
        uint256 id = _basvuruYap();
        vm.prank(UYE_1);
        vm.expectRevert(IsletmeHaritasi.SadeceYonetici.selector);
        harita.isletmeOnayla(id);
    }

    function testGecersizKoordinatReddedilir() public {
        vm.prank(ISLETME);
        vm.expectRevert(IsletmeHaritasi.GecersizKoordinat.selector);
        harita.isletmeBasvurusuYap("Rlay Kahve", "Kafe", 90_000_001, 28_978_500, NFC_1);
    }

    function testAyniNfcEtiketiIkiKezKaydedilemez() public {
        _basvuruYap();
        vm.prank(YETKISIZ);
        vm.expectRevert(IsletmeHaritasi.NfcEtiketiZatenKayitli.selector);
        harita.isletmeBasvurusuYap("Baska Kafe", "Kafe", 41_010_000, 28_980_000, NFC_1);
    }

    function testKonumDegisinceYenidenYoneticiOnayiGerekir() public {
        uint256 id = _basvuruYap();
        vm.prank(YONETICI);
        harita.isletmeOnayla(id);

        vm.prank(ISLETME);
        harita.konumGuncelle(id, 41_020_000, 28_990_000);

        require(harita.aktifIsletmeSayisi() == 0);
        IsletmeHaritasi.Isletme memory isletme = harita.isletmeBilgisi(id);
        require(!isletme.onayli);

        vm.prank(YONETICI);
        harita.isletmeOnayla(id);
        require(harita.aktifIsletmeSayisi() == 1);
    }

    function testYoneticiIsletmeyiHaritadanKaldiripGeriAlabilir() public {
        uint256 id = _basvuruYap();
        vm.prank(YONETICI);
        harita.isletmeOnayla(id);

        vm.prank(YONETICI);
        harita.isletmeAktifliginiAyarla(id, false);
        require(harita.aktifIsletmeSayisi() == 0);

        vm.prank(YONETICI);
        harita.isletmeAktifliginiAyarla(id, true);
        require(harita.aktifIsletmeSayisi() == 1);
    }

    function testYetkisizAdresIsletmeyiHaritadanKaldiramaz() public {
        uint256 id = _basvuruYap();
        vm.prank(YONETICI);
        harita.isletmeOnayla(id);

        vm.prank(YETKISIZ);
        vm.expectRevert(IsletmeHaritasi.SadeceYonetici.selector);
        harita.isletmeAktifliginiAyarla(id, false);
    }

    function testGuncelYoneticiOnayYetkisiniDevralir() public {
        uint256 id = _basvuruYap();
        _yoneticiOyuVer(UYE_1);
        _yoneticiOyuVer(UYE_2);
        _yoneticiOyuVer(UYE_3);
        _yoneticiOyuVer(UYE_4);

        vm.prank(YONETICI);
        vm.expectRevert(IsletmeHaritasi.SadeceYonetici.selector);
        harita.isletmeOnayla(id);

        vm.prank(YENI_YONETICI);
        harita.isletmeOnayla(id);
        require(harita.aktifIsletmeSayisi() == 1);
    }

    function _basvuruYap() private returns (uint256 id) {
        vm.prank(ISLETME);
        id = harita.isletmeBasvurusuYap("Rlay Kahve", "Kafe", 41_008_900, 28_978_500, NFC_1);
    }

    function _yoneticiOyuVer(address uye) private {
        vm.prank(uye);
        yetkilendirme.yoneticilikIcinOyVer(false, YENI_YONETICI);
    }
}
