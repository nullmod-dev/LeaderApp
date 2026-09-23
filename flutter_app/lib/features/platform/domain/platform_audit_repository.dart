import '../../../core/result/result.dart';
import 'platform_audit_models.dart';

abstract interface class PlatformAuditRepository {
  Future<Result<PlatformAuditPage>> listAuditEvents(PlatformAuditQuery query);
}
