"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.debugAuth = debugAuth;
const functions_1 = require("@azure/functions");
const tokenHeader = 'x-ms-token-aad-access-token';
function debugAuth(request) {
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
functions_1.app.http('debugAuth', {
    methods: ['GET'],
    authLevel: 'anonymous',
    route: 'debug-auth',
    handler: debugAuth
});
