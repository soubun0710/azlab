"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.user = user;
const functions_1 = require("@azure/functions");
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
            jsonBody: { error: 'A Microsoft Graph access token is required.' }
        };
    }
    try {
        const graphResponse = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(username)}?$select=id,displayName,userPrincipalName,mail`, {
            headers: {
                Authorization: `Bearer ${token}`
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
