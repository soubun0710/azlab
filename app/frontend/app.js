const status = document.querySelector('#status');
const result = document.querySelector('#result');

fetch('/api/hello')
  .then((response) => {
    if (!response.ok) {
      throw new Error(`API returned ${response.status}`);
    }
    return response.json();
  })
  .then((data) => {
    status.textContent = 'Function APIとの接続に成功しました。';
    result.textContent = JSON.stringify(data, null, 2);
  })
  .catch((error) => {
    status.textContent = 'Function APIへ接続できませんでした。';
    result.textContent = error.message;
  });
