"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.user = user;
const identity_1 = require("@azure/identity");
const functions_1 = require("@azure/functions");
const graphScope = 'https://graph.microsoft.com/.default';
const tenantId = '98493276-674d-4550-a5d7-552205bd2432';
async function user(request, context) {
    const username = request.query.get('username')?.trim();
    if (!username) {
        return {
            status: 400,
            jsonBody: { error: 'The username query parameter is required.' }
        };
    }
    const authorization = request.headers.get('authorization');
    const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!token) {
        return {
            status: 401,
            jsonBody: { error: 'A delegated Microsoft Graph access token is required.' }
        };
    }
    try {
        const clientId = process.env.ENTRA_CLIENT_ID;
        const clientSecret = process.env.ENTRA_CLIENT_SECRET;
        if (!clientId || !clientSecret) {
            context.error('OBO configuration is incomplete.');
            return {
                status: 500,
                jsonBody: { error: 'The Function OBO configuration is incomplete.' }
            };
        }
        const credential = new identity_1.OnBehalfOfCredential({
            tenantId,
            clientId,
            clientSecret,
            userAssertionToken: token
        });
        const graphAccessToken = await credential.getToken(graphScope);
        if (!graphAccessToken) {
            context.error('Microsoft Graph access token was not returned by the OBO flow.');
            return {
                status: 502,
                jsonBody: { error: 'Failed to acquire a Microsoft Graph access token.' }
            };
        }
        const graphResponse = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(username)}?$select=id,displayName,userPrincipalName,mail`, {
            headers: {
                Authorization: `Bearer ${graphAccessToken.token}`
            }
        });
        if (graphResponse.status === 404) {
            return {
                status: 404,
                jsonBody: { error: 'User not found.' }
            };
        }
        if (!graphResponse.ok) {
            context.error(`Microsoft Graph returned ${graphResponse.status}.`);
            return {
                status: 502,
                jsonBody: { error: 'Microsoft Graph user lookup failed.' }
            };
        }
        const graphUser = (await graphResponse.json());
        return {
            jsonBody: {
                id: graphUser.id,
                displayName: graphUser.displayName,
                userPrincipalName: graphUser.userPrincipalName,
                mail: graphUser.mail
            }
        };
    }
    catch (error) {
        context.error(`Failed to look up the Graph user: ${error instanceof Error ? error.message : String(error)}`);
        return {
            status: 502,
            jsonBody: { error: 'Failed to look up the user.' }
        };
    }
}
functions_1.app.http('user', {
    methods: ['GET'],
    authLevel: 'anonymous',
    route: 'user',
    handler: user
});
