import 'package:dio/dio.dart';
import 'package:kindle_reader/utils/logger.dart';

class ImageSearchService {
  final Dio _dio;
  final String? apiKey;
  final String? searchEngineId;

  ImageSearchService({this.apiKey, this.searchEngineId, Dio? dio}) : _dio = dio ?? Dio();

  Future<List<String>> searchImages(String query, {int numResults = 10}) async {
    if (apiKey == null || apiKey!.isEmpty || searchEngineId == null || searchEngineId!.isEmpty) {
      printWithTimestamp('ImageSearchService: APIキーまたは検索エンジンIDが設定されていません。');
      return [];
    }

    const String baseUrl = 'https://www.googleapis.com/customsearch/v1';
    final Map<String, dynamic> queryParameters = {
      'key': apiKey!,
      'cx': searchEngineId!,
      'q': query,
      'searchType': 'image',
      'num': numResults.toString(), // 取得する結果の数
      // 'imgSize': 'medium', // 必要であれば画像サイズなども指定可能 (例: medium, large, xlarge, xxlarge, huge, icon)
      // 'safe': 'active', // セーフサーチのレベル (active, off)
    };

    printWithTimestamp('ImageSearchService: Google Custom Search API リクエストパラメータ: $queryParameters');

    try {
      final response = await _dio.get(baseUrl, queryParameters: queryParameters);

      printWithTimestamp('ImageSearchService: RESPONSE STATUS CODE: ${response.statusCode}');

      printWithTimestamp('ImageSearchService: RESPONSE DATA: ${response.data}');

      printWithTimestamp('ImageSearchService: RAW RESPONSE DATA: ${response.data}'); // 生データを常に表示

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null && data is Map<String, dynamic>) {
          if (data.containsKey('items') && data['items'] is List) {
            final List<dynamic> itemsList = data['items'];
            final List<String> imageUrls = [];
            if (itemsList.isEmpty) {
              printWithTimestamp('ImageSearchService: Search returned 0 items (items list is empty).');
            }
            for (var item in itemsList) {
              if (item is Map<String, dynamic>) {
                final String? imageUrl = item['link'] as String?;
                if (imageUrl != null && imageUrl.isNotEmpty) {
                  imageUrls.add(imageUrl);
                } else {
                  printWithTimestamp('ImageSearchService: item["link"] is null or empty. Item data: $item');
                }
              } else {
                printWithTimestamp('ImageSearchService: Item in itemsList is not a Map. Item: $item');
              }
            }
            printWithTimestamp('ImageSearchService: 取得した画像URL (${imageUrls.length}件): $imageUrls');
            return imageUrls;
          } else {
            printWithTimestamp('ImageSearchService: Response data does not contain a valid "items" list. This might mean 0 search results. Keys: ${data.keys}');
          }
        } else {
          printWithTimestamp('ImageSearchService: Response data is null or not a Map. Data: $data');
        }
      } else {
        printWithTimestamp('ImageSearchService: Google Custom Search APIリクエスト失敗 - ステータス: ${response.statusCode}, 本文: ${response.data}');
      }
    } on DioException catch (e) {
      printWithTimestamp('ImageSearchService: Google Custom Search APIリクエスト失敗 - ステータス: ${e.response?.statusCode}, 本文: ${e.response?.data}');
      if (e.response?.data != null) {
        printWithTimestamp('Dioエラー詳細: ${e.response?.data}');
      }
      rethrow;
    } catch (e) {
      printWithTimestamp('ImageSearchService: Google Custom Search APIリクエスト中にエラー: $e');
      rethrow;
    }
    return [];
  }
} 