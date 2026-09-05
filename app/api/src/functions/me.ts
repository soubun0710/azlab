import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';

export async function me(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  try {
    const encodedPrincipal = request.headers.get('x-ms-client-principal');

    if (!encodedPrincipal) {
      return {
        status: 401,
        jsonBody: { error: 'Authenticated SWA user information was not provided.' }
      };
    }

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
    context.error(`Failed to process the SWA client principal: ${error instanceof Error ? error.message : String(error)}`);

    return {
      status: 400,
      jsonBody: { error: 'Failed to process the SWA client principal.' }
    };
  }
}

app.http('me', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'me',
  handler: me
});