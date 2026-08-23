"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.hello = hello;
const functions_1 = require("@azure/functions");
async function hello(request, context) {
    context.log('hello function invoked');
    return {
        jsonBody: {
            message: 'Hello from Azure Functions',
            runtime: process.version,
            method: request.method,
            utc: new Date().toISOString()
        }
    };
}
functions_1.app.http('hello', {
    methods: ['GET'],
    authLevel: 'anonymous',
    route: 'hello',
    handler: hello
});
