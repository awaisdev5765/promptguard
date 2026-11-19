// Provider abstraction: how a test reaches a model.

import 'dart:io';

import '../core/pricing.dart';

/// The output of one provider call: text plus token usage.
class CompletionResult {
  final String text;
  final TokenUsage? usage;

  CompletionResult({required this.text, this.usage});
}

/// Sends a chat-style request to a provider and returns the model output.
abstract class Provider {
  Future<CompletionResult> complete({
    required String model,
    required String system,
    required String user,
  });
}

/// Provider registry: `openai:gpt-4o-mini` style model refs.
class ProviderRegistry {
  final Map<String, Provider> _providers = {};
  final String Function(String envName) envLookup;

  ProviderRegistry({String Function(String envName)? envLookup})
      : envLookup = envLookup ?? _defaultEnv;

  static String _defaultEnv(String name) => Platform.environment[name] ?? '';

  /// Registers a provider under a scheme prefix.
  void register(String scheme, Provider provider) {
    _providers[scheme] = provider;
  }

  /// Resolves `scheme:model` to a provider + bare model name.
  (Provider, String) resolve(String modelRef) {
    final index = modelRef.indexOf(':');
    if (index <= 0) {
      throw StateError(
          'Model refs look like "openai:gpt-4o-mini" — got "$modelRef"');
    }
    final scheme = modelRef.substring(0, index);
    final model = modelRef.substring(index + 1);
    final provider = _providers[scheme];
    if (provider == null) {
      throw StateError('No provider registered for "$scheme:" (in "$modelRef"). '
          'Supported: ${_providers.keys.join(', ')}');
    }
    return (provider, model);
  }
}
