import 'dart:convert'; // JSONエンコード/デコード用

// import 'package:flutter_gemini/flutter_gemini.dart'; // 不要になるため削除
import 'package:google_generative_ai/google_generative_ai.dart'; // google_generative_ai をインポート
import 'package:kindle_reader/utils/logger.dart';

class LlmService {
  final String? _apiKey;
  GenerativeModel? _model;

  LlmService({required String? apiKey}) : _apiKey = apiKey {
    if (_apiKey != null && _apiKey.isNotEmpty) {
      _model = GenerativeModel(model: 'models/gemini-2.0-flash', apiKey: _apiKey);
      // _listAvailableModels(); // モデルリスト取得は一旦コメントアウト
    } else {
      printWithTimestamp('LlmService: APIキーが設定されていません。');
      // APIキーがない場合、_model は null のままになります。
      // 呼び出し側で _model が null でないことを確認する必要があります。
    }
  }

  // 利用可能なモデルをリストアップするメソッド (デバッグ用)
  // Future<void> _listAvailableModels() async {
  //   if (_apiKey == null || _apiKey!.isEmpty) {
  //     // ignore: avoid_print
  //     print('LlmService: APIキーがないため、モデルリストを取得できません。');
  //     return;
  //   }
  //   try {
  //     // ignore: avoid_print
  //     print('LlmService: 利用可能なモデルを問い合わせています...');
  //     // final client = GenerativeLanguageAPI(apiKey: _apiKey!); // この行は不要
  //     // GenerativeModel.listModels() 静的メソッドを使用 (APIキーが必要)
  //     // final response = await GenerativeModel.listModels(apiKey: _apiKey!);
  //     // ignore: avoid_print
  //     // print('LlmService: 利用可能なモデルリスト:');
  //     // response は List<Model> 型だと想定される (実際の型は要確認)
  //     // for (final modelInfo in response) { // モデル情報の型に合わせて調整
  //     //   // ignore: avoid_print
  //     //   print('  名前: ${modelInfo.name}');
  //     //   // ignore: avoid_print
  //     //   print('    バージョン: ${modelInfo.version}');
  //     //   // ignore: avoid_print
  //     //   print('    表示名: ${modelInfo.displayName}');
  //     //   // ignore: avoid_print
  //     //   print('    説明: ${modelInfo.description?.replaceAll("\n", " ")}'); // description は nullable かも
  //     //   // ignore: avoid_print
  //     //   print('    サポートメソッド: ${modelInfo.supportedGenerationMethods}');
  //     //   // ignore: avoid_print
  //     //   print('    入力トークン上限: ${modelInfo.inputTokenLimit}');
  //     //   // ignore: avoid_print
  //     //   print('    出力トークン上限: ${modelInfo.outputTokenLimit}');
  //     //   // ignore: avoid_print
  //     //   // print('    温度制御サポート: ${modelInfo.temperature}'); // ModelInfo に temperature があるか確認
  //     //   // ignore: avoid_print
  //     //   // print('    TopPサポート: ${modelInfo.topP}'); // ModelInfo に topP があるか確認
  //     //   // ignore: avoid_print
  //     //   // print('    TopKサポート: ${modelInfo.topK}'); // ModelInfo に topK があるか確認
  //     //   // ignore: avoid_print
  //     //   print('--------------------------------------------------');
  //     // }
  //   } catch (e,s) {
  //     // ignore: avoid_print
  //     print('LlmService: モデルリストの取得中にエラー: $e');
  //     print('スタックトレース: $s');
  //   }
  // }

