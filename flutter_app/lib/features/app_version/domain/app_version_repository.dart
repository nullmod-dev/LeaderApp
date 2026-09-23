import '../../../core/result/result.dart';
import 'app_version_models.dart';

/// Asks whether the installed build is still supported.
///
/// THE SEAM. A real implementation sends `AppInfo.clientVersionHeader` with
/// the installed version and maps the response:
///
/// - `HTTP 426 Upgrade Required`  → `Success(AppVersionSupport(supported: false, …))`
/// - any success                  → `Success(AppVersionSupport(supported: true))`
/// - no connectivity / timeout    → `Offline()`
/// - anything else                → `Failure(message)`
///
/// The `426` mapping is the only one the screen depends on, and it lives
/// here rather than in the controller so connecting the backend means adding
/// one implementation of this interface and overriding one provider — no
/// widget changes. See `FRONTEND-BACKEND-INTEGRATION.md` §1.
abstract class AppVersionRepository {
  Future<Result<AppVersionSupport>> checkSupport();
}
