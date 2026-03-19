import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/models/app_error.dart';
import '../../domain/models/archive_descriptor.dart';
import '../auth/auth_token_provider.dart';
import '../logging/sync_logger.dart';

/// Low-level Google Drive API operations.
class GoogleDriveService {
  static const _driveApiBase = 'https://www.googleapis.com/drive/v3';

  final AuthTokenProvider _authService;
  final SyncLogger _logger;
  final http.Client _httpClient;

  GoogleDriveService({
    required AuthTokenProvider authService,
    required SyncLogger logger,
    http.Client? httpClient,
  })  : _authService = authService,
        _logger = logger,
        _httpClient = httpClient ?? http.Client();

  /// Search for Takeout archive ZIP files on Drive.
  Future<List<ArchiveFile>> listTakeoutArchives() async {
    _logger.info('drive_archive_search_started');

    final headers = await _authService.getAuthHeaders();

    // Primary search: ZIP files with "takeout" in name
    var files = await _searchFiles(
      headers,
      "mimeType='application/zip' and name contains 'takeout' and trashed=false",
    );

    // Fallback 1: any file with "takeout" in name (might not be application/zip)
    if (files.isEmpty) {
      _logger.info('drive_fallback_search_any_takeout');
      files = await _searchFiles(
        headers,
        "name contains 'takeout' and trashed=false",
      );
      // Filter to only zip-like files
      files = files.where((f) => f.name.toLowerCase().endsWith('.zip')).toList();
    }

    // Fallback 2: any ZIP file at all (diagnostic)
    if (files.isEmpty) {
      _logger.info('drive_fallback_search_any_zip');
      final allZips = await _searchFiles(
        headers,
        "mimeType='application/zip' and trashed=false",
      );
      final allFileNames = allZips.map((f) => f.name).take(10).toList();

      // Also check for any files at all (to verify Drive access works)
      final anyFiles = await _searchFiles(headers, "trashed=false");

      throw AppError(
        AppErrorCode.archiveNotFound,
        'Takeoutアーカイブが見つかりません。\n'
        'Drive上のZIPファイル数: ${allZips.length}\n'
        'Drive上の全ファイル数: ${anyFiles.length}\n'
        '${allZips.isNotEmpty ? 'ZIP名: ${allFileNames.join(", ")}' : ''}\n'
        'ヒント: Google Takeoutで配信先を「Googleドライブに追加」にしてエクスポートしてください。',
      );
    }

    _logger.info('drive_archive_search_completed', {
      'fileCount': files.length,
    });

    return files;
  }

  /// Execute a Drive API file search with the given query.
  Future<List<ArchiveFile>> _searchFiles(
    Map<String, String> headers,
    String queryString,
  ) async {
    final query = Uri.encodeComponent(queryString);
    final fields = Uri.encodeComponent('files(id,name,size,createdTime)');

    final url = '$_driveApiBase/files?q=$query&fields=$fields'
        '&orderBy=createdTime desc&pageSize=50';

    final response = await _httpClient.get(Uri.parse(url), headers: headers);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AppError(
        AppErrorCode.tokenExpired,
        'Drive API authentication failed',
      );
    }

    if (response.statusCode != 200) {
      throw AppError(
        AppErrorCode.downloadFailed,
        'Drive API search failed: ${response.statusCode} ${response.body}',
      );
    }

    return _parseFileListResponse(response.body);
  }

  /// Download a file from Drive by its file ID.
  Future<Uint8List> downloadFile(String fileId) async {
    final headers = await _authService.getAuthHeaders();
    final url = '$_driveApiBase/files/$fileId?alt=media';

    final response = await _httpClient.get(Uri.parse(url), headers: headers);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AppError(
        AppErrorCode.tokenExpired,
        'Drive API authentication failed during download',
      );
    }

    if (response.statusCode != 200) {
      throw AppError(
        AppErrorCode.downloadFailed,
        'Drive file download failed: ${response.statusCode}',
      );
    }

    return response.bodyBytes;
  }

  /// Parse the JSON response from Drive files.list.
  List<ArchiveFile> _parseFileListResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final fileList = json['files'] as List<dynamic>? ?? [];

    return fileList
        .cast<Map<String, dynamic>>()
        .where((f) => f['id'] != null && f['name'] != null)
        .map((f) => ArchiveFile(
              fileId: f['id'] as String,
              name: f['name'] as String,
              sizeBytes: f['size'] != null
                  ? int.tryParse(f['size'].toString()) ?? 0
                  : 0,
              createdTime: f['createdTime'] != null
                  ? DateTime.parse(f['createdTime'] as String)
                  : DateTime.now(),
            ))
        .toList();
  }

  void dispose() {
    _httpClient.close();
  }
}