  Future<Map<String, String>> fetchBookInfoFromLlm(String bookTitle) async {
    if (_model == null) {
      // ignore: avoid_print
      print('LlmService: モデルが初期化されていません（APIキーがありません）。');
      throw Exception('LLMサービスが初期化されていません。APIキーを確認してください。');
    }

    final promptString = '''書籍「$bookTitle」について、以下の情報をJSON形式で教えてください。
{
  "genre": "(ここに書籍の主なジャンル)",
  "cover_image_keywords": "(ここにカバー画像を生成するためのキーワードや簡単な説明、3つ程度)"
}''';
    // ignore: avoid_print
    printWithTimestamp('LlmService: 送信するプロンプト:\n$promptString');

    try {
      final content = [Content.text(promptString)];
      // ignore: avoid_print
      printWithTimestamp('LlmService: model.generateContent() を呼び出します。');
      final response = await _model!.generateContent(content);
      // ignore: avoid_print
      printWithTimestamp('LlmService: APIからレスポンスを受け取りました。');

      if (response.text != null) {
        final String rawJsonText = response.text!;
        // ignore: avoid_print
        printWithTimestamp('LlmService: レスポンス テキスト: $rawJsonText');
        final cleanedJsonText = rawJsonText.replaceAll("```json", "").replaceAll("```", "").trim();
        
        try {
          final Map<String, dynamic> parsedJson = jsonDecode(cleanedJsonText);
          return {
            'genre': parsedJson['genre']?.toString() ?? '不明',
            'keywords': parsedJson['cover_image_keywords']?.toString() ?? 'キーワードなし',
          };
        } catch (e) {
          // ignore: avoid_print
          printWithTimestamp('JSONパースエラー: $e');
          printWithTimestamp('パースしようとした文字列: $cleanedJsonText');
          return {
            'genre': 'パース失敗',
            'keywords': 'パース失敗',
          };
        }
      } else {
        // ignore: avoid_print
        printWithTimestamp('LLM APIエラー: レスポンスのtextがnullです。response: ${response.toString()}');
        throw Exception('LLMからの情報取得に失敗しました。レスポンスが空です。');
      }
    // google_generative_ai パッケージがスローする可能性のある例外をキャッチ
    // 具体的な例外の型はドキュメントや実際の試行で確認してください。
    // 例として GenerativeAIException や HttpException が考えられます。
    } on GenerativeAIException catch (e, s) { 
      // ignore: avoid_print
      printWithTimestamp('google_generative_ai APIエラー (GenerativeAIException): $e');
      // ignore: avoid_print
      printWithTimestamp('スタックトレース: $s');
      throw Exception('LLM API呼び出し中に GenerativeAIException が発生しました: $e');
    } catch (e, s) {
      // ignore: avoid_print
      printWithTimestamp('LLM APIエラー (その他の例外): $e');
      // ignore: avoid_print
      printWithTimestamp('スタックトレース: $s');
      throw Exception('LLM API呼び出し中に予期せぬエラーが発生しました: $e');
    }
  }

  Future<String> generateImageSearchQuery(String title, String authors) async {
    // LLMへの問い合わせ処理を削除し、固定のクエリ形式を使用する
    final searchQuery = '"$title" book cover';
    printWithTimestamp('LlmService: 生成された画像検索クエリ (固定): $searchQuery');
    return searchQuery;
    /*  // 元のLLM呼び出し部分はコメントアウトまたは削除
    if (_model == null) {
      // ignore: avoid_print
      printWithTimestamp('LlmService: モデルが初期化されていません（APIキーがありません）。');
      throw Exception('LLMサービスが初期化されていません。APIキーを確認してください。');
    }

    // 著者名はプロンプト内では参考情報として残すが、基本クエリからは一旦外す
    final authorPromptPart = authors.isNotEmpty ? "著者名「$authors」も参考にしてください。" : "";
    // 基本の検索クエリを書籍タイトルのみにする
    final baseQuery = '"$title" book cover'; 
    
    final promptString = '''書籍タイトル「$title」について、オンラインでカバー画像や関連画像を検索するための、効果的な英語の検索クエリを生成してください。
$authorPromptPart
基本の検索クエリの形式は「$baseQuery」とします。
この基本クエリに、必要に応じて関連性の高いキーワードを追加したり、語順を調整するなどして、最も公式で高品質なカバー画像が見つかりやすいと思われる最終的な英語の検索クエリを1つだけ、文字列として返してください。
余計な説明や前置き、引用符は不要です。最終的なクエリ文字列のみを返してください。''';
    // ignore: avoid_print
    printWithTimestamp('LlmService: 画像検索クエリ生成プロンプト:\n$promptString');

    try {
      final content = [Content.text(promptString)];
      final response = await _model!.generateContent(content);

      if (response.text != null && response.text!.isNotEmpty) {
        final String searchQueryResponse = response.text!.trim();
        // ignore: avoid_print
        printWithTimestamp('LlmService: 生成された画像検索クエリ: $searchQueryResponse');
        return searchQueryResponse;
      } else {
        // ignore: avoid_print
        printWithTimestamp('LLM APIエラー: 画像検索クエリの生成に失敗しました。レスポンスが空かnullです。');
        throw Exception('LLMからの画像検索クエリ生成に失敗しました。');
      }
    } on GenerativeAIException catch (e, s) {
      // ignore: avoid_print
      printWithTimestamp('google_generative_ai APIエラー (GenerativeAIException) - 画像検索クエリ生成時: $e');
      // ignore: avoid_print
      printWithTimestamp('スタックトレース: $s');
      throw Exception('LLM API (画像検索クエリ生成) で GenerativeAIException が発生しました: $e');
    } catch (e, s) {
      // ignore: avoid_print
      printWithTimestamp('LLM APIエラー (その他の例外) - 画像検索クエリ生成時: $e');
      // ignore: avoid_print
      printWithTimestamp('スタックトレース: $s');
      throw Exception('LLM API (画像検索クエリ生成) で予期せぬエラーが発生しました: $e');
    }
    */
  }
} 