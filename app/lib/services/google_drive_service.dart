import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import '../utils/env_loader.dart';

/// Small data class describing the result of a Drive upload so callers can
/// persist both the public download link and the raw file id if needed later.
class DriveUploadResult {
  const DriveUploadResult({
    required this.fileId,
    required this.fileName,
    required this.downloadUrl,
    required this.folderId,
    required this.webViewLink,
  });

  final String fileId;
  final String fileName;
  final String downloadUrl;
  final String folderId;
  final String webViewLink;
}

/// Handles authenticated uploads of GLB/GTLF assets to the configured
/// Google Drive folder so each product can own its own directory of models.
class GoogleDriveService {
  GoogleDriveService._();

  static final GoogleDriveService instance = GoogleDriveService._();

  final Random _random = Random();
  AutoRefreshingAuthClient? _authClient;
  drive.DriveApi? _drive;
  String? _rootFolderId;

  /// Upload a 3D model for the provided product handle. The handle is used to
  /// create (or reuse) a child folder beneath the configured root folder so
  /// files stay organized per product.
  Future<DriveUploadResult> uploadModel({
    required String productHandle,
    required String fileName,
    required List<int> bytes,
  }) async {
    await _ensureInitialized();

    final driveApi = _drive!;
    final folderId = await _ensureProductFolder(productHandle);
    final sanitizedName = _sanitizeFileName(fileName);
    final media = drive.Media(
      Stream<List<int>>.fromIterable([bytes]),
      bytes.length,
      contentType: 'model/gltf-binary',
    );

    final metadata = drive.File()
      ..name = sanitizedName
      ..parents = [folderId];

    final uploaded = await driveApi.files.create(
      metadata,
      uploadMedia: media,
      $fields: 'id,name,webViewLink,webContentLink',
    );

    final fileId = uploaded.id;
    if (fileId == null) {
      throw StateError('Google Drive did not return a file id after upload.');
    }

    // Flip the permission so AR previews can fetch the model via public link.
    await driveApi.permissions.create(
      drive.Permission()
        ..type = 'anyone'
        ..role = 'reader',
      fileId,
    );

    // Re-fetch the file to get webContentLink after setting permissions
    // This ensures we get the direct download link for publicly accessible files
    final fileWithLink = await driveApi.files.get(
      fileId,
      $fields: 'id,webContentLink',
    ) as drive.File;

    // Use webContentLink if available (direct download), otherwise build a download URL
    final downloadUrl = fileWithLink.webContentLink ?? _buildDownloadUrl(fileId);

    return DriveUploadResult(
      fileId: fileId,
      fileName: uploaded.name ?? sanitizedName,
      downloadUrl: downloadUrl,
      folderId: folderId,
      webViewLink: uploaded.webViewLink ?? 'https://drive.google.com/file/d/$fileId/view',
    );
  }

  Future<void> _ensureInitialized() async {
    if (_drive != null && _rootFolderId != null) return;

    final folderId = EnvLoader.get('GOOGLE_DRIVE_FOLDER_ID');
    final clientEmail = EnvLoader.get('GOOGLE_SERVICE_ACCOUNT_EMAIL');
    final privateKey = EnvLoader.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY');

    if (folderId.isEmpty || clientEmail.isEmpty || privateKey.isEmpty) {
      throw StateError(
        'Missing Google Drive credentials. Please set GOOGLE_DRIVE_FOLDER_ID, '
        'GOOGLE_SERVICE_ACCOUNT_EMAIL, and GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY in .env',
      );
    }

    final normalizedKey = privateKey.replaceAll(r'\n', '\n');

    // Construct a JSON-like structure for ServiceAccountCredentials.fromJson
    // The service account JSON typically has: type, project_id, private_key_id, private_key, client_email, etc.
    // We'll create a minimal valid structure with what we have
    final credentialsJson = {
      'type': 'service_account',
      'project_id': '', // Not strictly required for Drive API
      'private_key_id': '', // Not strictly required
      'private_key': normalizedKey,
      'client_email': clientEmail,
      'client_id': '', // Not strictly required
      'auth_uri': 'https://accounts.google.com/o/oauth2/auth',
      'token_uri': 'https://oauth2.googleapis.com/token',
      'auth_provider_x509_cert_url': 'https://www.googleapis.com/oauth2/v1/certs',
      'client_x509_cert_url': '',
    };

    final credentials = ServiceAccountCredentials.fromJson(jsonEncode(credentialsJson));

    final scopes = [drive.DriveApi.driveFileScope];
    final baseClient = http.Client();
    _authClient = await clientViaServiceAccount(credentials, scopes, baseClient: baseClient);
    _drive = drive.DriveApi(_authClient!);
    _rootFolderId = folderId;
  }

  Future<String> _ensureProductFolder(String productHandle) async {
    final driveApi = _drive!;
    final rootId = _rootFolderId!;
    final folderName = _slugify(productHandle.isEmpty ? 'draft' : productHandle);

    final search = await driveApi.files.list(
      q:
          "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and '$rootId' in parents and trashed = false",
      $fields: 'files(id,name)',
      spaces: 'drive',
    );

    final existing = search.files?.firstWhere(
      (file) => file.id != null,
      orElse: () => drive.File(),
    );
    if (existing != null && existing.id != null) {
      return existing.id!;
    }

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [rootId];

    final created = await driveApi.files.create(folder, $fields: 'id');
    if (created.id == null) {
      throw StateError('Failed to create product folder on Google Drive.');
    }
    return created.id!;
  }

  String _slugify(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp('-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (normalized.isNotEmpty) return normalized;
    return 'product-${DateTime.now().millisecondsSinceEpoch}-${_random.nextInt(9999)}';
  }

  String _sanitizeFileName(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return 'model-${DateTime.now().millisecondsSinceEpoch}.glb';
    }
    return trimmed.replaceAll(RegExp(r'[^\w\.\-]'), '_');
  }

  /// Builds a direct download URL for a Google Drive file.
  /// This format works with ModelViewer and other web-based 3D viewers.
  /// For publicly accessible files, this bypasses the virus scan warning.
  String _buildDownloadUrl(String fileId) {
    // Use export=download with confirm=t to bypass virus scan warning
    // This format works better for binary files like GLB/GLTF
    return 'https://drive.google.com/uc?export=download&id=$fileId&confirm=t';
  }
}

