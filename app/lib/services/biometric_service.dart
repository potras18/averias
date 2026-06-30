import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      final biometrics = await _auth.getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Accede a Cocamatic',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }
}
