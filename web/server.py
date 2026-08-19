import html
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from datetime import datetime
from urllib.request import Request, urlopen


WEB_ROOT = Path(__file__).resolve().parent
ANVIL_RPC_URL = "http://127.0.0.1:8545"
CONTRACT_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3"
YONETIM_DURUMU_SELECTOR = "0xa797fed3"
TOPLULUK_UYESI_SAYISI_SELECTOR = "0xfa566874"
TOPLULUK_UYESI_SELECTOR = "0x87441ddf"


def rpc_call(method, params):
    request_body = json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    ).encode()
    request = Request(
        ANVIL_RPC_URL,
        data=request_body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    with urlopen(request, timeout=10) as response:
        body = json.loads(response.read())

    if "error" in body:
        raise RuntimeError(body["error"].get("message", "Unknown RPC error"))

    return body["result"]


def decode_address(word):
    return f"0x{word[-40:]}"


def read_local_contract():
    management_result = rpc_call(
        "eth_call",
        [{"to": CONTRACT_ADDRESS, "data": YONETIM_DURUMU_SELECTOR}, "latest"],
    )[2:]
    management_addresses = [
        decode_address(management_result[index * 64 : (index + 1) * 64])
        for index in range(7)
    ]

    member_count_result = rpc_call(
        "eth_call",
        [{"to": CONTRACT_ADDRESS, "data": TOPLULUK_UYESI_SAYISI_SELECTOR}, "latest"],
    )
    member_count = int(member_count_result, 16)
    members = []

    for index in range(member_count):
        encoded_index = f"{index:064x}"
        member_result = rpc_call(
            "eth_call",
            [
                {
                    "to": CONTRACT_ADDRESS,
                    "data": f"{TOPLULUK_UYESI_SELECTOR}{encoded_index}",
                },
                "latest",
            ],
        )[2:]
        members.append(
            {
                "address": decode_address(member_result[:64]),
                "added_by": decode_address(member_result[64:128]),
            }
        )

    return management_addresses, members


def member_cards(members):
    if not members:
        return '<p class="bos-liste">Aktif topluluk üyesi bulunmuyor.</p>'

    cards = []
    for index, member in enumerate(members, start=1):
        address = html.escape(member["address"])
        added_by = html.escape(member["added_by"])
        cards.append(
            f"""<article class="uye-karti">
              <p class="rutbe">Topluluk Üyesi {index}</p>
              <span class="adres">{address}</span>
              <p class="ekleyen">Topluluğa ekleyen
                <span class="ekleyen-adres">{added_by}</span>
              </p>
            </article>"""
        )

    return "\n".join(cards)


class WebHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def end_headers(self):
        # Keep browser refreshes deterministic while the local UI is changing.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        requested_path = self.path.split("?", 1)[0]
        if requested_path not in ("/", "/index.html"):
            super().do_GET()
            return

        template = (WEB_ROOT / "index.html").read_text(encoding="utf-8")

        try:
            management, members = read_local_contract()
            replacements = {
                "{{DURUM}}": "Yönetici, altı konsey üyesi ve topluluk kayıtları Anvil'den okundu.",
                "{{YONETICI}}": f"{management[0][:6]}…{management[0][-4:]}",
                "{{UYE_SAYISI}}": str(len(members)),
                "{{TOPLULUK_KARTLARI}}": member_cards(members),
                "{{GUNCELLEME}}": datetime.now().strftime("%d.%m.%Y %H:%M:%S"),
            }
            for index, address in enumerate(management[1:], start=1):
                replacements[f"{{{{KONSEY_{index}}}}}"] = f"{address[:6]}…{address[-4:]}"
        except Exception as error:
            replacements = {
                "{{DURUM}}": f"Anvil okunamadı: {html.escape(str(error))}",
                "{{YONETICI}}": "Okunamadı",
                "{{UYE_SAYISI}}": "0",
                "{{TOPLULUK_KARTLARI}}": '<p class="bos-liste">Anvil verisi okunamadı.</p>',
                "{{GUNCELLEME}}": "—",
            }
            for index in range(1, 7):
                replacements[f"{{{{KONSEY_{index}}}}}"] = "Okunamadı"

        rendered_page = template
        for token, value in replacements.items():
            rendered_page = rendered_page.replace(token, value)

        response_body = rendered_page.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(response_body)))
        self.end_headers()
        self.wfile.write(response_body)

    def do_POST(self):
        if self.path != "/rpc":
            self.send_error(404, "Not found")
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        request_body = self.rfile.read(content_length)
        upstream_request = Request(
            ANVIL_RPC_URL,
            data=request_body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with urlopen(upstream_request, timeout=10) as response:
                response_body = response.read()
                self.send_response(response.status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(response_body)))
                self.end_headers()
                self.wfile.write(response_body)
        except Exception as error:
            error_body = f'{{"error":"Anvil RPC proxy error: {error}"}}'.encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(error_body)))
            self.end_headers()
            self.wfile.write(error_body)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 8080), WebHandler)
    print("Web UI: http://127.0.0.1:8080")
    print(f"RPC proxy: {ANVIL_RPC_URL}")
    server.serve_forever()
