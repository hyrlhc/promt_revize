// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IsletmeHaritasi} from "../src/IsletmeHaritasi.sol";
import {IsletmeKimligi} from "../src/IsletmeKimligi.sol";
import {Yetkilendirme} from "../src/Yetkilendirme.sol";

interface VmKimlik {
    function prank(address gonderen) external;
    function expectRevert(bytes4 hata) external;
}

contract IsletmeKimligiTest {
    VmKimlik private constant vm = VmKimlik(address(uint160(uint256(keccak256("hevm cheat code")))));

    address private constant YONETICI = address(0x100);
    address private constant ISLETME = address(0x300);
    address private constant YABANCI = address(0x999);

    Yetkilendirme private yetkilendirme;
    IsletmeHaritasi private harita;
    IsletmeKimligi private kimlik;

    function setUp() public {
        yetkilendirme = new Yetkilendirme(
            YONETICI,
            address(0x101),
            address(0x102),
            address(0x103),
            address(0x104),
            address(0x105),
            address(0x106)
        );
        harita = new IsletmeHaritasi(address(yetkilendirme));
        kimlik = new IsletmeKimligi(address(harita));

        vm.prank(ISLETME);
        harita.isletmeBasvurusuYap("Relay Kafe", "Kafe", 37_952_278, 27_430_561, keccak256("kayit-1"));
    }

    function testOnaysizIsletmeKimlikAlamaz() public {
        vm.prank(ISLETME);
        vm.expectRevert(IsletmeKimligi.IsletmeOnayliVeAktifDegil.selector);
        kimlik.kimlikAl(1);
    }

    function testOnayliIsletmeDevredilemezKimlikAlir() public {
        _onaylaVeKimlikAl();

        require(kimlik.ownerOf(1) == ISLETME);
        require(kimlik.balanceOf(ISLETME) == 1);
        require(kimlik.isletmeKimligi(ISLETME) == 1);
        require(kimlik.dogrulanmisIsletmeMi(ISLETME));

        vm.prank(ISLETME);
        vm.expectRevert(IsletmeKimligi.IsletmeKimligiDevredilemez.selector);
        kimlik.transferFrom(ISLETME, YABANCI, 1);
    }

    function testYabanciIsletmeninKimliginiAlamaz() public {
        vm.prank(YONETICI);
        harita.isletmeOnayla(1);

        vm.prank(YABANCI);
        vm.expectRevert(IsletmeKimligi.SadeceIsletmeSahibi.selector);
        kimlik.kimlikAl(1);
    }

    function testHaritadanKaldirilincaOdemeYetkisiKapanir() public {
        _onaylaVeKimlikAl();

        vm.prank(YONETICI);
        harita.isletmeAktifliginiAyarla(1, false);
        require(!kimlik.dogrulanmisIsletmeMi(ISLETME));
    }

    function testAyniKimlikIkinciKezAlinamaz() public {
        _onaylaVeKimlikAl();

        vm.prank(ISLETME);
        vm.expectRevert(IsletmeKimligi.KimlikZatenAlinmis.selector);
        kimlik.kimlikAl(1);
    }

    function _onaylaVeKimlikAl() private {
        vm.prank(YONETICI);
        harita.isletmeOnayla(1);
        vm.prank(ISLETME);
        kimlik.kimlikAl(1);
    }
}
