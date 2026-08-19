// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Yetkilendirme} from "../src/Yetkilendirme.sol";

interface Vm {
    function prank(address gonderen) external;
    function expectRevert(bytes4 hata) external;
}

contract YetkilendirmeTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address private constant YONETICI = address(0x100);
    address private constant UYE_1 = address(0x101);
    address private constant UYE_2 = address(0x102);
    address private constant UYE_3 = address(0x103);
    address private constant UYE_4 = address(0x104);
    address private constant UYE_5 = address(0x105);
    address private constant UYE_6 = address(0x106);
    address private constant ADAY_1 = address(0x201);
    address private constant ADAY_2 = address(0x202);
    address private constant YENI_UYE = address(0x301);
    address private constant TOPLULUK_UYESI_1 = address(0x401);
    address private constant TOPLULUK_UYESI_2 = address(0x402);
    address private constant YETKISIZ = address(0x999);

    Yetkilendirme private yetkilendirme;

    function setUp() public {
        yetkilendirme = new Yetkilendirme(YONETICI, UYE_1, UYE_2, UYE_3, UYE_4, UYE_5, UYE_6);
    }

    function testKurucuYoneticiVeAdreslerDogruSirada() public view {
        (address yoneticiAdresi, address[6] memory uyeler) = yetkilendirme.yonetimDurumu();

        require(yoneticiAdresi == YONETICI);
        require(uyeler[0] == UYE_1);
        require(uyeler[5] == UYE_6);
        require(yetkilendirme.yetkiliMi(YONETICI));
        require(yetkilendirme.yetkiliMi(UYE_3));
        require(!yetkilendirme.yetkiliMi(ADAY_1));
    }

    function testUcIndirmeOyuYoneticiyiDegistirmez() public {
        _yoneticiOyuVer(UYE_1, false, ADAY_1);
        _yoneticiOyuVer(UYE_2, false, ADAY_1);
        _yoneticiOyuVer(UYE_3, false, ADAY_1);

        (address yoneticiAdresi,) = yetkilendirme.yonetimDurumu();
        require(yoneticiAdresi == YONETICI);
    }

    function testDortIndirmeVeDortAdayOyuYoneticiyiDegistirir() public {
        _yoneticiOyuVer(UYE_1, false, ADAY_1);
        _yoneticiOyuVer(UYE_2, false, ADAY_1);
        _yoneticiOyuVer(UYE_3, false, ADAY_1);
        _yoneticiOyuVer(UYE_4, false, ADAY_1);

        (address yoneticiAdresi,) = yetkilendirme.yonetimDurumu();
        require(yoneticiAdresi == ADAY_1);
        require(yetkilendirme.yetkiliMi(ADAY_1));
        require(!yetkilendirme.yetkiliMi(YONETICI));
    }

    function testYoneticiKalsinDiyenlerinAdayOyuSayilir() public {
        _yoneticiOyuVer(UYE_1, true, ADAY_1);
        _yoneticiOyuVer(UYE_2, true, ADAY_1);
        _yoneticiOyuVer(UYE_3, false, ADAY_1);
        _yoneticiOyuVer(UYE_4, false, ADAY_1);
        _yoneticiOyuVer(UYE_5, false, ADAY_2);
        _yoneticiOyuVer(UYE_6, false, ADAY_2);

        (address yoneticiAdresi,) = yetkilendirme.yonetimDurumu();
        require(yoneticiAdresi == ADAY_1);
    }

    function testDortIndirmeOyuFarkliAdaylaraBolunurseYoneticiKalir() public {
        _yoneticiOyuVer(UYE_1, false, ADAY_1);
        _yoneticiOyuVer(UYE_2, false, ADAY_1);
        _yoneticiOyuVer(UYE_3, false, ADAY_2);
        _yoneticiOyuVer(UYE_4, false, ADAY_2);

        (address yoneticiAdresi,) = yetkilendirme.yonetimDurumu();
        require(yoneticiAdresi == YONETICI);
    }

    function testKonseyUyesiYoneticiOyunuDegistirebilir() public {
        _yoneticiOyuVer(UYE_1, false, ADAY_1);
        _yoneticiOyuVer(UYE_1, true, ADAY_2);
        _yoneticiOyuVer(UYE_2, false, ADAY_1);
        _yoneticiOyuVer(UYE_3, false, ADAY_1);
        _yoneticiOyuVer(UYE_4, false, ADAY_1);

        (address yoneticiAdresi,) = yetkilendirme.yonetimDurumu();
        require(yoneticiAdresi == YONETICI);
    }

    function testAyniYoneticiOyuTekrarKullanilamaz() public {
        _yoneticiOyuVer(UYE_1, false, ADAY_1);

        vm.prank(UYE_1);
        vm.expectRevert(Yetkilendirme.AyniOyTekrarKullanilamaz.selector);
        yetkilendirme.yoneticilikIcinOyVer(false, ADAY_1);
    }

    function testKonseyDisindakiAdresYoneticiOyuKullanamaz() public {
        vm.prank(ADAY_1);
        vm.expectRevert(Yetkilendirme.SadeceKonseyUyesi.selector);
        yetkilendirme.yoneticilikIcinOyVer(false, ADAY_2);
    }

    function testYoneticiVeIkiKonseyUyesiKonseyiDegistirir() public {
        _konseyOyuVer(YONETICI, UYE_6, YENI_UYE);
        _konseyOyuVer(UYE_1, UYE_6, YENI_UYE);

        require(yetkilendirme.yetkiliMi(UYE_6));
        require(!yetkilendirme.yetkiliMi(YENI_UYE));

        _konseyOyuVer(UYE_2, UYE_6, YENI_UYE);

        require(!yetkilendirme.yetkiliMi(UYE_6));
        require(yetkilendirme.yetkiliMi(YENI_UYE));
    }

    function testBesKonseyUyesiYoneticisizKonseyiDegistirir() public {
        _konseyOyuVer(UYE_1, UYE_6, YENI_UYE);
        _konseyOyuVer(UYE_2, UYE_6, YENI_UYE);
        _konseyOyuVer(UYE_3, UYE_6, YENI_UYE);
        _konseyOyuVer(UYE_4, UYE_6, YENI_UYE);

        require(yetkilendirme.yetkiliMi(UYE_6));

        _konseyOyuVer(UYE_5, UYE_6, YENI_UYE);
        require(!yetkilendirme.yetkiliMi(UYE_6));
        require(yetkilendirme.yetkiliMi(YENI_UYE));
    }

    function testKonseyOyuBaskaAdayaTasinabilir() public {
        _konseyOyuVer(YONETICI, UYE_6, YENI_UYE);
        _konseyOyuVer(UYE_1, UYE_6, YENI_UYE);
        _konseyOyuVer(UYE_2, UYE_6, ADAY_1);

        _konseyOyuVer(UYE_2, UYE_6, YENI_UYE);
        require(yetkilendirme.yetkiliMi(YENI_UYE));
    }

    function testEskiUyeDegisikliktenSonraOyKullanamaz() public {
        _konseyOyuVer(YONETICI, UYE_6, YENI_UYE);
        _konseyOyuVer(UYE_1, UYE_6, YENI_UYE);
        _konseyOyuVer(UYE_2, UYE_6, YENI_UYE);

        vm.prank(UYE_6);
        vm.expectRevert(Yetkilendirme.SadeceKonseyUyesi.selector);
        yetkilendirme.yoneticilikIcinOyVer(false, ADAY_1);

        _yoneticiOyuVer(YENI_UYE, false, ADAY_1);
    }

    function testKurulumdaAyniKonseyAdresiReddedilir() public {
        vm.expectRevert(Yetkilendirme.AdresZatenKonseyUyesi.selector);
        new Yetkilendirme(YONETICI, UYE_1, UYE_1, UYE_3, UYE_4, UYE_5, UYE_6);
    }

    function testYoneticiToplulukUyesiEklerVeIzBirakir() public {
        vm.prank(YONETICI);
        yetkilendirme.toplulukUyesiEkle(TOPLULUK_UYESI_1);

        require(yetkilendirme.toplulukUyesiSayisi() == 1);

        (address uye, address ekleyen) = yetkilendirme.toplulukUyesi(0);
        require(uye == TOPLULUK_UYESI_1);
        require(ekleyen == YONETICI);

        (bool aktif, address kayitliEkleyen) = yetkilendirme.toplulukUyesiBilgisi(TOPLULUK_UYESI_1);
        require(aktif);
        require(kayitliEkleyen == YONETICI);
    }

    function testKonseyUyesiToplulukUyesiEkleyebilir() public {
        vm.prank(UYE_3);
        yetkilendirme.toplulukUyesiEkle(TOPLULUK_UYESI_1);

        (, address ekleyen) = yetkilendirme.toplulukUyesi(0);
        require(ekleyen == UYE_3);
    }

    function testYetkisizAdresToplulukUyesiEkleyemez() public {
        vm.prank(YETKISIZ);
        vm.expectRevert(Yetkilendirme.SadeceYoneticiVeyaKonseyUyesi.selector);
        yetkilendirme.toplulukUyesiEkle(TOPLULUK_UYESI_1);
    }

    function testKonseyUyesiToplulukUyesiCikarabilirVeIzKalir() public {
        vm.prank(YONETICI);
        yetkilendirme.toplulukUyesiEkle(TOPLULUK_UYESI_1);

        vm.prank(UYE_2);
        yetkilendirme.toplulukUyesiCikar(TOPLULUK_UYESI_1);

        require(yetkilendirme.toplulukUyesiSayisi() == 0);

        (bool aktif, address ekleyen) = yetkilendirme.toplulukUyesiBilgisi(TOPLULUK_UYESI_1);
        require(!aktif);
        require(ekleyen == YONETICI);
    }

    function testUyeCikarilirkenAktifListeBoslukBirakmaz() public {
        vm.prank(YONETICI);
        yetkilendirme.toplulukUyesiEkle(TOPLULUK_UYESI_1);

        vm.prank(UYE_1);
        yetkilendirme.toplulukUyesiEkle(TOPLULUK_UYESI_2);

        vm.prank(UYE_4);
        yetkilendirme.toplulukUyesiCikar(TOPLULUK_UYESI_1);

        require(yetkilendirme.toplulukUyesiSayisi() == 1);
        (address kalanUye, address ekleyen) = yetkilendirme.toplulukUyesi(0);
        require(kalanUye == TOPLULUK_UYESI_2);
        require(ekleyen == UYE_1);
    }

    function testAyniToplulukUyesiIkiKezEklenemez() public {
        vm.prank(YONETICI);
        yetkilendirme.toplulukUyesiEkle(TOPLULUK_UYESI_1);

        vm.prank(UYE_1);
        vm.expectRevert(Yetkilendirme.ToplulukUyesiZatenVar.selector);
        yetkilendirme.toplulukUyesiEkle(TOPLULUK_UYESI_1);
    }

    function _yoneticiOyuVer(address uye, bool yoneticiDursunMu, address aday) private {
        vm.prank(uye);
        yetkilendirme.yoneticilikIcinOyVer(yoneticiDursunMu, aday);
    }

    function _konseyOyuVer(address oyVeren, address gidecekUye, address gelecekUye) private {
        vm.prank(oyVeren);
        yetkilendirme.konseyDegisikligiIcinOyVer(gidecekUye, gelecekUye);
    }
}
