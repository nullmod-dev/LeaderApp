import '../../../core/motion/animated_counter.dart';
import '../../../l10n/strings.dart';
import 'inventory_models.dart';

/// A stock figure a storekeeper can read aloud.
///
/// Stock is held in individual units, but nobody counts 360 tablets — they
/// count three cartons. Only the parts that are actually there are named, so
/// an unpackaged item reads "٤ وحدة فردية" rather than
/// "٠ كرتونة، ٠ شريط، ٤ وحدة فردية"; a zero stock still says so.
String stockBreakdownLabel(InventoryItem item) {
  final value = item.stockBreakdown;
  final parts = <String>[
    if (value.cartons > 0)
      '${toArabicIndic('${value.cartons}')} ${S.cartonsLabel}',
    if (value.strips > 0)
      '${toArabicIndic('${value.strips}')} ${S.stripsLabel}',
    if (value.individuals > 0 || (value.cartons == 0 && value.strips == 0))
      '${toArabicIndic('${value.individuals}')} ${S.individualUnitsLabel}',
  ];
  return parts.join('، ');
}
