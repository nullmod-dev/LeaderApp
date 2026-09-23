import 'dart:math';

import '../../../core/result/result.dart';
import '../domain/inventory_models.dart';
import '../domain/inventory_repository.dart';

/// In-memory stock. Every active detachment carries items, including at least
/// one low and one expiring line, so the Storage tab is never blank and the
/// warning styles are always exercised. The archived one carries stock too —
/// the closing quantities and the movements that produced them, which is what
/// the archive reads back.
class MockInventoryRepository implements InventoryRepository {
  /// [items] and [movements] replace the seed — the Customer Demo workspace
  /// passes its own stock.
  MockInventoryRepository({
    List<InventoryItem>? items,
    List<InventoryMovement>? movements,
  })  : _items = List.of(items ?? _defaultItems()),
        _movements = List.of(movements ?? _defaultMovements());

  final _rand = Random(41);

  final List<InventoryItem> _items;

  static List<InventoryItem> _defaultItems() => [
    // ---- d_dam_central ----
    InventoryItem(
      id: 'i1',
      detachmentId: 'd_dam_central',
      name: 'أدرينالين ١ ملغ/مل',
      unit: 'أمبولة',
      currentStock: 4,
      minimum: 12,
      expiresOn: DateTime.now().add(const Duration(days: 22)),
      level: StockLevel.low,
    ),
    InventoryItem(
      id: 'i2',
      detachmentId: 'd_dam_central',
      name: 'باراسيتامول ٥٠٠ ملغ',
      unit: 'وحدة',
      currentStock: 72,
      minimum: 240,
      expiresOn: DateTime.now().add(const Duration(days: 120)),
      level: StockLevel.low,
      unitsPerStrip: 12,
      stripsPerCarton: 10,
      preferredUnit: PackagingUnit.strip,
    ),
    const InventoryItem(
      id: 'i3',
      detachmentId: 'd_dam_central',
      name: 'شاش طبي ١٠سم',
      unit: 'رول',
      currentStock: 32,
      minimum: 15,
      expiresOn: null,
      level: StockLevel.ok,
    ),
    InventoryItem(
      id: 'i4',
      detachmentId: 'd_dam_central',
      name: 'سالبوتامول بخّاخ',
      unit: 'قطعة',
      currentStock: 0,
      minimum: 6,
      expiresOn: DateTime.now().add(const Duration(days: 10)),
      level: StockLevel.empty,
    ),
    InventoryItem(
      id: 'i5',
      detachmentId: 'd_dam_central',
      name: 'دِكستروز ٥٪',
      unit: 'كيس',
      currentStock: 24,
      minimum: 10,
      expiresOn: DateTime.now().add(const Duration(days: 300)),
      level: StockLevel.ok,
    ),

    // ---- d_dam_rural ----
    const InventoryItem(
      id: 'i6',
      detachmentId: 'd_dam_rural',
      name: 'كمّامة N95',
      unit: 'قطعة',
      currentStock: 120,
      minimum: 30,
      expiresOn: null,
      level: StockLevel.ok,
    ),
    InventoryItem(
      id: 'i7',
      detachmentId: 'd_dam_rural',
      name: 'محلول ملحي ٠٫٩٪',
      unit: 'كيس',
      currentStock: 9,
      minimum: 18,
      expiresOn: DateTime.now().add(const Duration(days: 45)),
      level: StockLevel.low,
    ),
    const InventoryItem(
      id: 'i8',
      detachmentId: 'd_dam_rural',
      name: 'قفازات معقّمة — قياس M',
      unit: 'علبة',
      currentStock: 14,
      minimum: 8,
      expiresOn: null,
      level: StockLevel.ok,
    ),

    // ---- d_homs ----
    InventoryItem(
      id: 'i9',
      detachmentId: 'd_homs',
      name: 'أتروبين ١ ملغ',
      unit: 'أمبولة',
      currentStock: 2,
      minimum: 8,
      expiresOn: DateTime.now().add(const Duration(days: 6)),
      level: StockLevel.low,
    ),
    const InventoryItem(
      id: 'i10',
      detachmentId: 'd_homs',
      name: 'ضمادة ضاغطة',
      unit: 'قطعة',
      currentStock: 40,
      minimum: 20,
      expiresOn: null,
      level: StockLevel.ok,
    ),
    InventoryItem(
      id: 'i11',
      detachmentId: 'd_homs',
      name: 'ليدوكائين ٢٪',
      unit: 'أمبولة',
      currentStock: 0,
      minimum: 5,
      expiresOn: DateTime.now().add(const Duration(days: 200)),
      level: StockLevel.empty,
    ),

    // ---- d_coast ----
    const InventoryItem(
      id: 'i12',
      detachmentId: 'd_coast',
      name: 'جبيرة رقبة قابلة للتعديل',
      unit: 'قطعة',
      currentStock: 11,
      minimum: 6,
      expiresOn: null,
      level: StockLevel.ok,
    ),
    InventoryItem(
      id: 'i13',
      detachmentId: 'd_coast',
      name: 'أكسجين محمول ٢ لتر',
      unit: 'أسطوانة',
      currentStock: 3,
      minimum: 4,
      expiresOn: DateTime.now().add(const Duration(days: 400)),
      level: StockLevel.low,
    ),
    InventoryItem(
      id: 'i14',
      detachmentId: 'd_coast',
      name: 'شريط قياس سكر الدم',
      unit: 'علبة',
      currentStock: 7,
      minimum: 5,
      expiresOn: DateTime.now().add(const Duration(days: 14)),
      level: StockLevel.ok,
    ),

    // ---- d_north_arch (archived) ----
    // The stock a finished detachment was left holding. It is the *stored*
    // quantity, not a reconstruction: this domain keeps a movement log per
    // item (below), and the archive shows that log rather than inventing a
    // stock level for any earlier date.
    const InventoryItem(
      id: 'i15',
      detachmentId: 'd_north_arch',
      name: 'شاش طبي ١٠سم',
      unit: 'رول',
      currentStock: 9,
      minimum: 10,
      expiresOn: null,
      level: StockLevel.low,
    ),
    InventoryItem(
      id: 'i16',
      detachmentId: 'd_north_arch',
      name: 'محلول ملحي ٥٠٠مل',
      unit: 'كيس',
      currentStock: 14,
      minimum: 8,
      expiresOn: DateTime.now().subtract(const Duration(days: 5)),
      level: StockLevel.ok,
    ),
    const InventoryItem(
      id: 'i17',
      detachmentId: 'd_north_arch',
      name: 'قفازات معقّمة',
      unit: 'علبة',
      currentStock: 0,
      minimum: 4,
      expiresOn: null,
      level: StockLevel.empty,
    ),
  ];

