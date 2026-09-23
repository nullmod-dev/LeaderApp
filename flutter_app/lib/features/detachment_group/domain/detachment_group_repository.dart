import '../../../core/result/result.dart';
import 'detachment_group_models.dart';

abstract class DetachmentGroupRepository {
  Future<Result<List<DetachmentGroup>>> list({String? query});

  Future<Result<DetachmentGroup>> byId(String id);

  /// A name is the whole form. Everything else is optional.
  Future<Result<DetachmentGroup>> create({required String name, String? notes});

  Future<Result<DetachmentGroup>> update(DetachmentGroup group);

  /// Removes the detachment group **and everything inside it**. The caller has
  /// already confirmed; the repository does not ask again.
  Future<Result<void>> delete(String id);
}
