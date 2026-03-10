import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

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
      downloadUrl: data['downloadUrl'] as String,
      fileName: data['fileName'] as String,
      filePath: data['filePath'] as String,
    );
  }
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
    
    // Convert relative URL to absolute URL
    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    final absoluteUrl = result.downloadUrl.startsWith('http')
        ? result.downloadUrl
        : '$baseUrl${result.downloadUrl}';

    return BackendUploadResult(
      downloadUrl: absoluteUrl,
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
    
    // Convert relative URL to absolute URL
    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    final absoluteUrl = result.downloadUrl.startsWith('http')
        ? result.downloadUrl
        : '$baseUrl${result.downloadUrl}';

    return BackendUploadResult(
      downloadUrl: absoluteUrl,
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

