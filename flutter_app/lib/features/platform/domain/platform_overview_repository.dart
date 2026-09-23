import '../../../core/result/result.dart';
import 'platform_overview_models.dart';

/// The one aggregate read needed by the platform landing page.
///
/// A future backend may build this projection from several services, but the
/// client should not coordinate ten endpoints merely to render one overview.
abstract class PlatformOverviewRepository {
  Future<Result<PlatformOverviewSnapshot>> loadOverview();
}
