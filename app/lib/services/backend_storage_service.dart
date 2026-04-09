import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../utils/env_loader.dart';

/// Small data class describing the result of a backend storage upload.
class BackendUploadResult {
  const BackendUploadResult({
    required this.downloadUrl,
    required this.fileName,
    required this.filePath,
  });

  final String downloadUrl;
  final String fileName;
  final String filePath;

  factory BackendUploadResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return BackendUploadResult(
      downloadUrl: (data['downloadUrl'] as String?)?.trim() ?? '',
      fileName: (data['fileName'] as String?)?.trim() ?? '',
      filePath: (data['filePath'] as String?)?.trim() ?? '',
    );
  }
}

/// Public base for Supabase Storage objects (`.../storage/v1/object/public/<bucket>`), no trailing slash.
String _supabasePublicObjectRoot() {
  final explicit = EnvLoader.get('SUPABASE_STORAGE_PUBLIC_BASE').trim();
  if (explicit.isNotEmpty) {
    return explicit.replaceAll(RegExp(r'/+$'), '');
  }
  // Same pattern as backend: project URL + /storage/v1/object/public/<bucket>
  final su = EnvLoader.get('SUPABASE_URL').trim();
  final bucket = EnvLoader.get('SUPABASE_STORAGE_BUCKET', 'smartspace-uploads').trim();
  if (su.isEmpty) return '';
  final root = su.replaceAll(RegExp(r'/+$'), '');
  return '$root/storage/v1/object/public/$bucket';
}

/// Turns API upload JSON into a browser-usable URL.
///
/// Supabase uploads use object keys like `smartspace/models/...`; the backend returns a full
/// `https://*.supabase.co/...` [downloadUrl]. If anything still looks like `/uploads/models/<key>` or
/// the download field is empty, we rebuild from [filePath] using Supabase env vars.
String _resolvePublicDownloadUrl(String downloadUrl, String filePath) {
  var raw = downloadUrl.trim().replaceFirst(RegExp(r'^\uFEFF'), '');
  final fp = filePath.trim().replaceAll('\\', '/');

  // Some proxies strip the URL; we still have the authoritative object key in [filePath].
  if (raw.isEmpty && fp.isNotEmpty) {
    raw = fp.startsWith('smartspace/images/')
        ? '/uploads/images/$fp'
        : '/uploads/models/$fp';
  }

  final parsed = Uri.tryParse(raw);
  if (parsed != null &&
      parsed.hasScheme &&
      (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    return raw;
  }

  // Supabase object key from backend — never treat as a Railway `/uploads` path.
  if (fp.startsWith('smartspace/')) {
    final root = _supabasePublicObjectRoot();
    if (root.isNotEmpty) {
      return '$root/$fp';
    }
  }

  final api = Uri.tryParse(ApiConfig.baseUrl);
  if (api != null && api.hasAuthority) {
    final rel = raw.isEmpty ? '/' : (raw.startsWith('/') ? raw : '/$raw');
    return api.resolve(rel).toString();
  }

  return raw.isEmpty ? fp : raw;
}

/// Handles uploads of GLB/GLTF assets to the backend server.
/// Files are organized per-product in subdirectories.
class BackendStorageService {
  BackendStorageService._();

  static final BackendStorageService instance = BackendStorageService._();

  /// Upload a 3D model for the provided product handle.
  /// The handle is used to create a subdirectory so files stay organized per product.
  Future<BackendUploadResult> uploadModel({
    required String productHandle,
    required String fileName,
    required List<int> bytes,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/models/upload');
    
    // Create multipart request
    final request = http.MultipartRequest('POST', uri);
    
    // Add file
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ),
    );
    
    // Add product handle for folder organization
    request.fields['productHandle'] = productHandle;

    // Send request
    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 300), // 5 minute timeout for large files (up to 100MB)
    );
    
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        errorBody['message']?.toString() ?? 'Upload failed with status ${response.statusCode}',
      );
    }

    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    
    if (responseData['success'] != true) {
      throw Exception(responseData['message']?.toString() ?? 'Upload failed');
    }

    final result = BackendUploadResult.fromJson(responseData);

    return BackendUploadResult(
      downloadUrl: _resolvePublicDownloadUrl(result.downloadUrl, result.filePath),
      fileName: result.fileName,
      filePath: result.filePath,
    );
  }

  /// Upload a product image for the provided product handle.
  Future<BackendUploadResult> uploadImage({
    required String productHandle,
    required String fileName,
    required List<int> bytes,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/images/upload');
    
    // Create multipart request
    final request = http.MultipartRequest('POST', uri);
    
    // Add file
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ),
    );
    
    // Add product handle for folder organization
    request.fields['productHandle'] = productHandle;

    // Send request
    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 60), // 60 second timeout for images
    );
    
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        errorBody['message']?.toString() ?? 'Upload failed with status ${response.statusCode}',
      );
    }

    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    
    if (responseData['success'] != true) {
      throw Exception(responseData['message']?.toString() ?? 'Upload failed');
    }

    final result = BackendUploadResult.fromJson(responseData);

    return BackendUploadResult(
      downloadUrl: _resolvePublicDownloadUrl(result.downloadUrl, result.filePath),
      fileName: result.fileName,
      filePath: result.filePath,
    );
  }

  /// Delete a model from backend storage.
  Future<void> deleteModel(String filePath) async {
    final encodedPath = Uri.encodeComponent(filePath);
    final uri = Uri.parse('${ApiConfig.baseUrl}/models/$encodedPath');
    
    final response = await http.delete(uri).timeout(
      const Duration(seconds: 30),
    );

    if (response.statusCode != 200) {
      final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(
        errorBody['message']?.toString() ?? 'Delete failed with status ${response.statusCode}',
      );
    }
  }
}

