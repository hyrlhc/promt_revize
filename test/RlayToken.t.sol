// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {RlayToken} from "../src/RlayToken.sol";
import {Yetkilendirme} from "../src/Yetkilendirme.sol";

interface VmToken {
    function prank(address gonderen) external;
    function expectRevert(bytes4 hata) external;
}

contract RlayTokenTest {
    VmToken private constant vm = VmToken(address(uint160(uint256(keccak256("hevm cheat code")))));

    address private constant YONETICI = address(0x100);
    address private constant UYE_1 = address(0x101);
    address private constant UYE_2 = address(0x102);
    address private constant UYE_3 = address(0x103);
    address private constant UYE_4 = address(0x104);
    address private constant UYE_5 = address(0x105);
    address private constant UYE_6 = address(0x106);
    address private constant YENI_YONETICI = address(0x200);
    address private constant ALICI = address(0x300);
    address private constant HARCAYAN = address(0x400);

    Yetkilendirme private yetkilendirme;
    RlayToken private token;

    function setUp() public {
        yetkilendirme = new Yetkilendirme(YONETICI, UYE_1, UYE_2, UYE_3, UYE_4, UYE_5, UYE_6);
        token = new RlayToken(address(yetkilendirme));
    }

    function testYoneticiTokenBasabilirVeTransferEdilebilir() public {
        vm.prank(YONETICI);
        token.tokenBas(ALICI, 100 ether);

        vm.prank(ALICI);
        require(token.transfer(HARCAYAN, 25 ether));

        require(token.balanceOf(ALICI) == 75 ether);
        require(token.balanceOf(HARCAYAN) == 25 ether);
        require(token.totalSupply() == 100 ether);
    }

    function testYoneticiOlmayanTokenBasamaz() public {
        vm.prank(UYE_1);
        vm.expectRevert(RlayToken.SadeceYonetici.selector);
        token.tokenBas(ALICI, 1 ether);
    }

    function testGuncelYoneticiTokenBasmaYetkisiniDevralir() public {
        _yoneticiOyuVer(UYE_1);
        _yoneticiOyuVer(UYE_2);
        _yoneticiOyuVer(UYE_3);
        _yoneticiOyuVer(UYE_4);

        vm.prank(YONETICI);
        vm.expectRevert(RlayToken.SadeceYonetici.selector);
        token.tokenBas(ALICI, 1 ether);

        vm.prank(YENI_YONETICI);
        token.tokenBas(ALICI, 1 ether);
        require(token.balanceOf(ALICI) == 1 ether);
    }

    function testApproveVeTransferFromCalisir() public {
        vm.prank(YONETICI);
        token.tokenBas(ALICI, 10 ether);

        vm.prank(ALICI);
        token.approve(HARCAYAN, 4 ether);

        vm.prank(HARCAYAN);
        require(token.transferFrom(ALICI, UYE_6, 3 ether));

        require(token.balanceOf(UYE_6) == 3 ether);
        require(token.allowance(ALICI, HARCAYAN) == 1 ether);
    }

    function testMaksimumArzAsilamaz() public {
        uint256 maksimumArz = token.MAKSIMUM_ARZ();
        vm.prank(YONETICI);
        vm.expectRevert(RlayToken.MaksimumArzAsildi.selector);
        token.tokenBas(ALICI, maksimumArz + 1);
    }

    function _yoneticiOyuVer(address uye) private {
        vm.prank(uye);
        yetkilendirme.yoneticilikIcinOyVer(false, YENI_YONETICI);
    }
}
