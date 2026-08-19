# Relay — Base Sepolia topluluk cüzdanı

Relay dört küçük sözleşme ve bir React Native cüzdandan oluşur:

- `Yetkilendirme.sol`: yönetici, altı kişilik konsey ve topluluk üyeleri
- `RlayToken.sol`: transfer edilebilir, yönetici tarafından basılan RLAY
- `IsletmeHaritasi.sol`: işletme başvurusu, yönetici onayı ve aktif konum haritası
- `IsletmeKimligi.sol`: onaylı işletmeler için devredilemez doğrulama NFT’si
- `mobile/`: cüzdan oluşturma/içe aktarma, QR ödeme, RLAY transferi, işletme ve yönetici ekranları

Sözleşme bağımlılığı şöyledir:

```text
Yetkilendirme
├── RlayToken       (güncel yöneticiyi buradan okur)
├── IsletmeHaritasi (güncel yöneticiyi buradan okur)
└── IsletmeKimligi  (aktif işletmeyi IsletmeHaritasi'ndan doğrular)
```

## Test

```bash
forge test
cd mobile
npm run typecheck
```

## Base Sepolia deploy

Yayın scripti yönetici olarak `0x1E9aCE552E9c9c3bB5C3c8D3DA452Be6c5c93F9e`
adresini kullanır. Teknik deployer bu yetkiyi almaz.

```bash
forge script script/DeployRelay.s.sol:DeployRelay \
  --rpc-url https://base-sepolia-rpc.publicnode.com \
  --broadcast \
  --keystore .wallet/burner \
  --password-file .secrets/burner-password
```

Deploy adreslerini `mobile/.env.local` içine yaz:

```text
EXPO_PUBLIC_BASE_SEPOLIA_RPC_URL=https://base-sepolia-rpc.publicnode.com
EXPO_PUBLIC_YETKILENDIRME_ADDRESS=0x...
EXPO_PUBLIC_ISLETME_HARITASI_ADDRESS=0x...
EXPO_PUBLIC_RLAY_TOKEN_ADDRESS=0x...
EXPO_PUBLIC_ISLETME_KIMLIGI_ADDRESS=0x...
EXPO_PUBLIC_RELAY_API_URL=http://BILGISAYARIN_YEREL_IP_ADRESI:8787
```

## Mobil uygulama

```bash
cd mobile
npm install
npx expo run:android
# veya macOS ve Xcode ile: npx expo run:ios
```

Ana ekrandaki QR yalnızca herkese açık cüzdan adresini taşır. İşletme paneli bu
kodu kamerayla okur, tutarı girer ve üç dakikalık imzalı ödeme isteği yollar.
Yalnızca aktif işletme NFT’sine sahip cüzdan bunu yapabilir.

Kasadaki üç dakikalık imzalı tutarı iki telefon arasında taşımak için `relay-api`
çalıştırılır. Bu servis para ve özel anahtar tutmaz; nihai transfer Base Sepolia'daki
RLAY sözleşmesinde gerçekleşir.

Bu sürüm yalnızca testnet prototipidir. Gerçek değere sahip varlıklarla kullanılmadan önce bağımsız
akıllı sözleşme ve mobil cüzdan güvenlik denetimi gerekir.
