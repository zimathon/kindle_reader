import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  // APIキーを保存するためのキー名
  static const String _geminiApiKey = 'gemini_api_key';
  static const String _serpApiKey = 'serp_api_key';
  static const String _googleSearchApiKey = 'google_search_api_key';
  static const String _googleSearchEngineId = 'google_search_engine_id';

  Future<void> saveGeminiApiKey(String apiKey) async {
    await _storage.write(key: _geminiApiKey, value: apiKey);
  }

  Future<String?> getGeminiApiKey() async {
    return await _storage.read(key: _geminiApiKey);
  }

  Future<void> deleteGeminiApiKey() async {
    await _storage.delete(key: _geminiApiKey);
  }

  Future<void> saveSerpApiKey(String apiKey) async {
    await _storage.write(key: _serpApiKey, value: apiKey);
  }

  Future<String?> getSerpApiKey() async {
    return await _storage.read(key: _serpApiKey);
  }

  Future<void> deleteSerpApiKey() async {
    await _storage.delete(key: _serpApiKey);
  }

  // Google Programmable Search API Key
  Future<void> saveGoogleSearchApiKey(String apiKey) async {
    await _storage.write(key: _googleSearchApiKey, value: apiKey);
  }

  Future<String?> getGoogleSearchApiKey() async {
    return await _storage.read(key: _googleSearchApiKey);
  }

  Future<void> deleteGoogleSearchApiKey() async {
    await _storage.delete(key: _googleSearchApiKey);
  }

  // Google Programmable Search Engine ID
  Future<void> saveGoogleSearchEngineId(String engineId) async {
    await _storage.write(key: _googleSearchEngineId, value: engineId);
  }

  Future<String?> getGoogleSearchEngineId() async {
    return await _storage.read(key: _googleSearchEngineId);
  }

  Future<void> deleteGoogleSearchEngineId() async {
    await _storage.delete(key: _googleSearchEngineId);
  }

  // 必要に応じて全てのキーを削除するメソッドなども追加可能
  Future<void> deleteAllApiKeys() async {
    await deleteGeminiApiKey();
    await deleteSerpApiKey();
    await deleteGoogleSearchApiKey();
    await deleteGoogleSearchEngineId();
  }
} 