# Relay Payment Relay

Kasadaki birkaç dakikalık ödeme isteğini işletme ve müşteri telefonu arasında
taşıyan, bağımlılıksız yerel prototip servisidir. Para veya özel anahtar tutmaz.
İşletme, müşteri adresini QR’dan okur ve tutarı cüzdanıyla imzalar. Servis isteği
kabul etmeden önce işletmenin aktif harita kaydını ve devredilemez doğrulanmış
işletme NFT’sini Base Sepolia’dan kontrol eder. Müşteri cevabı da alıcı cüzdanıyla
imzalanır. Nihai ödeme Base Sepolia'daki RLAY sözleşmesindedir.

```bash
npm start
```

Varsayılan adres `http://0.0.0.0:8787` olur. Fiziksel telefonlarla test ederken
`mobile/.env.local` içindeki `EXPO_PUBLIC_RELAY_API_URL` değerini bilgisayarın
aynı Wi-Fi ağındaki IP adresine ayarla.

Bu prototip istekleri yalnızca bellekte ve üç dakikalık süreyle tutar; servis
yeniden başlarsa açık istekler silinir. Üretimde kalıcı veri deposu, hız sınırı,
TLS ve birden fazla sunucu arasında olay dağıtımı gerekir.
