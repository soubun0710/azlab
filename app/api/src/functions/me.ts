import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';

export async function me(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  const encodedPrincipal = request.headers.get('x-ms-client-principal');

  if (!encodedPrincipal) {
    return {
      status: 401,
      jsonBody: { error: 'Authenticated SWA user information was not provided.' }
    };
  }

  try {
    const principal = JSON.parse(Buffer.from(encodedPrincipal, 'base64').toString('utf8'));

    return {
      jsonBody: {
        identityProvider: principal.identityProvider,
        userId: principal.userId,
        userDetails: principal.userDetails,
        userRoles: principal.userRoles
      }
    };
  } catch (error) {
    context.error('Failed to decode the SWA client principal.');

    return {
      status: 400,
      jsonBody: { error: 'Invalid SWA client principal.' }
    };
  }
}

app.http('me', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'me',
  handler: me
});