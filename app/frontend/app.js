const status = document.querySelector('#status');
const user = document.querySelector('#user');
const result = document.querySelector('#result');
const searchForm = document.querySelector('#user-search-form');

const tenantId = '98493276-674d-4550-a5d7-552205bd2432';
const clientId = '7dea1e23-c64e-4b20-a5d5-dfe01eb0cca0';
const apiScope = `api://${clientId}/user_impersonation`;
const msalInstance = new msal.PublicClientApplication({
  auth: {
    clientId,
    authority: `https://login.microsoftonline.com/${tenantId}`,
    redirectUri: window.location.origin
  },
  cache: {
    cacheLocation: 'sessionStorage'
  }
});

async function getApiAccessToken() {
  let account = msalInstance.getActiveAccount() || msalInstance.getAllAccounts()[0];

  if (!account) {
    const loginResult = await msalInstance.loginPopup({ scopes: [apiScope] });
    account = loginResult.account;
    msalInstance.setActiveAccount(account);
  }

  try {
    const tokenResult = await msalInstance.acquireTokenSilent({
      account,
      scopes: [apiScope]
    });
    return tokenResult.accessToken;
  } catch {
    const tokenResult = await msalInstance.acquireTokenPopup({
      account,
      scopes: [apiScope]
    });
    return tokenResult.accessToken;
  }
}

async function loadAuthenticationState() {
  const authResponse = await fetch('/.auth/me');
  const authData = await authResponse.json();
  user.textContent = `SWA認証情報:\n${JSON.stringify(authData, null, 2)}`;

  if (!authData.clientPrincipal) {
    status.textContent = 'Entra IDへログインしてください。';
    return;
  }

  const meResponse = await fetch('/api/me');
  const meBody = await meResponse.text();
  if (!meResponse.ok) {
    throw new Error(`User API returned ${meResponse.status}: ${meBody || 'empty response'}`);
  }

  let meData;
  try {
    meData = JSON.parse(meBody);
  } catch {
    throw new Error(`User API returned invalid JSON: ${meBody || 'empty response'}`);
  }

  status.textContent = 'SWA認証とFunctionへのユーザー情報連携に成功しました。';
  result.textContent = JSON.stringify(meData, null, 2);
}

searchForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const username = new FormData(searchForm).get('username').trim();

  status.textContent = 'Graphアクセストークンを取得しています...';
  result.textContent = '';

  try {
    const accessToken = await getApiAccessToken();
    const response = await fetch(`/api/user?username=${encodeURIComponent(username)}`, {
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${accessToken}`
      }
    });
    const body = await response.text();
    if (!response.ok) {
      throw new Error(`User search returned ${response.status}: ${body || 'empty response'}`);
    }

    result.textContent = JSON.stringify(JSON.parse(body), null, 2);
    status.textContent = 'ユーザー検索に成功しました。';
  } catch (error) {
    status.textContent = 'ユーザー検索に失敗しました。';
    result.textContent = error instanceof Error ? error.message : String(error);
  }
});

loadAuthenticationState().catch((error) => {
  status.textContent = '認証状態の確認に失敗しました。';
  result.textContent = error.message;
});
