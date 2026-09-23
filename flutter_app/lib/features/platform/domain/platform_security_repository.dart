import '../../../core/result/result.dart';
import 'platform_security_models.dart';

/// Read-only backend boundary for current platform security alerts.
///
/// It exposes no Point 11 audit data or alert mutations.
abstract class PlatformSecurityRepository {
  Future<Result<PlatformSecuritySnapshot>> loadSecurityAlerts();
}
