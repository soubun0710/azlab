import { app, HttpRequest, HttpResponseInit } from '@azure/functions';

const tokenHeader = 'x-ms-token-aad-access-token';

export function debugAuth(request: HttpRequest): HttpResponseInit {
  const token = request.headers.get(tokenHeader);
  const clientPrincipal = request.headers.get('x-ms-client-principal');
  const headerNames = Array.from(request.headers.keys())
    .filter((name) => name.toLowerCase().startsWith('x-ms-'))
    .sort();

  return {
    jsonBody: {
      tokenHeader: {
        name: tokenHeader,
        present: Boolean(token),
        length: token?.length ?? 0,
        looksLikeJwt: token ? token.split('.').length === 3 : false
      },
      clientPrincipal: {
        present: Boolean(clientPrincipal),
        length: clientPrincipal?.length ?? 0
      },
      forwardedMsHeaders: headerNames
    }
  };
}

app.http('debugAuth', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'debug-auth',
  handler: debugAuth
});