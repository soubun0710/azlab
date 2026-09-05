"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getRoles = getRoles;
const functions_1 = require("@azure/functions");
async function getRoles(request, context) {
    if (request.method !== 'POST') {
        return { status: 405 };
    }
    const payload = (await request.json());
    const objectId = payload.claims?.find((claim) => claim.typ === 'http://schemas.microsoft.com/identity/claims/objectidentifier')?.val;
    if (!payload.accessToken || !objectId) {
        return {
            status: 400,
            jsonBody: { error: 'The SWA role source payload is missing accessToken or object identifier.' }
        };
    }
    const graphResponse = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(objectId)}?$select=id,displayName,userPrincipalName,mail`, {
        headers: {
            Authorization: `Bearer ${payload.accessToken}`
        }
    });
    if (!graphResponse.ok) {
        context.error(`Microsoft Graph returned ${graphResponse.status}.`);
        return {
            status: 502,
            jsonBody: { error: 'Microsoft Graph user lookup failed.' }
        };
    }
    const user = (await graphResponse.json());
    context.log(`Microsoft Graph user lookup succeeded for ${user.id ?? objectId}.`);
    return {
        jsonBody: {
            roles: ['authenticated']
        }
    };
}
functions_1.app.http('getRoles', {
    methods: ['POST'],
    authLevel: 'anonymous',
    route: 'getroles',
    handler: getRoles
});
