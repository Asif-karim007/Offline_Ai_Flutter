import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal secure-storage wrapper for the user-supplied web-search API key.
///
/// Swift's `KeychainStore`, ported onto `flutter_secure_storage` — Keychain on iOS,
/// EncryptedSharedPreferences over the Android Keystore on Android. Only key material goes
/// here; *whether* a key exists is a plain, non-secret flag in preferences, so the settings UI
/// can render "configured"/"not configured" without a secure-storage read on every rebuild.
/// Keep that split when wiring settings up.
///
/// The iOS service attribute is set explicitly to the string the Swift app used, so a key
/// written by the Swift build is found by this one on the same device.
class ApiKeyStore {
  ApiKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String service = 'com.offlineaichat.websearch';

  static const IOSOptions _iosOptions = IOSOptions(
    accountName: service,
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  static const AndroidOptions _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);

  Future<void> set(String value, {required String key}) => _storage.write(
        key: key,
        value: value,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  Future<String?> get({required String key}) => _storage.read(
        key: key,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  Future<void> remove({required String key}) => _storage.delete(
        key: key,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
}
