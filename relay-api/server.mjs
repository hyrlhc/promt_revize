import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { Contract, JsonRpcProvider, getAddress, verifyMessage } from 'ethers';

const CHAIN_ID = 84532;
const RPC_URL = process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia-rpc.publicnode.com';
const MERCHANT_MAP = process.env.ISLETME_HARITASI_ADDRESS || '0xea004DbD58F988da2752388cf80D1e0dDB5777ed';
const MERCHANT_IDENTITY = process.env.ISLETME_KIMLIGI_ADDRESS || '0x980D6c0949c376523940AfDfE0B6D9Fc3b34141F';
const ADDRESS = /^0x[0-9a-fA-F]{40}$/;
const HASH = /^0x[0-9a-fA-F]{64}$/;
const SIGNATURE = /^0x[0-9a-fA-F]{130}$/;
const INTEGER = /^\d+$/;
const MAX_BODY_BYTES = 64 * 1024;

const provider = new JsonRpcProvider(RPC_URL, { chainId: CHAIN_ID, name: 'Base Sepolia' }, { staticNetwork: true });
const identityContract = new Contract(
  MERCHANT_IDENTITY,
  ['function dogrulanmisIsletmeMi(address hesap) view returns (bool)'],
  provider,
);
const merchantContract = new Contract(
  MERCHANT_MAP,
  ['function isletmeBilgisi(uint256) view returns (tuple(address odemeAdresi,string ad,string kategori,int32 enlemE6,int32 boylamE6,bytes32 kayitKimligi,bool onayli,bool aktif))'],
  provider,
);

function canonicalMessage(input) {
  return [
    'RELAY_PAYMENT_REQUEST_V1',
    `chainId=${CHAIN_ID}`,
    `merchantId=${input.merchantId}`,
    `merchantAddress=${input.merchantAddress.toLowerCase()}`,
    `recipientAddress=${input.recipientAddress.toLowerCase()}`,
    `amountWei=${input.amountWei}`,
    `nonce=${input.nonce}`,
    `expiresAt=${input.expiresAt}`,
  ].join('\n');
}

export function canonicalResponseMessage(input) {
  return [
    'RELAY_PAYMENT_RESPONSE_V1',
    `chainId=${CHAIN_ID}`,
    `requestId=${input.requestId}`,
    `recipientAddress=${input.recipientAddress.toLowerCase()}`,
    `action=${input.action}`,
    `transactionHash=${(input.transactionHash || '').toLowerCase()}`,
  ].join('\n');
}

async function verifyMerchantOnChain(input) {
  if (canonicalMessage(input) !== input.message) throw new Error('Ödeme isteği içeriği değiştirilmiş.');
  const signer = getAddress(verifyMessage(input.message, input.signature));
  if (signer !== getAddress(input.merchantAddress)) throw new Error('İşletme imzası geçersiz.');
  if (!(await identityContract.dogrulanmisIsletmeMi(signer))) throw new Error('Doğrulanmış işletme NFT yetkisi bulunamadı.');

  const merchant = await merchantContract.isletmeBilgisi(input.merchantId);
  if (getAddress(merchant.odemeAdresi) !== signer || !merchant.onayli || !merchant.aktif) {
    throw new Error('İşletme haritada aktif değil.');
  }
  return { merchantName: String(merchant.ad), merchantCategory: String(merchant.kategori) };
}

function json(response, status, body) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'content-type',
    'cache-control': 'no-store',
  });
  response.end(status === 204 ? undefined : JSON.stringify(body));
}

