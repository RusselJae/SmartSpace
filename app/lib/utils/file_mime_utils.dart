/// Utility to derive MIME type from file name/extension.
///
/// PlatformFile in file_picker does not expose mimeType, so we infer from extension.
String mimeTypeFromFileName(String? name, [String? extension]) {
  final ext = (extension ?? '').toLowerCase().replaceFirst('.', '');
  final fromExt = ext.isNotEmpty ? ext : (name ?? '').split('.').lastOrNull?.toLowerCase() ?? '';
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'zip': 'application/zip',
    'rar': 'application/x-rar-compressed',
  };
  return map[fromExt] ?? 'application/octet-stream';
}
