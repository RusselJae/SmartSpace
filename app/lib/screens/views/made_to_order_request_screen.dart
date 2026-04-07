import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/mysql_database_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/toast.dart';
import 'sign_in.dart';

/// =============================================================
/// MadeToOrderRequestScreen
///
/// Entry form for custom furniture requests (review first — pay only after you accept a quote).
/// =============================================================
class MadeToOrderRequestScreen extends StatefulWidget {
  const MadeToOrderRequestScreen({super.key, this.prefilledProductName});

  final String? prefilledProductName;

  @override
  State<MadeToOrderRequestScreen> createState() => _MadeToOrderRequestScreenState();
}

class _MadeToOrderRequestScreenState extends State<MadeToOrderRequestScreen> {
  static const Color _kWalnut = Color(0xFF5C4033);
  static const Color _kMuted = Color(0xFF6A6A6A);
  static const Color _kWalnutSoftBg = Color(0xFFEFE8E3);

  final MySQLDatabaseService _db = MySQLDatabaseService();
  final AuthService _auth = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _itemController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _materialsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _agreePolicy = false;
  bool _submitting = false;

  XFile? _validIdXFile;
  List<PlatformFile> _referenceFiles = const [];

  @override
  void initState() {
    super.initState();
    if (!_auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushReplacement(
          CupertinoPageRoute(
            builder: (_) => const SignInScreen(),
            fullscreenDialog: true,
          ),
        );
        Toast.info(context, 'Please sign in first');
      });
      return;
    }
    if (widget.prefilledProductName != null && widget.prefilledProductName!.trim().isNotEmpty) {
      _itemController.text = widget.prefilledProductName!.trim();
    }
  }

  @override
  void dispose() {
    _itemController.dispose();
    _sizeController.dispose();
    _materialsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickValidId() async {
    try {
      final x = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (!mounted) return;
      setState(() => _validIdXFile = x);
    } catch (e) {
      if (!mounted) return;
      Toast.warning(context, 'Could not pick image: $e');
    }
  }

  Future<void> _pickReferenceImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: true,
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;
      setState(() => _referenceFiles = List<PlatformFile>.unmodifiable(result.files));
    } catch (e) {
      if (!mounted) return;
      Toast.warning(context, 'Could not pick files: $e');
    }
  }

  void _removeValidId() {
    setState(() => _validIdXFile = null);
  }

  void _removeReferenceAt(int index) {
    if (index < 0 || index >= _referenceFiles.length) return;
    final updated = List<PlatformFile>.from(_referenceFiles)..removeAt(index);
    setState(() => _referenceFiles = List<PlatformFile>.unmodifiable(updated));
  }

  Future<void> _submitRequest() async {
    final item = _itemController.text.trim();
    if (item.isEmpty) {
      Toast.error(context, 'Please enter item/design details');
      return;
    }
    if (_validIdXFile == null) {
      Toast.error(context, 'Please upload a valid ID photo');
      return;
    }
    if (!_agreePolicy) {
      Toast.error(context, 'Please confirm you understand the process');
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      Toast.error(context, 'Please sign in first');
      return;
    }

    setState(() => _submitting = true);
    try {
      final created = await _db.createMadeToOrderRequest(
        userId: user.id,
        userName: user.fullName,
        itemName: item,
        preferredSize: _sizeController.text.trim(),
        materials: _materialsController.text.trim(),
        notes: _notesController.text.trim(),
      );
      final requestRef = created.requestRef;

      final idFile = _validIdXFile!;
      final idBytes = await idFile.readAsBytes();
      await _db.uploadMadeToOrderValidId(
        requestRef: requestRef,
        imageBytes: idBytes,
        fileName: idFile.name.isNotEmpty ? idFile.name : 'valid_id.jpg',
      );

      if (_referenceFiles.isNotEmpty) {
        final bytesList = <List<int>>[];
        final names = <String>[];
        for (final f in _referenceFiles) {
          if (f.bytes == null) continue;
          bytesList.add(f.bytes!);
          names.add(f.name);
        }
        if (bytesList.isNotEmpty) {
          try {
            await _db.uploadMadeToOrderReferenceImages(
              requestRef: requestRef,
              filesBytes: bytesList,
              fileNames: names,
            );
          } catch (e) {
            if (mounted) {
              Toast.warning(context, 'Reference upload failed (request still saved): $e');
            }
          }
        }
      }

      if (!mounted) return;
      Toast.success(context, 'Request sent. We will review and send you a quote.');
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Could not submit: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _requiredLabel(String label, {double fontSize = 13}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: _kWalnut,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        Text(
          '*',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: CupertinoColors.systemRed,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? placeholder,
    int maxLines = 1,
    TextInputType? keyboardType,
    bool required = false,
    Widget? prefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        required ? _requiredLabel(label) : Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _kWalnut,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: controller,
          prefix: prefix,
          placeholder: placeholder,
          maxLines: maxLines,
          keyboardType: keyboardType,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.black87,
            decoration: TextDecoration.none,
          ),
          placeholderStyle: GoogleFonts.poppins(
            fontSize: 14,
            color: _kMuted.withValues(alpha: 0.7),
            decoration: TextDecoration.none,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kWalnut.withValues(alpha: 0.2), width: 1),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF8F7F5),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: _kWalnut,
        ),
        middle: Text(
          'Made to Order',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: _kWalnut,
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kWalnut.withValues(alpha: 0.2), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom Furniture Request',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kWalnut,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share your design details. We review every request, send a quote, and only then you pay a deposit.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: _kMuted,
                      height: 1.4,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _field(
              label: 'Item / Design',
              controller: _itemController,
              placeholder: 'e.g. 6-seater dining table, Scandinavian style',
              required: true,
            ),
            const SizedBox(height: 12),
            _field(
              label: 'Preferred Size',
              controller: _sizeController,
              placeholder: 'e.g. 180cm x 90cm x 75cm',
            ),
            const SizedBox(height: 12),
            _field(
              label: 'Materials / Finish',
              controller: _materialsController,
              placeholder: 'e.g. mahogany with matte walnut finish',
            ),
            const SizedBox(height: 12),
            _field(
              label: 'Notes',
              controller: _notesController,
              placeholder: 'Any special requests or references',
              maxLines: 4,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kWalnutSoftBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kWalnut.withValues(alpha: 0.18), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _requiredLabel('Valid ID', fontSize: 14),
                  const SizedBox(height: 8),
                  Text(
                    'Upload one clear valid ID for verification.',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      height: 1.4,
                      color: _kMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _pickValidId,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kWalnut.withValues(alpha: 0.25), width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.person_crop_rectangle, color: _kWalnut, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _validIdXFile == null ? 'Add Valid ID photo' : _validIdXFile!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _kWalnut,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(CupertinoIcons.chevron_forward, color: _kWalnut, size: 16),
                        ],
                      ),
                    ),
                  ),
                  if (_validIdXFile != null) ...[
                    const SizedBox(height: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: _removeValidId,
                      child: Text(
                        'Remove attached ID',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemRed,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kWalnutSoftBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kWalnut.withValues(alpha: 0.18), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reference Images',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kWalnut,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Optional images to guide your preferred design.',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      height: 1.4,
                      color: _kMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _pickReferenceImages,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kWalnut.withValues(alpha: 0.25), width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.photo_on_rectangle, color: _kWalnut, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _referenceFiles.isEmpty
                                  ? 'Add reference images'
                                  : '${_referenceFiles.length} reference images selected',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _kWalnut,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(CupertinoIcons.chevron_forward, color: _kWalnut, size: 16),
                        ],
                      ),
                    ),
                  ),
                  if (_referenceFiles.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...List.generate(_referenceFiles.length, (index) {
                      final file = _referenceFiles[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: _kWalnut,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              onPressed: () => _removeReferenceAt(index),
                              child: Text(
                                'Remove',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: CupertinoColors.systemRed,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kWalnut.withValues(alpha: 0.18), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Policy',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kWalnut,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• No payment until we send a quote you accept\n'
                    '• Production timeline: typically 6–7 weeks after deposit\n'
                    '• Deposit is non-refundable if you cancel after paying\n'
                    '• Balance is due on delivery',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.5,
                      color: _kMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 10),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () => setState(() => _agreePolicy = !_agreePolicy),
                    child: Row(
                      children: [
                        Icon(
                          _agreePolicy
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          color: _agreePolicy ? _kWalnut : CupertinoColors.systemGrey2,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'I understand quotes are reviewed before any payment, and deposits are non-refundable if I cancel after paying.',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: _kWalnut,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _submitting ? null : _submitRequest,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: _submitting ? CupertinoColors.systemGrey : _kWalnut,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _submitting ? 'Sending…' : 'Submit request',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

