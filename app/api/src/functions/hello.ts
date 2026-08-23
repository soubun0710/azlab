import { app, HttpRequest, HttpResponseInit, InvocationContext } from '@azure/functions';

export async function hello(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
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

app.http('hello', {
  methods: ['GET'],
  authLevel: 'anonymous',
  route: 'hello',
  handler: hello
});
