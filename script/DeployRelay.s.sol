// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IsletmeHaritasi} from "../src/IsletmeHaritasi.sol";
import {RlayToken} from "../src/RlayToken.sol";
import {Yetkilendirme} from "../src/Yetkilendirme.sol";

interface VmRelayDeploy {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @notice Relay'in üç küçük sözleşmesini doğru bağımlılık sırasıyla yayınlar
contract DeployRelay {
    VmRelayDeploy private constant vm = VmRelayDeploy(address(uint160(uint256(keccak256("hevm cheat code")))));

    // Kullanıcının belirlediği yönetici. Deploy cüzdanı bu rolde kalmaz.
    address private constant YONETICI = 0x1E9aCE552E9c9c3bB5C3c8D3DA452Be6c5c93F9e;

    // Base Sepolia prototipi için ayrı ayrı üretilmiş şifreli test keystore'ları.
    // Üretim yayınında bunlar topluluğun gerçek altı cüzdanıyla değiştirilmelidir.
    address private constant KONSEY_1 = 0x1B133EF5668984A684D5e2cE90078D7266A2a126;
    address private constant KONSEY_2 = 0x39736eE1df567F67C9BB61b62009854D8Ca4b3b1;
    address private constant KONSEY_3 = 0xE558BD53BD61985Adaf3C796394d579540d2A740;
    address private constant KONSEY_4 = 0x5EBC3422C883aC5a33cdBC26f555Bd23f988d0EA;
    address private constant KONSEY_5 = 0x5C540EAd230Fa357cf4c789a8d703B4BeAb46833;
    address private constant KONSEY_6 = 0x742889fA0d5052e6b5C2dAc33afa08ca009875f1;

    function run() external returns (Yetkilendirme yetkilendirme, RlayToken token, IsletmeHaritasi harita) {
        vm.startBroadcast();

        yetkilendirme = new Yetkilendirme(YONETICI, KONSEY_1, KONSEY_2, KONSEY_3, KONSEY_4, KONSEY_5, KONSEY_6);
        token = new RlayToken(address(yetkilendirme));
        harita = new IsletmeHaritasi(address(yetkilendirme));

        vm.stopBroadcast();
    }
}
