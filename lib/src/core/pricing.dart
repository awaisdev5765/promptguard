// Token usage and cost accounting for runs.

/// Usage numbers from one provider call.
class TokenUsage {
  final int promptTokens;
  final int completionTokens;

  TokenUsage({required this.promptTokens, required this.completionTokens});

  int get totalTokens => promptTokens + completionTokens;
}

/// Pricing per 1M tokens (USD) for cost estimation.
class ModelPricing {
  final double inputPerMillion;
  final double outputPerMillion;

  const ModelPricing({required this.inputPerMillion, required this.outputPerMillion});

  double cost(TokenUsage usage) =>
      usage.promptTokens / 1e6 * inputPerMillion +
      usage.completionTokens / 1e6 * outputPerMillion;
}

/// Well-known model prices (per 1M tokens, USD). Defaults applied when a
/// model is unknown; users can override in promptguard.yaml under `pricing`.
const knownPricing = <String, ModelPricing>{
  'gpt-4o': ModelPricing(inputPerMillion: 2.50, outputPerMillion: 10.00),
  'gpt-4o-mini': ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.60),
  'gpt-4.1-mini': ModelPricing(inputPerMillion: 0.40, outputPerMillion: 1.60),
  'o4-mini': ModelPricing(inputPerMillion: 1.10, outputPerMillion: 4.40),
  'claude-3-5-haiku': ModelPricing(inputPerMillion: 0.80, outputPerMillion: 4.00),
  'claude-sonnet-4': ModelPricing(inputPerMillion: 3.00, outputPerMillion: 15.00),
  'gemini-2.0-flash': ModelPricing(inputPerMillion: 0.10, outputPerMillion: 0.40),
  'gemini-1.5-flash': ModelPricing(inputPerMillion: 0.075, outputPerMillion: 0.30),
  'llama-3.1-8b': ModelPricing(inputPerMillion: 0.05, outputPerMillion: 0.08),
  'llama-3.3-70b': ModelPricing(inputPerMillion: 0.59, outputPerMillion: 0.79),
};

/// Extracts usage from an OpenAI-compatible response JSON.
TokenUsage? usageFromOpenAI(Map<String, dynamic> json) {
  final usage = json['usage'];
  if (usage is! Map) return null;
  return TokenUsage(
    promptTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
    completionTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
  );
}

/// Extracts usage from an Anthropic response JSON.
TokenUsage? usageFromAnthropic(Map<String, dynamic> json) {
  return TokenUsage(
    promptTokens: (json['input_tokens'] as num?)?.toInt() ?? 0,
    completionTokens: (json['output_tokens'] as num?)?.toInt() ?? 0,
  );
}

/// Extracts usage from a Gemini response JSON.
TokenUsage? usageFromGemini(Map<String, dynamic> json) {
  final usage = json['usageMetadata'];
  if (usage is! Map) return null;
  return TokenUsage(
    promptTokens: (usage['promptTokenCount'] as num?)?.toInt() ?? 0,
    completionTokens: (usage['candidatesTokenCount'] as num?)?.toInt() ?? 0,
  );
}