async function readJson(request) {
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new Error('İstek gövdesi çok büyük.');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function validRequest(input) {
  const now = Date.now();
  return input
    && Number.isSafeInteger(input.merchantId)
    && input.merchantId > 0
    && ADDRESS.test(input.merchantAddress)
    && ADDRESS.test(input.recipientAddress)
    && typeof input.amount === 'string'
    && /^\d+(\.\d{1,18})?$/.test(input.amount)
    && INTEGER.test(input.amountWei)
    && BigInt(input.amountWei) > 0n
    && typeof input.nonce === 'string'
    && input.nonce.length >= 16
    && Number.isSafeInteger(input.expiresAt)
    && input.expiresAt > now
    && input.expiresAt <= now + 10 * 60 * 1000
    && typeof input.message === 'string'
    && input.message.length <= 1000
    && SIGNATURE.test(input.signature);
}

export function createRelayServer({ verifyMerchant = verifyMerchantOnChain } = {}) {
  const requests = new Map();
  const activeByRecipient = new Map();

  return createServer(async (request, response) => {
    if (request.method === 'OPTIONS') return json(response, 204, {});
    const url = new URL(request.url ?? '/', 'http://relay.local');

    try {
      if (request.method === 'GET' && url.pathname === '/health') {
        return json(response, 200, { ok: true, service: 'relay-payment-relay', chainId: CHAIN_ID });
      }

      if (request.method === 'POST' && url.pathname === '/v1/payment-requests') {
        const input = await readJson(request);
        if (!validRequest(input)) return json(response, 400, { error: 'Geçersiz ödeme isteği.' });
        const verified = await verifyMerchant(input);

        const id = randomUUID();
        const paymentRequest = {
          id,
          chainId: CHAIN_ID,
          merchantId: input.merchantId,
          merchantAddress: getAddress(input.merchantAddress),
          merchantName: verified.merchantName,
          merchantCategory: verified.merchantCategory,
          recipientAddress: getAddress(input.recipientAddress),
          amount: input.amount,
          amountWei: input.amountWei,
          nonce: input.nonce,
          expiresAt: input.expiresAt,
          message: input.message,
          signature: input.signature,
          status: 'open',
          createdAt: Date.now(),
        };
        const recipientKey = paymentRequest.recipientAddress.toLowerCase();
        const previousId = activeByRecipient.get(recipientKey);
        if (previousId && requests.has(previousId)) requests.get(previousId).status = 'replaced';
        requests.set(id, paymentRequest);
        activeByRecipient.set(recipientKey, id);
        return json(response, 201, paymentRequest);
      }

      const recipientMatch = url.pathname.match(/^\/v1\/payment-requests\/recipient\/(0x[0-9a-f]{40})\/current$/i);
      if (request.method === 'GET' && recipientMatch) {
        const recipientKey = recipientMatch[1].toLowerCase();
        const id = activeByRecipient.get(recipientKey);
        const paymentRequest = id ? requests.get(id) : null;
        if (!paymentRequest || paymentRequest.status !== 'open' || paymentRequest.expiresAt <= Date.now()) {
          if (id) activeByRecipient.delete(recipientKey);
          return json(response, 404, { error: 'Açık ödeme isteği yok.' });
        }
        return json(response, 200, paymentRequest);
      }

      const responseMatch = url.pathname.match(/^\/v1\/payment-requests\/([0-9a-f-]+)\/respond$/i);
      if (request.method === 'POST' && responseMatch) {
        const paymentRequest = requests.get(responseMatch[1]);
        if (!paymentRequest) return json(response, 404, { error: 'Ödeme isteği bulunamadı.' });
        if (paymentRequest.status !== 'open') return json(response, 409, { error: 'Ödeme isteği artık açık değil.' });
        const input = await readJson(request);
        if (input.action !== 'accepted' && input.action !== 'rejected') {
          return json(response, 400, { error: 'Geçersiz ödeme cevabı.' });
        }
        if (!ADDRESS.test(input.recipientAddress) || getAddress(input.recipientAddress) !== paymentRequest.recipientAddress) {
          return json(response, 400, { error: 'Alıcı cüzdanı eşleşmiyor.' });
        }
        if (input.action === 'accepted' && !HASH.test(input.transactionHash)) {
          return json(response, 400, { error: 'İşlem hash bilgisi eksik.' });
        }
        const expectedResponseMessage = canonicalResponseMessage({
          requestId: paymentRequest.id,
          recipientAddress: input.recipientAddress,
          action: input.action,
          transactionHash: input.action === 'accepted' ? input.transactionHash : '',
        });
        if (input.message !== expectedResponseMessage || !SIGNATURE.test(input.signature)) {
          return json(response, 400, { error: 'Alıcı cevabı imzası eksik veya değiştirilmiş.' });
        }
        if (getAddress(verifyMessage(input.message, input.signature)) !== paymentRequest.recipientAddress) {
          return json(response, 400, { error: 'Alıcı cevabı imzası geçersiz.' });
        }

        paymentRequest.status = input.action;
        paymentRequest.transactionHash = input.action === 'accepted' ? input.transactionHash : undefined;
        paymentRequest.respondedAt = Date.now();
        activeByRecipient.delete(paymentRequest.recipientAddress.toLowerCase());
        return json(response, 200, paymentRequest);
      }

      const idMatch = url.pathname.match(/^\/v1\/payment-requests\/([0-9a-f-]+)$/i);
      if (request.method === 'GET' && idMatch) {
        const paymentRequest = requests.get(idMatch[1]);
        if (!paymentRequest) return json(response, 404, { error: 'Ödeme isteği bulunamadı.' });
        return json(response, 200, paymentRequest);
      }

      return json(response, 404, { error: 'Yol bulunamadı.' });
    } catch (error) {
      return json(response, 400, { error: error instanceof Error ? error.message : 'İstek işlenemedi.' });
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT || 8787);
  const host = process.env.HOST || '0.0.0.0';
  createRelayServer().listen(port, host, () => {
    console.log(`Relay payment relay http://${host}:${port}`);
  });
}
