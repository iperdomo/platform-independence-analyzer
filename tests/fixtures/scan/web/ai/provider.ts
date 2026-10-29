import { customProvider, gateway } from "ai";

export const model = (id: string) => gateway.languageModel(id);
export const options = { providerOptions: { gateway: { order: ["groq", "bedrock"] } } };

// Not the AI Gateway: an API-gateway config block and a word in prose.
export const apiGateway = { gateway: { port: 8080 } };
// The payment gateway times out after 30s.
