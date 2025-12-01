import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile_extras.dart';
import '../models/address_entry.dart';
import '../models/user.dart';
import 'mysql_database_service.dart';

class ProfileStorage {
  static final ProfileStorage _instance = ProfileStorage._internal();
  factory ProfileStorage() => _instance;
  ProfileStorage._internal();

  static const String _extrasPrefix = 'profile_extras_';
  static const String _addressesPrefix = 'profile_addresses_';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<ProfileExtras> loadExtras(User user) async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString('$_extrasPrefix${user.id}');
    if (raw == null) {
      return ProfileExtras(
        username: user.email.split('@').first,
        gender: Gender.other,
        dateOfBirth: null,
        avatarPath: null,
      );
    }
    try {
      return ProfileExtras.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return ProfileExtras(
        username: user.email.split('@').first,
        gender: Gender.other,
        dateOfBirth: null,
        avatarPath: null,
      );
    }
  }

  Future<void> saveExtras(String userId, ProfileExtras extras) async {
    final prefs = await _ensurePrefs();
    await prefs.setString('$_extrasPrefix$userId', jsonEncode(extras.toJson()));
  }

  Future<List<AddressEntry>> loadAddresses(String userId) async {
    final db = MySQLDatabaseService();
    // Try database first
    if (db.isConnected) {
      try {
        final addresses = await db.getAddresses(userId);
        // Also save to local cache for offline support
        await _saveAddressesLocal(userId, addresses);
        return addresses;
      } catch (e) {
        // Fall back to local storage if database fails
      }
    }
    // Fallback to local storage
    final prefs = await _ensurePrefs();
    final raw = prefs.getString('$_addressesPrefix$userId');
    if (raw == null) return [];
    try {
      final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return data.map(AddressEntry.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAddresses(String userId, List<AddressEntry> addresses) async {
    final db = MySQLDatabaseService();
    // Save to database first
    if (db.isConnected) {
      try {
        // Get existing addresses from database
        final existing = await db.getAddresses(userId);
        final existingIds = existing.map((a) => a.id).toSet();
        final newIds = addresses.map((a) => a.id).toSet();
        
        // Delete addresses that were removed
        for (final addr in existing) {
          if (!newIds.contains(addr.id)) {
            await db.deleteAddress(addr.id, userId);
          }
        }
        
        // Create or update addresses
        for (final addr in addresses) {
          if (existingIds.contains(addr.id)) {
            // Update existing
            await db.updateAddress(
              addressId: addr.id,
              userId: userId,
              fullName: addr.fullName,
              phoneNumber: addr.phoneNumber,
              region: addr.region,
              street: addr.street,
              postalCode: addr.postalCode.isEmpty ? null : addr.postalCode,
              label: addr.label,
              isDefault: addr.isDefault,
            );
          } else {
            // Create new
            await db.createAddress(
              userId: userId,
              fullName: addr.fullName,
              phoneNumber: addr.phoneNumber,
              region: addr.region,
              street: addr.street,
              postalCode: addr.postalCode.isEmpty ? null : addr.postalCode,
              label: addr.label,
              isDefault: addr.isDefault,
            );
          }
        }
        // Also save to local cache
        await _saveAddressesLocal(userId, addresses);
        return;
      } catch (e) {
        // Fall back to local storage if database fails
      }
    }
    // Fallback to local storage
    await _saveAddressesLocal(userId, addresses);
  }

  Future<void> _saveAddressesLocal(String userId, List<AddressEntry> addresses) async {
    final prefs = await _ensurePrefs();
    await prefs.setString(
      '$_addressesPrefix$userId',
      jsonEncode(addresses.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> clearUserData(String userId) async {
    final prefs = await _ensurePrefs();
    await prefs.remove('$_extrasPrefix$userId');
    await prefs.remove('$_addressesPrefix$userId');
  }
}