  final List<InventoryMovement> _movements;

  static List<InventoryMovement> _defaultMovements() => [
    InventoryMovement(
        id: 'mv1',
        itemId: 'i1',
        direction: MovementDirection.outflow,
        quantity: 2,
        reason: 'طوارئ · شفت ١٤–٢٠',
        at: DateTime.now().subtract(const Duration(days: 3))),
    InventoryMovement(
        id: 'mv2',
        itemId: 'i1',
        direction: MovementDirection.inflow,
        quantity: 6,
        reason: 'تسليم من المستودع المركزي',
        at: DateTime.now().subtract(const Duration(days: 10))),
    InventoryMovement(
        id: 'mv3',
        itemId: 'i2',
        direction: MovementDirection.outflow,
        quantity: 4,
        reason: 'صرف ورشة',
        at: DateTime.now().subtract(const Duration(days: 1))),
    InventoryMovement(
        id: 'mv4',
        itemId: 'i4',
        direction: MovementDirection.outflow,
        quantity: 6,
        reason: 'نوبة ربو · مركز الشعلان',
        at: DateTime.now().subtract(const Duration(days: 2))),
    InventoryMovement(
        id: 'mv5',
        itemId: 'i7',
        direction: MovementDirection.outflow,
        quantity: 9,
        reason: 'إسعاف ميداني · داريا',
        at: DateTime.now().subtract(const Duration(days: 4))),
    InventoryMovement(
        id: 'mv6',
        itemId: 'i9',
        direction: MovementDirection.inflow,
        quantity: 4,
        reason: 'تبرّع صيدلية الوعر',
        at: DateTime.now().subtract(const Duration(days: 7))),
    InventoryMovement(
        id: 'mv7',
        itemId: 'i13',
        direction: MovementDirection.outflow,
        quantity: 1,
        reason: 'نقل مريض إلى المشفى',
        at: DateTime.now().subtract(const Duration(hours: 20))),

    // The archived detachment's movement log — dated inside the weeks it
    // actually ran, so the archive's storage tab has a real history to show
    // and not just a closing number.
    InventoryMovement(
        id: 'mv8',
        itemId: 'i15',
        direction: MovementDirection.inflow,
        quantity: 24,
        reason: 'تجهيز أولي · مركز الأشرفية',
        at: DateTime.now().subtract(const Duration(days: 33))),
    InventoryMovement(
        id: 'mv9',
        itemId: 'i15',
        direction: MovementDirection.outflow,
        quantity: 15,
        reason: 'إسعاف ميداني',
        at: DateTime.now().subtract(const Duration(days: 24))),
    InventoryMovement(
        id: 'mv10',
        itemId: 'i16',
        direction: MovementDirection.inflow,
        quantity: 20,
        reason: 'تسليم من المستودع المركزي',
        at: DateTime.now().subtract(const Duration(days: 31))),
    InventoryMovement(
        id: 'mv11',
        itemId: 'i16',
        direction: MovementDirection.outflow,
        quantity: 6,
        reason: 'صرف شفت مسائي',
        at: DateTime.now().subtract(const Duration(days: 22))),
    InventoryMovement(
        id: 'mv12',
        itemId: 'i17',
        direction: MovementDirection.outflow,
        quantity: 12,
        reason: 'استهلاك الأيام الأخيرة',
        at: DateTime.now().subtract(const Duration(days: 21))),
  ];

