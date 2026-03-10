import 'dart:io';
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path;

import '../../models/profile_extras.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/mysql_database_service.dart';
import '../../services/profile_storage.dart';
import '../../widgets/toast.dart';
import '../views/sign_in.dart';

// Color constants matching the app's design system
const _inkTitle = Color(0xFF6D4C41); // Medium brown for text
const _inkBody = Color(0xFF5F5B56); // Body text color
const _coffeePrimary = Color(0xFF8D6E63); // Primary brown

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final AuthService _auth = AuthService();
  final ProfileStorage _storage = ProfileStorage();
  final MySQLDatabaseService _db = MySQLDatabaseService();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  Gender _gender = Gender.other;
  DateTime? _dateOfBirth;

  Uint8List? _avatarBytes;
  String? _avatarPath;
  String? _avatarNetworkUrl;
  bool _avatarDirty = false;
  String? _serverAvatarValue;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    final user = _auth.currentUser;
    _avatarDirty = false;
    if (user == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    // Try to load from server first - this ensures we get the most up-to-date data
    // including dateOfBirth that was saved during signup or profile updates
    try {
      final serverUsers = await _db.getAllUsers();
      final serverUser = serverUsers.firstWhere((u) => u.id == user.id, orElse: () => user);
      _usernameController.text = serverUser.username;
      _nameController.text = serverUser.fullName;
      _emailController.text = serverUser.email;
      _phoneController.text = serverUser.phoneNumber ?? '';
      if (serverUser.gender != null) {
        _gender = Gender.values.firstWhere((g) => g.name == serverUser.gender, orElse: () => Gender.other);
      }
      // Prioritize server dateOfBirth - this ensures we display the birthday from signup
      // or the most recently saved birthday from the server
      _dateOfBirth = serverUser.dateOfBirth;
      
      // Load avatar from server (base64 data URL)
      await _applyServerAvatar(serverUser.avatarUrl);
    } catch (e) {
      // Fallback to local storage if server fetch fails
      final extras = await _storage.loadExtras(user);
      _usernameController.text = extras.username;
      _nameController.text = user.fullName;
      _emailController.text = user.email;
      _phoneController.text = user.phoneNumber ?? '';
      _gender = extras.gender;
      // Use local dateOfBirth as fallback, but prioritize user's dateOfBirth if available
      // This ensures we show the birthday from signup even if local storage is outdated
      _dateOfBirth = user.dateOfBirth ?? extras.dateOfBirth;
      _avatarPath = extras.avatarPath;
      if (_avatarPath != null && await File(_avatarPath!).exists()) {
        _avatarBytes = await File(_avatarPath!).readAsBytes();
        _avatarNetworkUrl = null;
      } else {
        await _applyServerAvatar(user.avatarUrl);
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _applyServerAvatar(String? avatarUrl) async {
    _avatarDirty = false;
    _serverAvatarValue = avatarUrl;
    if (avatarUrl == null) {
      _avatarNetworkUrl = null;
      return;
    }
    if (avatarUrl.startsWith('data:image')) {
      try {
        final base64Data = avatarUrl.split(',').last;
        _avatarBytes = base64Decode(base64Data);
        _avatarNetworkUrl = null;
      } catch (_) {
        _avatarNetworkUrl = null;
      }
    } else {
      _avatarBytes = null;
      _avatarNetworkUrl = avatarUrl;
    }
  }

  Future<void> _selectAvatar() async {
    if (!mounted) return;
    try {
      // Use image_picker instead of file_picker for better Android compatibility
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512, // Resize to max 512px width to reduce memory
        maxHeight: 512, // Resize to max 512px height
        imageQuality: 85, // Compress to 85% quality
      );
      
      if (!mounted) return;
      if (pickedFile == null) return;
      
      // Read and compress the image
      Uint8List? imageBytes;
      try {
        final fileBytes = await pickedFile.readAsBytes();
        
        // Decode image to compress it further if needed
        final decodedImage = img.decodeImage(fileBytes);
        if (decodedImage == null) {
          if (mounted) Toast.error(context, 'Failed to process image');
          return;
        }
        
        // Resize if still too large (safety check)
        img.Image resizedImage = decodedImage;
        if (decodedImage.width > 512 || decodedImage.height > 512) {
          resizedImage = img.copyResize(
            decodedImage,
            width: decodedImage.width > decodedImage.height ? 512 : null,
            height: decodedImage.height > decodedImage.width ? 512 : null,
            maintainAspect: true,
          );
        }
        
        // Encode as JPEG with compression
        imageBytes = Uint8List.fromList(
          img.encodeJpg(resizedImage, quality: 85),
        );
        
        // Final size check
        const maxSizeBytes = 5 * 1024 * 1024; // 5MB limit
        if (imageBytes.length > maxSizeBytes) {
          if (mounted) Toast.warning(context, 'Image is too large (max 5 MB). Please choose a smaller image.');
          return;
        }
      } catch (e) {
        debugPrint('Image processing error: $e');
        if (mounted) Toast.error(context, 'Failed to process image: $e');
        return;
      }
      
      if (!mounted) return;
      final finalBytes = imageBytes;
      
      setState(() {
        _avatarBytes = finalBytes;
        _avatarPath = pickedFile.path;
        _avatarNetworkUrl = null;
        _serverAvatarValue = null;
        _avatarDirty = true;
      });
    } catch (e, stackTrace) {
      debugPrint('Image selection error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        Toast.error(context, 'Failed to select image. Please try again.');
      }
    }
  }

  Future<void> _pickDob() async {
    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(1950, 1, 1);
    final DateTime lastDate = DateTime.now();
    final DateTime initialDate = _dateOfBirth ?? DateTime(now.year - 18, 1, 1);
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _coffeePrimary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _inkTitle,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _coffeePrimary,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _dateOfBirth) {
      setState(() {
        _dateOfBirth = picked;
      });
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (_nameController.text.trim().isEmpty) {
      Toast.warning(context, 'Name cannot be empty');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      // Sync to server - upload avatar first if it was changed
      String? avatarPayload = _serverAvatarValue;
      if (_avatarDirty && _avatarBytes != null) {
        final normalizedName = (_avatarPath != null && _avatarPath!.isNotEmpty)
            ? path.basename(_avatarPath!)
            : '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        avatarPayload = await _db.uploadAvatar(
          userId: user.id,
          bytes: _avatarBytes!,
          fileName: normalizedName,
        );
      }
      // Update user on server - include dateOfBirth even if null to ensure it's properly synced
      // This ensures the server has the latest birthday value
      final updatedUser = await _db.updateUser(
        userId: user.id,
        fullName: _nameController.text.trim(),
        username: _usernameController.text.trim(),
        phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        gender: _gender.name,
        dateOfBirth: _dateOfBirth, // Send current dateOfBirth value to server
        avatarUrl: avatarPayload,
      );

      // Update local session with the user data returned from server
      // This ensures we have the server's version of the data, including dateOfBirth
      await _auth.updateCurrentUser(updatedUser);
      await _applyServerAvatar(updatedUser.avatarUrl);
      
      // CRITICAL: Update _dateOfBirth from the server response to ensure consistency
      // This prevents the birthday from reverting to an old value
      // The server's response is the source of truth
      if (updatedUser.dateOfBirth != null) {
        _dateOfBirth = updatedUser.dateOfBirth;
      }

      // Save extras locally for backward compatibility
      // Use the server's dateOfBirth value to ensure local storage matches server
      final extras = ProfileExtras(
        username: _usernameController.text.trim(),
        gender: _gender,
        dateOfBirth: updatedUser.dateOfBirth ?? _dateOfBirth, // Prioritize server value
        avatarPath: _avatarPath,
      );
      await _storage.saveExtras(updatedUser.id, extras);

      if (!mounted) return;
      Toast.success(context, 'Profile saved');
      
      // Pop the screen to return to profile tab, which will refresh
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'Failed to save profile: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }


  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: _inkTitle,
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, {TextInputType? keyboardType}) {
    return CupertinoTextField(
      controller: controller,
      keyboardType: keyboardType,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CupertinoColors.separator),
      ),
      style: GoogleFonts.poppins(
        fontSize: 14,
        color: _inkTitle,
        decoration: TextDecoration.none,
      ),
    );
  }

  Widget _buildGenderChip(Gender gender, String label) {
    final selected = _gender == gender;
    return GestureDetector(
      onTap: () => setState(() => _gender = gender),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? const Color(0xFF8D6E63) : Colors.transparent,
          border: Border.all(
            color: selected ? const Color(0xFF8D6E63) : CupertinoColors.separator,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
              size: 18,
              color: selected ? Colors.white : _inkBody.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: selected ? Colors.white : _inkTitle,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(User user, bool isWide) {
    final avatar = _avatarBytes != null
        ? CircleAvatar(radius: 40, backgroundImage: MemoryImage(_avatarBytes!))
        : _avatarNetworkUrl != null
            ? CircleAvatar(radius: 40, backgroundImage: NetworkImage(_avatarNetworkUrl!))
            : CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFFE0E0E0),
                child: Icon(CupertinoIcons.person, size: 40, color: Colors.grey.shade700),
              );

    final formFields = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Username'),
        _buildField(_usernameController),
        const SizedBox(height: 12),
        _buildLabel('Name'),
        _buildField(_nameController),
        const SizedBox(height: 12),
        _buildLabel('Email'),
        _buildField(_emailController, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _buildLabel('Phone Number'),
        _buildField(_phoneController, keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _buildLabel('Gender'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildGenderChip(Gender.male, 'Male'),
            _buildGenderChip(Gender.female, 'Female'),
            _buildGenderChip(Gender.other, 'Other'),
          ],
        ),
        const SizedBox(height: 12),
        _buildLabel('Date of Birth'),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _pickDob,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: CupertinoColors.separator),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _dateOfBirth == null
                      ? 'Tap to set birthday'
                      : '${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.year}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _dateOfBirth == null ? _inkBody.withValues(alpha: 0.7) : _inkTitle,
                    decoration: TextDecoration.none,
                  ),
                ),
                Icon(
                  CupertinoIcons.calendar,
                  size: 18,
                  color: _inkBody.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Keep the action area laser-focused on saving details per the new UX
        // request (no quick links to addresses/orders/reviews anymore).
        // Modern, sleek button with improved color scheme matching Apple's design guidelines
        CupertinoButton(
          color: _coffeePrimary, // Rich brown primary color for better visibility and modern look
          onPressed: _saving ? null : _saveProfile,
          child: _saving
              ? const CupertinoActivityIndicator(color: Colors.white)
              : Text(
                  'Save',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
        ),
      ],
    );

    final avatarSection = Column(
      children: [
        avatar,
        const SizedBox(height: 8),
        // Modern, sleek button with improved color scheme matching Apple's design guidelines
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          borderRadius: BorderRadius.circular(8),
          color: _coffeePrimary, // Rich brown primary color for better visibility and modern look
          onPressed: _selectAvatar,
          child: Text(
            'Select Image',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text('Max 1 MB • JPEG, PNG',
            style: GoogleFonts.poppins(fontSize: 11, color: _inkBody.withValues(alpha: 0.7))),
      ],
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: formFields),
          const SizedBox(width: 32),
          avatarSection,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: avatarSection),
        const SizedBox(height: 24),
        formFields,
      ],
    );
  }

  Widget _buildGuest() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6,
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.person_crop_circle_badge_plus,
                  size: 60, color: Color(0xFF8D6E63)),
            ),
            const SizedBox(height: 24),
            Text(
              'Create a profile to save your addresses, track orders, and leave reviews.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 16, color: _inkTitle),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute(
                    builder: (_) => const SignInScreen(),
                    fullscreenDialog: true,
                  ),
                );
              },
              child: Text(
                'Sign In / Sign Up',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        leading: CupertinoNavigationBarBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
          color: const Color(0xFF8D6E63),
        ),
        middle: Text('My Profile', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      child: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : user == null
                ? _buildGuest()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 720;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Layout now jumps straight into the editable form
                            // so the screen feels cleaner and matches the new spec.
                            _buildForm(user, isWide),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}

