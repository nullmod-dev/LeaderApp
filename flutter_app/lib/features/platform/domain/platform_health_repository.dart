import '../../../core/result/result.dart';
import 'platform_health_models.dart';

/// Read-only backend boundary for the latest available platform health
/// snapshot. It is independent from tenant-operational repositories.
abstract class PlatformHealthRepository {
  Future<Result<PlatformHealthSnapshot>> loadHealth();
}
