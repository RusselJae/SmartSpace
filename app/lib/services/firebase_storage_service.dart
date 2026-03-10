import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

import '../utils/env_loader.dart';

/// Small data class describing the result of a Firebase Storage upload.
class FirebaseUploadResult {
  const FirebaseUploadResult({
    required this.downloadUrl,
    required this.fileName,
    required this.filePath,
  });

  final String downloadUrl;
  final String fileName;
  final String filePath;
}

/// Handles uploads of GLB/GLTF assets to Firebase Storage.
/// Files are organized per-product in subdirectories.
class FirebaseStorageService {
  FirebaseStorageService._();

  static final FirebaseStorageService instance = FirebaseStorageService._();

  FirebaseStorage? _storage;
  String? _basePath;

  /// Initialize Firebase Storage with configuration from environment.
  Future<void> _ensureInitialized() async {
    if (_storage != null && _basePath != null) return;

    _basePath = EnvLoader.get('FIREBASE_STORAGE_BASE_PATH');
    if (_basePath == null || _basePath!.isEmpty) {
      _basePath = '3d-models'; // Default path
    }

    // Initialize Firebase Storage
    // Note: Firebase Core should be initialized in main.dart
    _storage = FirebaseStorage.instance;
  }

  /// Upload a 3D model for the provided product handle.
  /// The handle is used to create a subdirectory so files stay organized per product.
  Future<FirebaseUploadResult> uploadModel({
    required String productHandle,
    required String fileName,
    required List<int> bytes,
  }) async {
    await _ensureInitialized();

    final storage = _storage!;
    final basePath = _basePath!;

    // Sanitize the product handle and file name
    final sanitizedHandle = _sanitizePath(productHandle.isEmpty ? 'draft' : productHandle);
    final sanitizedFileName = _sanitizeFileName(fileName);

    // Create the storage path: basePath/productHandle/fileName
    final storagePath = '$basePath/$sanitizedHandle/$sanitizedFileName';

    // Create a reference to the file location
    final ref = storage.ref().child(storagePath);

    // Upload the file
    try {
      final uploadTask = ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(
          contentType: 'model/gltf-binary',
          cacheControl: 'public, max-age=31536000', // Cache for 1 year
        ),
      );

      // Wait for upload to complete
      final snapshot = await uploadTask;

      // Get the download URL (publicly accessible)
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return FirebaseUploadResult(
        downloadUrl: downloadUrl,
        fileName: sanitizedFileName,
        filePath: storagePath,
      );
    } catch (e) {
      throw Exception('Failed to upload model to Firebase Storage: $e');
    }
  }

  /// Delete a model from Firebase Storage.
  Future<void> deleteModel(String filePath) async {
    await _ensureInitialized();

    final storage = _storage!;
    final ref = storage.ref().child(filePath);

    try {
      await ref.delete();
    } catch (e) {
      throw Exception('Failed to delete model from Firebase Storage: $e');
    }
  }

  /// Get a download URL for an existing file.
  Future<String> getDownloadUrl(String filePath) async {
    await _ensureInitialized();

    final storage = _storage!;
    final ref = storage.ref().child(filePath);

    try {
      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception('Failed to get download URL: $e');
    }
  }

  String _sanitizePath(String input) {
    // Remove or replace invalid characters for Firebase Storage paths
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-_]'), '-')
        .replaceAll(RegExp('-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _sanitizeFileName(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return 'model-${DateTime.now().millisecondsSinceEpoch}.glb';
    }
    // Keep the extension, sanitize the rest
    final ext = path.extension(trimmed);
    final nameWithoutExt = path.basenameWithoutExtension(trimmed);
    final sanitized = nameWithoutExt.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    return '$sanitized$ext';
  }
}

