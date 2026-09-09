const status = document.querySelector('#status');
const user = document.querySelector('#user');
const userSearch = document.querySelector('#user-search');
const username = document.querySelector('#username');
const result = document.querySelector('#result');

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
  userSearch.hidden = false;
  result.textContent = JSON.stringify(meData, null, 2);
}

userSearch.addEventListener('submit', async (event) => {
  event.preventDefault();
  const value = username.value.trim();

  if (!value) {
    return;
  }

  result.textContent = 'Graphで検索しています...';

  try {
    const response = await fetch(`/api/user?username=${encodeURIComponent(value)}`);
    const body = await response.text();

    if (!response.ok) {
      throw new Error(`Graph user lookup returned ${response.status}: ${body || 'empty response'}`);
    }

    result.textContent = JSON.stringify(JSON.parse(body), null, 2);
  } catch (error) {
    result.textContent = error instanceof Error ? error.message : String(error);
  }
});

loadAuthenticationState().catch((error) => {
  status.textContent = '認証状態の確認に失敗しました。';
  result.textContent = error.message;
});
