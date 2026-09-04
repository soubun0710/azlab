const status = document.querySelector('#status');
const user = document.querySelector('#user');
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
  const meData = await meResponse.json();
  if (!meResponse.ok) {
    throw new Error(`User API returned ${meResponse.status}`);
  }

  status.textContent = 'SWA認証とFunctionへのユーザー情報連携に成功しました。';
  result.textContent = JSON.stringify(meData, null, 2);
}

loadAuthenticationState().catch((error) => {
  status.textContent = '認証状態の確認に失敗しました。';
  result.textContent = error.message;
});
