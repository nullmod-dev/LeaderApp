/// Deterministic credentials for the three development-only MTM identities.
///
/// This is test infrastructure, not product account provisioning. Callers
/// must check `demoAccountsAllowed` before consulting it; release builds take
/// the compile-time-false branch and tree-shake this table. The values are
/// local mock credentials only: never render them, log a password, or reuse
/// them as production secrets.
library;

import '../domain/auth_models.dart';
import 'demo_personas.dart';

final class DevTestCredential {
  const DevTestCredential({
    required this.persona,
    required this.password,
  });

  final DemoPersona persona;
  final String password;

  String get email => persona.user.email;
  AuthUser get user => persona.user;

  bool matchesPassword(String candidate) => candidate == password;
}

abstract final class DevTestCredentials {
  static const superAdmin = DevTestCredential(
    persona: DemoPersona.superAdmin,
    password: 'nullmod.dev@gmail.com',
  );
  static const mainAdmin = DevTestCredential(
    persona: DemoPersona.mainAdmin,
    password: 'pbea4007@mtu.edu.iq',
  );
  static const simpleAdmin = DevTestCredential(
    persona: DemoPersona.simpleAdmin,
    password: 'hamodekaherhm@gmail.com',
  );

  static const values = [superAdmin, mainAdmin, simpleAdmin];

  static DevTestCredential? forEmail(String email) {
    final normalized = email.trim().toLowerCase();
    for (final credential in values) {
      if (credential.email.toLowerCase() == normalized) return credential;
    }
    return null;
  }
}