  int _nextItem = 18;

  Future<void> _latency() => Future<void>.delayed(
        Duration(milliseconds: 280 + _rand.nextInt(340)),
      );

  /// One rule for the three level values, applied everywhere stock changes,
  /// so a level can never disagree with the quantity beside it.
  static StockLevel _levelFor(int stock, int minimum) => stock == 0
      ? StockLevel.empty
      : stock < minimum
          ? StockLevel.low
          : StockLevel.ok;

  @override
  Future<Result<List<InventoryItem>>> listForDetachment(
      String detachmentId) async {
    await _latency();
    return Success(
        _items.where((i) => i.detachmentId == detachmentId).toList());
  }

  @override
  Future<Result<InventoryItem>> byId(String id) async {
    await _latency();
    final i = _items.indexWhere((e) => e.id == id);
    // Never fall back to another detachment's item.
    if (i < 0) return const Failure('لم يُعثر على الصنف.', code: 'not_found');
    return Success(_items[i]);
  }

  @override
  Future<Result<List<InventoryMovement>>> movementsForItem(
      String itemId) async {
    await _latency();
    final out = _movements.where((m) => m.itemId == itemId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return Success(out);
  }

  @override
  Future<Result<InventoryItem>> create({
    required String detachmentId,
    required String name,
    required String unit,
    required int openingStock,
    required int minimum,
    PackagingUnit openingUnit = PackagingUnit.individual,
    int unitsPerStrip = 1,
    int stripsPerCarton = 1,
    DateTime? expiresOn,
  }) async {
    await _latency();
    if (name.trim().isEmpty || unit.trim().isEmpty) {
      return const Failure('الاسم والوحدة مطلوبان.', code: 'validation');
    }
    if (openingStock < 0 ||
        minimum < 0 ||
        unitsPerStrip <= 0 ||
        stripsPerCarton <= 0) {
      return const Failure('أدخل رقما صحيحا.', code: 'validation');
    }
    final packaging = MedicinePackaging(
      unitsPerStrip: unitsPerStrip,
      stripsPerCarton: stripsPerCarton,
    );
    // Choosing strips or cartons without saying how many they hold would
    // store a quantity that reads as packages but counts as loose units.
    if (!packaging.supports(openingUnit)) {
      return const Failure(
        'حدّد عدد الوحدات في الشريط وعدد الشرائط في الكرتونة قبل اختيار هذه التعبئة.',
        code: 'packaging_required',
      );
    }
    final openingBaseUnits = packaging.baseUnitsFor(openingStock, openingUnit);
    final item = InventoryItem(
      id: 'i${_nextItem++}',
      detachmentId: detachmentId,
      name: name.trim(),
      unit: unit.trim(),
      currentStock: openingBaseUnits,
      minimum: minimum,
      expiresOn: expiresOn,
      level: _levelFor(openingBaseUnits, minimum),
      unitsPerStrip: unitsPerStrip,
      stripsPerCarton: stripsPerCarton,
      preferredUnit: openingUnit,
    );
    _items.add(item);
    if (openingStock > 0) {
      // The opening quantity is a real inflow. Without it the item's first
      // number has no movement behind it, and the history reads as if the
      // stock appeared on its own.
      _movements.add(InventoryMovement(
        id: 'mv_${DateTime.now().millisecondsSinceEpoch}',
        itemId: item.id,
        direction: MovementDirection.inflow,
        quantity: openingStock,
        packagingUnit: openingUnit,
        convertedBaseUnitQuantity: openingBaseUnits,
        itemName: item.name,
        source: 'inventory_setup',
        stockBefore: 0,
        stockAfter: openingBaseUnits,
        reason: 'رصيد افتتاحي',
        at: DateTime.now(),
      ));
    }
    return Success(item);
  }

  @override
  Future<Result<InventoryItem>> update({
    required String id,
    required String name,
    required String unit,
    required int minimum,
    int? unitsPerStrip,
    int? stripsPerCarton,
    PackagingUnit? preferredUnit,
    DateTime? expiresOn,
  }) async {
    await _latency();
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return const Failure('لم يُعثر على الصنف.', code: 'not_found');
    if (name.trim().isEmpty || unit.trim().isEmpty) {
      return const Failure('الاسم والوحدة مطلوبان.', code: 'validation');
    }
    if (minimum < 0 ||
        (unitsPerStrip != null && unitsPerStrip <= 0) ||
        (stripsPerCarton != null && stripsPerCarton <= 0)) {
      return const Failure('أدخل رقما صحيحا.', code: 'validation');
    }
    final current = _items[i];
    final nextPackaging = MedicinePackaging(
      unitsPerStrip: unitsPerStrip ?? current.unitsPerStrip,
      stripsPerCarton: stripsPerCarton ?? current.stripsPerCarton,
    );
    if (!nextPackaging.supports(preferredUnit ?? current.preferredUnit)) {
      return const Failure(
        'حدّد عدد الوحدات في الشريط وعدد الشرائط في الكرتونة قبل اختيار هذه التعبئة.',
        code: 'packaging_required',
      );
    }
    _items[i] = current.copyWith(
      name: name.trim(),
      unit: unit.trim(),
      minimum: minimum,
      expiresOn: expiresOn,
      unitsPerStrip: unitsPerStrip,
      stripsPerCarton: stripsPerCarton,
      preferredUnit: preferredUnit,
      // Raising the minimum can turn a healthy line into a low one, so the
      // level is recomputed rather than carried over.
      level: _levelFor(current.currentStock, minimum),
    );
    return Success(_items[i]);
  }

  @override
  Future<Result<void>> delete(String id) async {
    await _latency();
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return const Failure('لم يُعثر على الصنف.', code: 'not_found');
    _items.removeAt(i);
    _movements.removeWhere((m) => m.itemId == id);
    return const Success(null);
  }

  @override
  Future<Result<InventoryItem>> addMovement({
    required String itemId,
    required MovementDirection direction,
    required int quantity,
    required String reason,
    PackagingUnit packagingUnit = PackagingUnit.individual,
    String? source,
    String? performedBy,
    String? performedByName,
  }) async {
    await _latency();
    final i = _items.indexWhere((e) => e.id == itemId);
    if (i < 0) return const Failure('لم يُعثر على الصنف.', code: 'not_found');
    if (quantity <= 0) {
      return const Failure('الكمية يجب أن تكون أكبر من صفر.',
          code: 'validation');
    }
    final current = _items[i];
    if (!current.packaging.supports(packagingUnit)) {
      return const Failure(
        'هذا الصنف غير معرّف بهذه التعبئة.',
        code: 'packaging_unavailable',
      );
    }
    final converted = current.packaging.baseUnitsFor(quantity, packagingUnit);
    if (direction == MovementDirection.outflow &&
        converted > current.currentStock) {
      return const Failure('الكمية المطلوبة أكبر من المخزون الحالي.',
          code: 'insufficient_stock');
    }
    final before = current.currentStock;
    final delta =
        direction == MovementDirection.inflow ? converted : -converted;
    final newStock = before + delta;
    _items[i] = _items[i].copyWith(
      currentStock: newStock,
      level: _levelFor(newStock, _items[i].minimum),
    );
    _movements.add(InventoryMovement(
      id: 'mv_${DateTime.now().millisecondsSinceEpoch}',
      itemId: itemId,
      direction: direction,
      quantity: quantity,
      packagingUnit: packagingUnit,
      convertedBaseUnitQuantity: converted,
      itemName: current.name,
      source: source,
      performedBy: performedBy,
      performedByName: performedByName,
      stockBefore: before,
      stockAfter: newStock,
      reason: reason,
      at: DateTime.now(),
    ));
    return Success(_items[i]);
  }
}
