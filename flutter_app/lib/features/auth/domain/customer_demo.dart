import '../../demo/domain/demo_capabilities.dart';
import '../../../l10n/strings.dart';
import 'auth_models.dart';

/// Global product policy for starting a customer demo.
///
/// This is intentionally unrelated to the debug-only persona gate. A real
/// composition root replaces it from remote/platform configuration. The
/// optional duration is authoritative configuration when supplied; `null`
/// means the backend owns expiry entirely through `SessionAccess.demo`.
class CustomerDemoPolicy {
  const CustomerDemoPolicy({required this.available, this.duration});

  final bool available;
  final Duration? duration;
}

const defaultCustomerDemoPolicy = CustomerDemoPolicy(available: true);

/// The isolated demo identity used by the development backend.
///
/// It is neither a tenant administrator nor a development persona: no tenant
/// id, no tenant membership, and a dedicated role that reaches the product
/// only while the session envelope also says the demo is active.
///
/// It carries [demoCapabilities] — the demo-only envelope — because the trial
/// is the real application and every control in it is capability-gated. Read
/// that file for what stops the envelope being a production grant.
const customerDemoUser = AuthUser(
  id: 'customer_demo_workspace',
  name: 'زائر تجربة ${S.productNameAr}',
  email: 'demo@mtm.app',
  role: AuthRole.customerDemo,
  saasTenantId: null,
  capabilities: demoCapabilities,
  orgName: 'مساحة تجربة ${S.productNameAr}',
  avatarInitials: 'تج',
);
