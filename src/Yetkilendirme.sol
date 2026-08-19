// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Bir yönetici ve altı konsey üyesi bulunan topluluk yetkilendirme sözleşmesi
/// @notice İlk yönetici ve başlangıç konseyi yayınlama sırasında açıkça verilir
contract Yetkilendirme {
    uint8 private constant KONSEY_UYE_SAYISI = 6;
    uint8 private constant YONETICIYI_DEGISTIRME_ESIGI = 4;
    uint8 private constant YONETICIYLE_KONSEY_DEGISTIRME_ESIGI = 2;
    uint8 private constant SADECE_KONSEYLE_DEGISTIRME_ESIGI = 5;

    address private _yonetici;
    address[6] private _konseyUyeleri;
    mapping(address => bool) private _konseyUyesiMi;

    struct ToplulukUyesiKaydi {
        bool aktif;
        address ekleyen;
    }

    mapping(address uye => ToplulukUyesiKaydi kayit) private _toplulukUyelikleri;
    address[] private _aktifToplulukUyeleri;
    mapping(address uye => uint256 birFazlaIndeks) private _aktifToplulukUyesiIndeksi;

    // Yönetici veya konsey değiştiğinde tur artar. Böylece eski yönetime ait
    // tamamlanmamış oylar yeni yönetimde yanlışlıkla kullanılamaz.
    uint256 private _yonetimTuru;

    struct YoneticiOyu {
        bool kullanildi;
        bool yoneticiDursunMu;
        address onerilenYeniYonetici;
    }

    mapping(uint256 tur => mapping(address uye => YoneticiOyu oy)) private _yoneticiOylari;
    mapping(uint256 tur => uint8 oySayisi) private _yoneticiGitsinOySayisi;
    mapping(uint256 tur => mapping(address aday => uint8 oySayisi)) private _yoneticiAdayiOySayisi;

    // Bir üye aynı koltuk için yalnızca tek adayı destekler. Üye fikrini
    // değiştirirse eski adaydan oyu düşülüp yeni adaya eklenir.
    mapping(uint256 tur => mapping(address gidecekUye => mapping(address oyVeren => address aday))) private
        _konseyTercihi;
    mapping(bytes32 teklif => uint8 oySayisi) private _konseyOySayisi;
    mapping(bytes32 teklif => bool onaylandi) private _yoneticiKonseyOnayi;

    error SifirAdresKullanilamaz();
    error AdreslerFarkliOlmali();
    error YoneticiKonseyUyesiOlamaz();
    error AdresZatenKonseyUyesi();
    error AdresKonseyUyesiDegil();
    error GecersizYoneticiAdayi();
    error SadeceKonseyUyesi();
    error SadeceYoneticiVeyaKonseyUyesi();
    error AyniOyTekrarKullanilamaz();
    error ToplulukUyesiZatenVar();
    error ToplulukUyesiDegil();
    error GecersizToplulukUyesiIndeksi();

    event YoneticiOyuVerildi(
        address indexed oyVeren,
        bool yoneticiDursunMu,
        address indexed onerilenYeniYonetici,
        uint8 yoneticiGitsinOySayisi,
        uint8 adayinOySayisi
    );
    event YoneticiDegisti(address indexed eskiYonetici, address indexed yeniYonetici);
    event KonseyDegisikligiOyuVerildi(
        address indexed oyVeren,
        address indexed gidecekUye,
        address indexed gelecekUye,
        bool yoneticiOnayi,
        uint8 konseyOySayisi
    );
    event KonseyUyesiDegisti(address indexed gidenUye, address indexed gelenUye);
    event ToplulukUyesiEklendi(address indexed uye, address indexed ekleyen);
    event ToplulukUyesiCikarildi(address indexed uye, address indexed cikaran, address indexed ilkEkleyen);

    modifier sadeceKonseyUyesi() {
        if (!_konseyUyesiMi[msg.sender]) revert SadeceKonseyUyesi();
        _;
    }

    modifier sadeceYoneticiVeyaKonseyUyesi() {
        if (msg.sender != _yonetici && !_konseyUyesiMi[msg.sender]) revert SadeceYoneticiVeyaKonseyUyesi();
        _;
    }

    constructor(
        address ilkYonetici,
        address konseyUyesi1,
        address konseyUyesi2,
        address konseyUyesi3,
        address konseyUyesi4,
        address konseyUyesi5,
        address konseyUyesi6
    ) {
        // Yayınlayan teknik cüzdan ile topluluğun yöneticisi aynı olmak zorunda
        // değildir. Böylece deploy anahtarı yönetime kalıcı yetki kazanmaz.
        if (ilkYonetici == address(0)) revert SifirAdresKullanilamaz();
        _yonetici = ilkYonetici;

        address[6] memory ilkUyeler =
            [konseyUyesi1, konseyUyesi2, konseyUyesi3, konseyUyesi4, konseyUyesi5, konseyUyesi6];

        for (uint256 i = 0; i < KONSEY_UYE_SAYISI; i++) {
            address uye = ilkUyeler[i];

            // Sıfır adres, yönetici veya daha önce eklenmiş bir adres konseyde
            // kullanılamaz. Böylece her zaman altı farklı konsey cüzdanı kalır.
            if (uye == address(0)) revert SifirAdresKullanilamaz();
            if (uye == _yonetici) revert YoneticiKonseyUyesiOlamaz();
            if (_konseyUyesiMi[uye]) revert AdresZatenKonseyUyesi();

            _konseyUyeleri[i] = uye;
            _konseyUyesiMi[uye] = true;
        }
    }

    /// @notice Yöneticiyi ve altı konsey üyesini tek okumada döndürür
    function yonetimDurumu() external view returns (address yoneticiAdresi, address[6] memory konseyAdresleri) {
        return (_yonetici, _konseyUyeleri);
    }

    /// @notice Yönetici veya mevcut konsey üyesi olan hesaplar için true döndürür
    function yetkiliMi(address hesap) external view returns (bool) {
        return hesap == _yonetici || _konseyUyesiMi[hesap];
    }

    /// @notice Adds a wallet to the community and records which authority added it
    function toplulukUyesiEkle(address yeniUye) external sadeceYoneticiVeyaKonseyUyesi {
        if (yeniUye == address(0)) revert SifirAdresKullanilamaz();
        if (_toplulukUyelikleri[yeniUye].aktif) revert ToplulukUyesiZatenVar();

        // Aktif üyeler ayrı bir dizide tutulur; bu sayede web sitesi üyeleri
        // tek tek indeksle okuyabilir. İndeksin bir fazlası saklanarak sıfır,
        // "listede değil" işareti olarak kullanılabilir.
        _aktifToplulukUyeleri.push(yeniUye);
        _aktifToplulukUyesiIndeksi[yeniUye] = _aktifToplulukUyeleri.length;

        // Ekleyen adres doğrudan cüzdan adresiyle eşleştirilir. Üye çıkarılsa
        // bile bu alan silinmez; son üyeliği kimin verdiği zincirde kalır.
        _toplulukUyelikleri[yeniUye] = ToplulukUyesiKaydi({aktif: true, ekleyen: msg.sender});

        emit ToplulukUyesiEklendi(yeniUye, msg.sender);
    }

    /// @notice Aktif üyeyi çıkarır; yönetici ve konsey bu işlemde eşit yetkilidir
    function toplulukUyesiCikar(address uye) external sadeceYoneticiVeyaKonseyUyesi {
        ToplulukUyesiKaydi storage kayit = _toplulukUyelikleri[uye];
        if (!kayit.aktif) revert ToplulukUyesiDegil();

        uint256 silinecekIndeks = _aktifToplulukUyesiIndeksi[uye] - 1;
        uint256 sonIndeks = _aktifToplulukUyeleri.length - 1;

        // Dizinin ortasından silmek pahalı olduğu için son üyeyi boşalan yere
        // taşıyıp diziyi kısaltıyoruz. Üyelerin sırası kimlik veya rütbe değildir.
        if (silinecekIndeks != sonIndeks) {
            address tasinanUye = _aktifToplulukUyeleri[sonIndeks];
            _aktifToplulukUyeleri[silinecekIndeks] = tasinanUye;
            _aktifToplulukUyesiIndeksi[tasinanUye] = silinecekIndeks + 1;
        }

        _aktifToplulukUyeleri.pop();
        delete _aktifToplulukUyesiIndeksi[uye];
        kayit.aktif = false;

        emit ToplulukUyesiCikarildi(uye, msg.sender, kayit.ekleyen);
    }

    /// @notice Returns the number of currently active community members
    function toplulukUyesiSayisi() external view returns (uint256) {
        return _aktifToplulukUyeleri.length;
    }

    /// @notice Returns an active community member and the authority that added it
    function toplulukUyesi(uint256 indeks) external view returns (address uye, address ekleyen) {
        if (indeks >= _aktifToplulukUyeleri.length) revert GecersizToplulukUyesiIndeksi();

        uye = _aktifToplulukUyeleri[indeks];
        ekleyen = _toplulukUyelikleri[uye].ekleyen;
    }

    /// @notice Keeps the latest membership trace readable even after removal
    function toplulukUyesiBilgisi(address uye) external view returns (bool aktif, address ekleyen) {
        ToplulukUyesiKaydi memory kayit = _toplulukUyelikleri[uye];
        return (kayit.aktif, kayit.ekleyen);
    }

    /// @notice Konsey üyesinin mevcut yöneticiyi değerlendirmesini ve alternatif aday önermesini sağlar
    function yoneticilikIcinOyVer(bool yoneticiDursunMu, address onerilenYeniYonetici) external sadeceKonseyUyesi {
        // Yeni yönetici sıfır adres, mevcut yönetici veya mevcut konseyden biri olamaz.
        // Konseyden biri yönetici olursa altı bağımsız konsey koltuğu kuralı bozulurdu.
        if (
            onerilenYeniYonetici == address(0) || onerilenYeniYonetici == _yonetici
                || _konseyUyesiMi[onerilenYeniYonetici]
        ) {
            revert GecersizYoneticiAdayi();
        }

        uint256 tur = _yonetimTuru;
        YoneticiOyu storage oncekiOy = _yoneticiOylari[tur][msg.sender];

        if (
            oncekiOy.kullanildi && oncekiOy.yoneticiDursunMu == yoneticiDursunMu
                && oncekiOy.onerilenYeniYonetici == onerilenYeniYonetici
        ) revert AyniOyTekrarKullanilamaz();

        // Üye oyunu değiştiriyorsa önce eski oyun sayaçlardaki etkisini kaldır.
        if (oncekiOy.kullanildi) {
            if (!oncekiOy.yoneticiDursunMu) _yoneticiGitsinOySayisi[tur] -= 1;
            _yoneticiAdayiOySayisi[tur][oncekiOy.onerilenYeniYonetici] -= 1;
        }

        oncekiOy.kullanildi = true;
        oncekiOy.yoneticiDursunMu = yoneticiDursunMu;
        oncekiOy.onerilenYeniYonetici = onerilenYeniYonetici;

        if (!yoneticiDursunMu) _yoneticiGitsinOySayisi[tur] += 1;
        _yoneticiAdayiOySayisi[tur][onerilenYeniYonetici] += 1;

        emit YoneticiOyuVerildi(
            msg.sender,
            yoneticiDursunMu,
            onerilenYeniYonetici,
            _yoneticiGitsinOySayisi[tur],
            _yoneticiAdayiOySayisi[tur][onerilenYeniYonetici]
        );

        // Yonetim ancak iki şart aynı anda gerçekleşirse değişir:
        // 1) En az dört üye mevcut yöneticinin gitmesini ister.
        // 2) Aynı yeni yönetici adayı en az dört öneri alır.
        // "Yönetici dursun" diyen bir üyenin aday önerisi ikinci şartta sayılır.
        if (_yoneticiGitsinOySayisi[tur] >= YONETICIYI_DEGISTIRME_ESIGI) {
            address yeterliOyAlanAday = _dortOyAlanAdayiBul(tur);
            if (yeterliOyAlanAday != address(0)) _yoneticiyiDegistir(yeterliOyAlanAday);
        }
    }

    /// @notice Votes to replace one council member with another wallet
    function konseyDegisikligiIcinOyVer(address gidecekUye, address gelecekUye) external sadeceYoneticiVeyaKonseyUyesi {
        bool oyVerenYonetici = msg.sender == _yonetici;
        if (!_konseyUyesiMi[gidecekUye]) revert AdresKonseyUyesiDegil();
        if (gelecekUye == address(0)) revert SifirAdresKullanilamaz();
        if (gidecekUye == gelecekUye) revert AdreslerFarkliOlmali();
        if (gelecekUye == _yonetici) revert YoneticiKonseyUyesiOlamaz();
        if (_konseyUyesiMi[gelecekUye]) revert AdresZatenKonseyUyesi();

        uint256 tur = _yonetimTuru;
        address oncekiAday = _konseyTercihi[tur][gidecekUye][msg.sender];
        if (oncekiAday == gelecekUye) revert AyniOyTekrarKullanilamaz();

        // Aynı koltuk için daha önce başka birini desteklediyse eski desteği sil.
        if (oncekiAday != address(0)) {
            bytes32 oncekiTeklif = _konseyTeklifKimligi(tur, gidecekUye, oncekiAday);
            if (oyVerenYonetici) {
                _yoneticiKonseyOnayi[oncekiTeklif] = false;
            } else {
                _konseyOySayisi[oncekiTeklif] -= 1;
            }
        }

        _konseyTercihi[tur][gidecekUye][msg.sender] = gelecekUye;
        bytes32 teklif = _konseyTeklifKimligi(tur, gidecekUye, gelecekUye);

        if (oyVerenYonetici) {
            _yoneticiKonseyOnayi[teklif] = true;
        } else {
            _konseyOySayisi[teklif] += 1;
        }

        emit KonseyDegisikligiOyuVerildi(
            msg.sender, gidecekUye, gelecekUye, _yoneticiKonseyOnayi[teklif], _konseyOySayisi[teklif]
        );

        // Değişiklik için iki alternatif yol vardır:
        // - yöneticinin onayı + en az iki konsey üyesi,
        // - yöneticinin onayı olmadan en az beş konsey üyesi.
        bool yoneticiVeIkiUye =
            _yoneticiKonseyOnayi[teklif] && _konseyOySayisi[teklif] >= YONETICIYLE_KONSEY_DEGISTIRME_ESIGI;
        bool besKonseyUyesi = _konseyOySayisi[teklif] >= SADECE_KONSEYLE_DEGISTIRME_ESIGI;

        if (yoneticiVeIkiUye || besKonseyUyesi) _konseyUyesiniDegistir(gidecekUye, gelecekUye);
    }

    function _dortOyAlanAdayiBul(uint256 tur) private view returns (address) {
        // Konsey daima altı kişi olduğu için bu döngünün maliyeti sınırlıdır.
        for (uint256 i = 0; i < KONSEY_UYE_SAYISI; i++) {
            address aday = _yoneticiOylari[tur][_konseyUyeleri[i]].onerilenYeniYonetici;
            if (aday != address(0) && _yoneticiAdayiOySayisi[tur][aday] >= YONETICIYI_DEGISTIRME_ESIGI) {
                return aday;
            }
        }

        return address(0);
    }

    function _yoneticiyiDegistir(address yeniYonetici) private {
        address eskiYonetici = _yonetici;
        _yonetici = yeniYonetici;

        // Yeni tur, eski yöneticinin onayladığı konsey tekliflerini ve eski konseyin
        // kullandığı yonetim oylarını geçersiz kılar.
        _yonetimTuru += 1;
        emit YoneticiDegisti(eskiYonetici, yeniYonetici);
    }

    function _konseyUyesiniDegistir(address gidecekUye, address gelecekUye) private {
        for (uint256 i = 0; i < KONSEY_UYE_SAYISI; i++) {
            if (_konseyUyeleri[i] == gidecekUye) {
                _konseyUyeleri[i] = gelecekUye;
                break;
            }
        }

        _konseyUyesiMi[gidecekUye] = false;
        _konseyUyesiMi[gelecekUye] = true;

        // Üyelik değiştiği anda önceki yönetime ait bütün eksik teklifler biter.
        _yonetimTuru += 1;
        emit KonseyUyesiDegisti(gidecekUye, gelecekUye);
    }

    function _konseyTeklifKimligi(uint256 tur, address gidecekUye, address gelecekUye) private pure returns (bytes32) {
        return keccak256(abi.encode(tur, gidecekUye, gelecekUye));
    }
}
