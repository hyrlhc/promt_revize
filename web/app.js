const urlParams = new URLSearchParams(window.location.search);

const CONFIG = {
  rpcUrl: urlParams.get("rpc") || "/rpc",
  chainId: "0x7a69",
  contractAddress: urlParams.get("contract") || "0x5FbDB2315678afecb367f032d93F642f64180aa3",
  selectors: {
    yonetimDurumu: "0xa797fed3",
    toplulukUyesiSayisi: "0xfa566874",
    toplulukUyesi: "0x87441ddf",
  },
};

const durum = document.querySelector("#durum");
const yenile = document.querySelector("#yenile");
const yoneticiAdresi = document.querySelector("#yonetici-adresi");
const konseyAdresleri = [...document.querySelectorAll("[data-konsey]")];
const toplulukListesi = document.querySelector("#topluluk-listesi");
const uyeSayisi = document.querySelector("#uye-sayisi");
const sonGuncelleme = document.querySelector("#son-guncelleme");

let istekKimligi = 0;

async function rpcCagir(method, params) {
  const response = await fetch(CONFIG.rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++istekKimligi, method, params }),
  });

  if (!response.ok) throw new Error(`RPC isteği başarısız: ${response.status}`);

  const body = await response.json();
  if (body.error) throw new Error(body.error.message || "RPC bilinmeyen bir hata döndürdü.");

  return body.result;
}

function adresGecerliMi(address) {
  return /^0x[0-9a-fA-F]{40}$/.test(address);
}

function adresKelimesiniCoz(kelime) {
  return `0x${kelime.slice(-40)}`;
}

function yonetimAdresleriniCoz(encodedResult) {
  const temizVeri = encodedResult.startsWith("0x") ? encodedResult.slice(2) : encodedResult;
  if (temizVeri.length < 7 * 64) throw new Error("Sözleşme beklenen yönetim verisini döndürmedi.");

  return Array.from({ length: 7 }, (_, index) => {
    const kelime = temizVeri.slice(index * 64, (index + 1) * 64);
    return adresKelimesiniCoz(kelime);
  });
}

function toplulukUyesiniCoz(encodedResult) {
  const temizVeri = encodedResult.startsWith("0x") ? encodedResult.slice(2) : encodedResult;
  if (temizVeri.length < 2 * 64) throw new Error("Topluluk üyesi verisi eksik döndü.");

  return {
    uye: adresKelimesiniCoz(temizVeri.slice(0, 64)),
    ekleyen: adresKelimesiniCoz(temizVeri.slice(64, 128)),
  };
}

function uintParametresi(index) {
  return BigInt(index).toString(16).padStart(64, "0");
}

function explorerAdresi(address) {
  // Yerel Anvil adreslerinin herkese açık explorer sayfası yoktur.
  if (CONFIG.chainId === "0x7a69") return null;
  return `https://sepolia.basescan.org/address/${address}`;
}

function adresBaglantisiniAyarla(element, address) {
  const explorerUrl = explorerAdresi(address);
  if (explorerUrl) {
    element.href = explorerUrl;
  } else {
    element.removeAttribute("href");
  }
}

function adresiGoster(element, address, rol) {
  element.textContent = `${address.slice(0, 6)}…${address.slice(-4)}`;
  adresBaglantisiniAyarla(element, address);
  element.setAttribute("aria-label", `${rol}: ${address}`);
  element.title = address;
}

