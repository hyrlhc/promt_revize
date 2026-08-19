// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice İşletme onaylarında her zaman güncel yöneticiyi okuyabilmek için
/// Yetkilendirme sözleşmesinin yalnızca gereken görünümünü kullanıyoruz.
interface IYetkilendirme {
    function yonetimDurumu() external view returns (address yoneticiAdresi, address[6] memory konseyAdresleri);
}

/// @title Yönetici onaylı topluluk işletmeleri haritası
/// @notice İşletmeler konum ve ödeme adresleriyle başvurur; yalnızca güncel
/// yönetici onayından sonra mobil uygulamadaki aktif işletme listesine girer.
contract IsletmeHaritasi {
    int32 private constant ENLEM_ALT_SINIR = -90_000_000;
    int32 private constant ENLEM_UST_SINIR = 90_000_000;
    int32 private constant BOYLAM_ALT_SINIR = -180_000_000;
    int32 private constant BOYLAM_UST_SINIR = 180_000_000;
    uint256 private constant MAKSIMUM_AD_UZUNLUGU = 64;
    uint256 private constant MAKSIMUM_KATEGORI_UZUNLUGU = 32;

    IYetkilendirme public immutable yetkilendirme;

    struct Isletme {
        address odemeAdresi;
        string ad;
        string kategori;
        // Koordinatlar altı ondalık basamakla tam sayı saklanır.
        // Örnek: 41.008900 enlemi zincirde 41008900 olarak tutulur.
        int32 enlemE6;
        int32 boylamE6;
        // Uygulamanın her başvuru için ürettiği tekil ve opak kayıt özeti.
        bytes32 kayitKimligi;
        bool onayli;
        bool aktif;
    }

    uint256 private _sonrakiIsletmeId = 1;
    mapping(uint256 id => Isletme isletme) private _isletmeler;
    mapping(bytes32 kayitKimligi => uint256 id) private _kayitKimligindenIsletmeId;
    uint256[] private _aktifIsletmeIdleri;
    mapping(uint256 id => uint256 birFazlaIndeks) private _aktifIsletmeIndeksi;

    error SifirAdresKullanilamaz();
    error SadeceYonetici();
    error GecersizIsletmeAdi();
    error GecersizKategori();
    error GecersizKoordinat();
    error GecersizKayitKimligi();
    error KayitKimligiZatenKullanilmis();
    error IsletmeBulunamadi();
    error IsletmeZatenOnayli();
    error IsletmeOnayliDegil();
    error SadeceIsletmeSahibi();
    error AyniDurumTekrarAyarlanamaz();
    error GecersizAktifIsletmeIndeksi();

    event IsletmeBasvurusuOlusturuldu(
        uint256 indexed id,
        address indexed odemeAdresi,
        bytes32 indexed kayitKimligi,
        string ad,
        int32 enlemE6,
        int32 boylamE6
    );
    event IsletmeOnaylandi(uint256 indexed id, address indexed yonetici);
    event IsletmeAktifligiDegisti(uint256 indexed id, bool aktif, address indexed yonetici);
    event IsletmeKonumuGuncellendi(uint256 indexed id, int32 enlemE6, int32 boylamE6);

    modifier sadeceYonetici() {
        (address yonetici,) = yetkilendirme.yonetimDurumu();
        if (msg.sender != yonetici) revert SadeceYonetici();
        _;
    }

    constructor(address yetkilendirmeAdresi) {
        if (yetkilendirmeAdresi == address(0)) revert SifirAdresKullanilamaz();
        yetkilendirme = IYetkilendirme(yetkilendirmeAdresi);
    }

    /// @notice İşletme kendi ödeme cüzdanıyla başvuru oluşturur.
    /// @dev Kayıt kimliği başvuruyu benzersizleştirir. Koordinatlar işletme
    /// tarafından girilir ve yönetici onaylamadan aktif haritada gösterilmez.
    function isletmeBasvurusuYap(
        string calldata ad,
        string calldata kategori,
        int32 enlemE6,
        int32 boylamE6,
        bytes32 kayitKimligi
    ) external returns (uint256 id) {
        _metinleriDogrula(ad, kategori);
        _koordinatiDogrula(enlemE6, boylamE6);
        if (kayitKimligi == bytes32(0)) revert GecersizKayitKimligi();
        if (_kayitKimligindenIsletmeId[kayitKimligi] != 0) revert KayitKimligiZatenKullanilmis();

        id = _sonrakiIsletmeId++;
        _isletmeler[id] = Isletme({
            odemeAdresi: msg.sender,
            ad: ad,
            kategori: kategori,
            enlemE6: enlemE6,
            boylamE6: boylamE6,
            kayitKimligi: kayitKimligi,
            onayli: false,
            aktif: false
        });
        _kayitKimligindenIsletmeId[kayitKimligi] = id;

        emit IsletmeBasvurusuOlusturuldu(id, msg.sender, kayitKimligi, ad, enlemE6, boylamE6);
    }

    /// @notice Güncel yönetici işletmeyi onaylar ve aktif haritaya ekler.
    function isletmeOnayla(uint256 id) external sadeceYonetici {
        Isletme storage isletme = _isletmeyiGetir(id);
        if (isletme.onayli) revert IsletmeZatenOnayli();

        isletme.onayli = true;
        isletme.aktif = true;
        _aktifListeyeEkle(id);
        emit IsletmeOnaylandi(id, msg.sender);
    }

    /// @notice Yönetici onaylı işletmeyi geçici olarak gizleyebilir veya geri açabilir.
    function isletmeAktifliginiAyarla(uint256 id, bool aktif) external sadeceYonetici {
        Isletme storage isletme = _isletmeyiGetir(id);
        if (!isletme.onayli) revert IsletmeOnayliDegil();
        if (isletme.aktif == aktif) revert AyniDurumTekrarAyarlanamaz();

        isletme.aktif = aktif;
        if (aktif) {
            _aktifListeyeEkle(id);
        } else {
            _aktifListedenCikar(id);
        }
        emit IsletmeAktifligiDegisti(id, aktif, msg.sender);
    }

    /// @notice İşletme konumunu değiştirirse önceki yönetici onayı geçersiz olur.
    /// Yeni koordinatın haritada görünmesi için yönetici yeniden onay vermelidir.
    function konumGuncelle(uint256 id, int32 yeniEnlemE6, int32 yeniBoylamE6) external {
        Isletme storage isletme = _isletmeyiGetir(id);
        if (msg.sender != isletme.odemeAdresi) revert SadeceIsletmeSahibi();
        _koordinatiDogrula(yeniEnlemE6, yeniBoylamE6);

        if (isletme.aktif) _aktifListedenCikar(id);
        isletme.enlemE6 = yeniEnlemE6;
        isletme.boylamE6 = yeniBoylamE6;
        isletme.onayli = false;
        isletme.aktif = false;

        emit IsletmeKonumuGuncellendi(id, yeniEnlemE6, yeniBoylamE6);
    }

    function aktifIsletmeSayisi() external view returns (uint256) {
        return _aktifIsletmeIdleri.length;
    }

    /// @notice Yönetici panelinin bekleyenler dahil bütün başvuruları okuyacağı sayı
    function isletmeSayisi() external view returns (uint256) {
        return _sonrakiIsletmeId - 1;
    }

    /// @notice Mobil haritanın indeksle okuyacağı aktif işletme kaydı.
    function aktifIsletme(uint256 indeks)
        external
        view
        returns (
            uint256 id,
            address odemeAdresi,
            string memory ad,
            string memory kategori,
            int32 enlemE6,
            int32 boylamE6,
            bytes32 kayitKimligi
        )
    {
        if (indeks >= _aktifIsletmeIdleri.length) revert GecersizAktifIsletmeIndeksi();
        id = _aktifIsletmeIdleri[indeks];
        Isletme storage isletme = _isletmeler[id];
        return (
            id,
            isletme.odemeAdresi,
            isletme.ad,
            isletme.kategori,
            isletme.enlemE6,
            isletme.boylamE6,
            isletme.kayitKimligi
        );
    }

    function isletmeBilgisi(uint256 id) external view returns (Isletme memory) {
        return _isletmeyiGetir(id);
    }

    /// @notice Opak kayıt kimliğinden yalnızca onaylı ve aktif işletmeyi bulur.
    function kayitKimligiIleIsletmeBul(bytes32 kayitKimligi) external view returns (uint256 id, Isletme memory isletme) {
        id = _kayitKimligindenIsletmeId[kayitKimligi];
        isletme = _isletmeyiGetir(id);
        if (!isletme.onayli || !isletme.aktif) revert IsletmeOnayliDegil();
    }

    function _isletmeyiGetir(uint256 id) private view returns (Isletme storage isletme) {
        isletme = _isletmeler[id];
        if (isletme.odemeAdresi == address(0)) revert IsletmeBulunamadi();
    }

    function _metinleriDogrula(string calldata ad, string calldata kategori) private pure {
        uint256 adUzunlugu = bytes(ad).length;
        uint256 kategoriUzunlugu = bytes(kategori).length;
        if (adUzunlugu == 0 || adUzunlugu > MAKSIMUM_AD_UZUNLUGU) revert GecersizIsletmeAdi();
        if (kategoriUzunlugu == 0 || kategoriUzunlugu > MAKSIMUM_KATEGORI_UZUNLUGU) revert GecersizKategori();
    }

    function _koordinatiDogrula(int32 enlemE6, int32 boylamE6) private pure {
        if (
            enlemE6 < ENLEM_ALT_SINIR || enlemE6 > ENLEM_UST_SINIR || boylamE6 < BOYLAM_ALT_SINIR
                || boylamE6 > BOYLAM_UST_SINIR
        ) revert GecersizKoordinat();
    }

    function _aktifListeyeEkle(uint256 id) private {
        _aktifIsletmeIdleri.push(id);
        _aktifIsletmeIndeksi[id] = _aktifIsletmeIdleri.length;
    }

    function _aktifListedenCikar(uint256 id) private {
        uint256 silinecekIndeks = _aktifIsletmeIndeksi[id] - 1;
        uint256 sonIndeks = _aktifIsletmeIdleri.length - 1;

        if (silinecekIndeks != sonIndeks) {
            uint256 tasinanId = _aktifIsletmeIdleri[sonIndeks];
            _aktifIsletmeIdleri[silinecekIndeks] = tasinanId;
            _aktifIsletmeIndeksi[tasinanId] = silinecekIndeks + 1;
        }

        _aktifIsletmeIdleri.pop();
        delete _aktifIsletmeIndeksi[id];
    }
}
