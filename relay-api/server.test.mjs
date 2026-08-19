import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { Wallet } from 'ethers';

import { canonicalResponseMessage, createRelayServer } from './server.mjs';

let server;
let baseUrl;

before(async () => {
  server = createRelayServer({
    verifyMerchant: async () => ({ merchantName: 'Relay Dondurma', merchantCategory: 'Dondurma' }),
  });
  await new Promise((resolve, reject) => {
    const onError = (error) => reject(error);
    server.once('error', onError);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', onError);
      resolve();
    });
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.closeAllConnections();
  server.close();
});

test('işletme alıcıya istek yollar ve kabul işlemini yakalar', async () => {
  const recipientWallet = Wallet.createRandom();
  const recipientAddress = recipientWallet.address;
  const input = {
    merchantId: 1,
    merchantAddress: '0x1111111111111111111111111111111111111111',
    recipientAddress,
    amount: '12.5',
    amountWei: '12500000000000000000',
    nonce: '12345678-1234-1234-1234-123456789012',
    expiresAt: Date.now() + 120_000,
    message: 'signed relay payment request',
    signature: `0x${'11'.repeat(65)}`,
  };

  const createdResponse = await fetch(`${baseUrl}/v1/payment-requests`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(input),
  });
  assert.equal(createdResponse.status, 201);
  const created = await createdResponse.json();
  assert.equal(created.merchantName, 'Relay Dondurma');

  const currentResponse = await fetch(`${baseUrl}/v1/payment-requests/recipient/${recipientAddress}/current`);
  assert.equal(currentResponse.status, 200);
  assert.equal((await currentResponse.json()).amount, '12.5');

  const forgedWallet = Wallet.createRandom();
  const forgedMessage = canonicalResponseMessage({ requestId: created.id, recipientAddress, action: 'rejected', transactionHash: '' });
  const forgedResponse = await fetch(`${baseUrl}/v1/payment-requests/${created.id}/respond`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      action: 'rejected',
      recipientAddress,
      message: forgedMessage,
      signature: await forgedWallet.signMessage(forgedMessage),
    }),
  });
  assert.equal(forgedResponse.status, 400);

  const transactionHash = `0x${'22'.repeat(32)}`;
  const responseMessage = canonicalResponseMessage({ requestId: created.id, recipientAddress, action: 'accepted', transactionHash });
  const acceptedResponse = await fetch(`${baseUrl}/v1/payment-requests/${created.id}/respond`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      action: 'accepted',
      recipientAddress,
      transactionHash,
      message: responseMessage,
      signature: await recipientWallet.signMessage(responseMessage),
    }),
  });
  assert.equal(acceptedResponse.status, 200);
  assert.equal((await acceptedResponse.json()).status, 'accepted');
  assert.equal((await fetch(`${baseUrl}/v1/payment-requests/recipient/${recipientAddress}/current`)).status, 404);
});

test('reddedilen istek işlem hash istemez', async () => {
  const recipientWallet = Wallet.createRandom();
  const recipientAddress = recipientWallet.address;
  const input = {
    merchantId: 1,
    merchantAddress: '0x1111111111111111111111111111111111111111',
    recipientAddress,
    amount: '2',
    amountWei: '2000000000000000000',
    nonce: '22345678-1234-1234-1234-123456789012',
    expiresAt: Date.now() + 120_000,
    message: 'signed relay payment request',
    signature: `0x${'11'.repeat(65)}`,
  };
  const created = await (await fetch(`${baseUrl}/v1/payment-requests`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(input),
  })).json();
  const responseMessage = canonicalResponseMessage({ requestId: created.id, recipientAddress, action: 'rejected', transactionHash: '' });
  const response = await fetch(`${baseUrl}/v1/payment-requests/${created.id}/respond`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'rejected', recipientAddress, message: responseMessage, signature: await recipientWallet.signMessage(responseMessage) }),
  });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).status, 'rejected');
});

test('geçersiz istek reddedilir', async () => {
  const response = await fetch(`${baseUrl}/v1/payment-requests`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ merchantId: 0 }),
  });
  assert.equal(response.status, 400);
});