function toplulukKartlariniGoster(uyeler) {
  toplulukListesi.replaceChildren();
  uyeSayisi.textContent = `${uyeler.length} üye`;

  if (uyeler.length === 0) {
    const bosMesaj = document.createElement("p");
    bosMesaj.className = "bos-liste";
    bosMesaj.textContent = "Aktif topluluk üyesi bulunmuyor.";
    toplulukListesi.append(bosMesaj);
    return;
  }

  uyeler.forEach(({ uye, ekleyen }, index) => {
    const kart = document.createElement("article");
    kart.className = "uye-karti";

    const rol = document.createElement("p");
    rol.className = "rutbe";
    rol.textContent = `Topluluk Üyesi ${index + 1}`;

    const uyeLinki = document.createElement("a");
    uyeLinki.className = "adres";
    adresBaglantisiniAyarla(uyeLinki, uye);
    uyeLinki.textContent = uye;
    uyeLinki.setAttribute("aria-label", `Topluluk üyesi ${index + 1}: ${uye}`);

    const ekleyenMetni = document.createElement("p");
    ekleyenMetni.className = "ekleyen";
    ekleyenMetni.textContent = "Topluluğa ekleyen";

    const ekleyenLinki = document.createElement("a");
    adresBaglantisiniAyarla(ekleyenLinki, ekleyen);
    ekleyenLinki.textContent = ekleyen;
    ekleyenLinki.setAttribute("aria-label", `Üyeyi topluluğa ekleyen: ${ekleyen}`);

    ekleyenMetni.append(ekleyenLinki);
    kart.append(rol, uyeLinki, ekleyenMetni);
    toplulukListesi.append(kart);
  });
}

async function toplulukUyeleriniOku() {
  const sayiSonucu = await rpcCagir("eth_call", [
    { to: CONFIG.contractAddress, data: CONFIG.selectors.toplulukUyesiSayisi },
    "latest",
  ]);
  const sayi = Number(BigInt(sayiSonucu));

  // İlk demo için istemciyi yanlış veya aşırı büyük bir yanıttan koruyan sınır.
  if (!Number.isSafeInteger(sayi) || sayi > 500) throw new Error("Topluluk üye sayısı güvenli sınırı aşıyor.");

  const istekler = Array.from({ length: sayi }, (_, index) => {
    const data = `${CONFIG.selectors.toplulukUyesi}${uintParametresi(index)}`;
    return rpcCagir("eth_call", [{ to: CONFIG.contractAddress, data }, "latest"]);
  });

  const sonuclar = await Promise.all(istekler);
  return sonuclar.map(toplulukUyesiniCoz);
}

async function yonetimiYukle() {
  yenile.disabled = true;
  durum.removeAttribute("role");

  try {
    if (!adresiGecerliMi(CONFIG.contractAddress)) {
      throw new Error("Yerel Yetkilendirme sözleşmesinin adresi henüz ayarlanmadı.");
    }

    durum.textContent = "Anvil'den yönetici, konsey ve topluluk bilgisi okunuyor…";

    const chainId = await rpcCagir("eth_chainId", []);
    if (chainId.toLowerCase() !== CONFIG.chainId) throw new Error("RPC, beklenen Anvil ağına bağlı değil.");

    const code = await rpcCagir("eth_getCode", [CONFIG.contractAddress, "latest"]);
    if (!code || code === "0x") throw new Error("Bu adreste deploy edilmiş sözleşme bulunamadı.");

    const [yonetimSonucu, uyeler] = await Promise.all([
      rpcCagir("eth_call", [
        { to: CONFIG.contractAddress, data: CONFIG.selectors.yonetimDurumu },
        "latest",
      ]),
      toplulukUyeleriniOku(),
    ]);

    const [yonetici, ...konsey] = yonetimAdresleriniCoz(yonetimSonucu);
    adresiGoster(yoneticiAdresi, yonetici, "Yönetici");
    konseyAdresleri.forEach((element, index) => adresiGoster(element, konsey[index], `Konsey ${index + 1}`));
    toplulukKartlariniGoster(uyeler);

    durum.textContent = "Yönetici, altı konsey üyesi ve topluluk kayıtları Anvil'den okundu.";
    sonGuncelleme.textContent = new Intl.DateTimeFormat("tr-TR", {
      dateStyle: "medium",
      timeStyle: "medium",
    }).format(new Date());
  } catch (error) {
    durum.textContent = error instanceof Error ? error.message : "Beklenmeyen bir hata oluştu.";
    durum.setAttribute("role", "alert");
  } finally {
    yenile.disabled = false;
  }
}

yenile.addEventListener("click", yonetimiYukle);
yonetimiYukle();
