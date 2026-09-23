import '../../../core/result/result.dart';
import 'home_models.dart';

abstract class HomeRepository {
  /// Today's operational snapshot for one detachment.
  ///
  /// One call rather than three: the dashboard needs the detachment, the
  /// shifts around now, and the store's health together, and a mobile client
  /// opening on a bad connection should pay for one round trip, not three.
  /// A backend serves this by joining data it already owns — see
  /// `API_CONTRACT.md` § Home.
  Future<Result<HomeSummary>> summary(String detachmentId);
}
