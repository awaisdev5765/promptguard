// HTTP providers for the major model APIs.

import 'dart:convert';
import 'dart:io';

import '../core/pricing.dart';
import 'provider.dart';

/// OpenAI-compatible chat completions. Works with api.openai.com and any
/// compatible endpoint (Groq, Together, OpenRouter, local llama.cpp...).
class OpenAICompatibleProvider extends Provider {
  final String baseUrl;
  final String apiKeyEnv;
  final String Function(String) envLookup;

  OpenAICompatibleProvider({
    required this.baseUrl,
    required this.apiKeyEnv,
    required this.envLookup,
  });

  @override
  Future<CompletionResult> complete({
    required String model,
    required String system,
    required String user,
  }) async {
    final apiKey = envLookup(apiKeyEnv);
    if (apiKey.isEmpty) {
      throw StateError(
          'Missing API key: set $apiKeyEnv in your environment.');
    }

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl/chat/completions'));
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer $apiKey');
      final body = jsonEncode({
        'model': model,
        'messages': [
          if (system.isNotEmpty) {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      });
      request.add(utf8.encode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode} from $baseUrl: '
            '${_clip(text, 300)}');
      }
      final json = jsonDecode(text) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw StateError('No choices in response: ${_clip(text, 300)}');
      }
      final content = ((choices.first as Map)['message'] as Map)['content'] as String;
      return CompletionResult(text: content, usage: usageFromOpenAI(json));
    } finally {
      client.close();
    }
  }
}

/// Anthropic Messages API.
class AnthropicProvider extends Provider {
  final String apiKeyEnv;
  final String Function(String) envLookup;

  AnthropicProvider({required this.apiKeyEnv, required this.envLookup});

  @override
  Future<CompletionResult> complete({
    required String model,
    required String system,
    required String user,
  }) async {
    final apiKey = envLookup(apiKeyEnv);
    if (apiKey.isEmpty) {
      throw StateError('Missing API key: set $apiKeyEnv in your environment.');
    }

    final client = HttpClient();
    try {
      final request =
          await client.postUrl(Uri.parse('https://api.anthropic.com/v1/messages'));
      request.headers.contentType = ContentType.json;
      request.headers.set('x-api-key', apiKey);
      request.headers.set('anthropic-version', '2023-06-01');
      final body = jsonEncode({
        'model': model,
        'max_tokens': 1024,
        if (system.isNotEmpty) 'system': system,
        'messages': [
          {'role': 'user', 'content': user},
        ],
      });
      request.add(utf8.encode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw StateError(
            'HTTP ${response.statusCode} from Anthropic: ${_clip(text, 300)}');
      }
      final json = jsonDecode(text) as Map<String, dynamic>;
      final content = json['content'] as List;
      final message = ((content.first as Map)['text'] ?? '') as String;
      return CompletionResult(text: message, usage: usageFromAnthropic(json));
    } finally {
      client.close();
    }
  }
}

/// Google Gemini generateContent API.
class GeminiProvider extends Provider {
  final String apiKeyEnv;
  final String Function(String) envLookup;

  GeminiProvider({required this.apiKeyEnv, required this.envLookup});

  @override
  Future<CompletionResult> complete({
    required String model,
    required String system,
    required String user,
  }) async {
    final apiKey = envLookup(apiKeyEnv);
    if (apiKey.isEmpty) {
      throw StateError('Missing API key: set $apiKeyEnv in your environment.');
    }

    final client = HttpClient();
    try {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType.json;
      final body = jsonEncode({
        if (system.isNotEmpty)
          'system_instruction': {'parts': [{'text': system}]},
        'contents': [
          {'parts': [{'text': user}]},
        ],
      });
      request.add(utf8.encode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw StateError(
            'HTTP ${response.statusCode} from Gemini: ${_clip(text, 300)}');
      }
      final json = jsonDecode(text) as Map<String, dynamic>;
      final candidates = json['candidates'] as List;
      final parts =
          ((candidates.first as Map)['content'] as Map)['parts'] as List;
      final message = ((parts.first as Map)['text'] ?? '') as String;
      return CompletionResult(text: message, usage: usageFromGemini(json));
    } finally {
      client.close();
    }
  }
}

/// The default registry with the three bundled providers.
ProviderRegistry defaultRegistry(String Function(String) envLookup) {
  final registry = ProviderRegistry(envLookup: envLookup);
  registry.register(
    'openai',
    OpenAICompatibleProvider(
      baseUrl: 'https://api.openai.com/v1',
      apiKeyEnv: 'OPENAI_API_KEY',
      envLookup: envLookup,
    ),
  );
  registry.register(
    'groq',
    OpenAICompatibleProvider(
      baseUrl: 'https://api.groq.com/openai/v1',
      apiKeyEnv: 'GROQ_API_KEY',
      envLookup: envLookup,
    ),
  );
  registry.register(
    'openrouter',
    OpenAICompatibleProvider(
      baseUrl: 'https://openrouter.ai/api/v1',
      apiKeyEnv: 'OPENROUTER_API_KEY',
      envLookup: envLookup,
    ),
  );
  registry.register(
    'anthropic',
    AnthropicProvider(apiKeyEnv: 'ANTHROPIC_API_KEY', envLookup: envLookup),
  );
  registry.register(
    'gemini',
    GeminiProvider(apiKeyEnv: 'GEMINI_API_KEY', envLookup: envLookup),
  );
  return registry;
}

String _clip(String text, int length) =>
    text.length <= length ? text : '${text.substring(0, length)}…';
