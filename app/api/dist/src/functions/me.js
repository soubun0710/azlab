"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.me = me;
const functions_1 = require("@azure/functions");
async function me(request, context) {
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
    }
    catch (error) {
        context.error('Failed to decode the SWA client principal.');
        return {
            status: 400,
            jsonBody: { error: 'Invalid SWA client principal.' }
        };
    }
}
functions_1.app.http('me', {
    methods: ['GET'],
    authLevel: 'anonymous',
    route: 'me',
    handler: me
});
