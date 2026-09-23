enum StockLevel { ok, low, empty }

enum PackagingUnit { individual, strip, carton }

class MedicinePackaging {
  const MedicinePackaging({
    this.unitsPerStrip = 1,
    this.stripsPerCarton = 1,
  })  : assert(unitsPerStrip > 0),
        assert(stripsPerCarton > 0);

  final int unitsPerStrip;
  final int stripsPerCarton;

  /// Whether this item is really packaged in [unit]. A one-to-one
  /// conversion means the packaging was never configured, so accepting
  /// "three strips" there would silently record three loose units.
  bool supports(PackagingUnit unit) => switch (unit) {
        PackagingUnit.individual => true,
        PackagingUnit.strip => unitsPerStrip > 1,
        PackagingUnit.carton => unitsPerStrip > 1 && stripsPerCarton > 1,
      };

  int baseUnitsFor(int quantity, PackagingUnit unit) => switch (unit) {
        PackagingUnit.individual => quantity,
        PackagingUnit.strip => quantity * unitsPerStrip,
        PackagingUnit.carton => quantity * stripsPerCarton * unitsPerStrip,
      };

  PackagingBreakdown breakdown(int baseUnits) {
    final cartonSize = stripsPerCarton * unitsPerStrip;
    final cartons = cartonSize > 1 ? baseUnits ~/ cartonSize : 0;
    final afterCartons = baseUnits - cartons * cartonSize;
    final strips = unitsPerStrip > 1 ? afterCartons ~/ unitsPerStrip : 0;
    final individuals = afterCartons - strips * unitsPerStrip;
    return PackagingBreakdown(
      cartons: cartons,
      strips: strips,
      individuals: individuals,
    );
  }
}

class PackagingBreakdown {
  const PackagingBreakdown({
    required this.cartons,
    required this.strips,
    required this.individuals,
  });

  final int cartons;
  final int strips;
  final int individuals;
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.detachmentId,
    required this.name,
    required this.unit,
    required this.currentStock,
    required this.minimum,
    required this.expiresOn,
    required this.level,
    this.unitsPerStrip = 1,
    this.stripsPerCarton = 1,
    this.preferredUnit = PackagingUnit.individual,
  });

  final String id;
  final String detachmentId;
  final String name;
  final String unit;
  final int currentStock;
  final int minimum;
  final DateTime? expiresOn;
  final StockLevel level;
  final int unitsPerStrip;
  final int stripsPerCarton;
  final PackagingUnit preferredUnit;

  MedicinePackaging get packaging => MedicinePackaging(
        unitsPerStrip: unitsPerStrip,
        stripsPerCarton: stripsPerCarton,
      );

  PackagingBreakdown get stockBreakdown => packaging.breakdown(currentStock);

  int? get daysToExpiry => expiresOn?.difference(DateTime.now()).inDays;

  bool get belowMinimum => currentStock < minimum;

  InventoryItem copyWith({
    int? currentStock,
    StockLevel? level,
    String? name,
    String? unit,
    int? minimum,
    DateTime? expiresOn,
    int? unitsPerStrip,
    int? stripsPerCarton,
    PackagingUnit? preferredUnit,
  }) =>
      InventoryItem(
        id: id,
        detachmentId: detachmentId,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        currentStock: currentStock ?? this.currentStock,
        minimum: minimum ?? this.minimum,
        expiresOn: expiresOn ?? this.expiresOn,
        level: level ?? this.level,
        unitsPerStrip: unitsPerStrip ?? this.unitsPerStrip,
        stripsPerCarton: stripsPerCarton ?? this.stripsPerCarton,
        preferredUnit: preferredUnit ?? this.preferredUnit,
      );

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id: j['id'] as String,
        detachmentId: j['detachmentId'] as String,
        name: j['name'] as String,
        unit: j['unit'] as String,
        currentStock: j['currentStock'] as int,
        minimum: j['minimum'] as int,
        expiresOn: j['expiresOn'] == null
            ? null
            : DateTime.parse(j['expiresOn'] as String),
        level: StockLevel.values.firstWhere(
          (level) => level.name == j['level'],
          orElse: () => (j['currentStock'] as int) == 0
              ? StockLevel.empty
              : StockLevel.ok,
        ),
        unitsPerStrip: (j['unitsPerStrip'] as int?) ?? 1,
        stripsPerCarton: (j['stripsPerCarton'] as int?) ?? 1,
        preferredUnit: PackagingUnit.values.firstWhere(
          (unit) => unit.name == j['preferredUnit'],
          orElse: () => PackagingUnit.individual,
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'detachmentId': detachmentId,
        'name': name,
        'unit': unit,
        'currentStock': currentStock,
        'minimum': minimum,
        if (expiresOn != null) 'expiresOn': expiresOn!.toIso8601String(),
        'level': level.name,
        'unitsPerStrip': unitsPerStrip,
        'stripsPerCarton': stripsPerCarton,
        'preferredUnit': preferredUnit.name,
      };
}

enum MovementDirection { inflow, outflow }

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.itemId,
    required this.direction,
    required this.quantity,
    required this.reason,
    required this.at,
    this.packagingUnit = PackagingUnit.individual,
    int? convertedBaseUnitQuantity,
    this.itemName,
    this.source,
    this.performedBy,
    this.performedByName,
    this.stockBefore,
    this.stockAfter,
  }) : convertedBaseUnitQuantity = convertedBaseUnitQuantity ?? quantity;

  final String id;
  final String itemId;
  final MovementDirection direction;
  final int quantity;
  final PackagingUnit packagingUnit;
  final int convertedBaseUnitQuantity;
  final String? itemName;

  /// Where the movement came from — the channel, e.g. the mobile app or the
  /// item's own opening balance.
  final String? source;

  /// Who recorded it. Null only when there is no session to attribute the
  /// movement to, which is the case for records written before this field
  /// existed.
  final String? performedBy;
  final String? performedByName;
  final int? stockBefore;
  final int? stockAfter;
  final String reason;
  final DateTime at;

  factory InventoryMovement.fromJson(Map<String, dynamic> j) =>
      InventoryMovement(
        id: j['id'] as String,
        itemId: j['itemId'] as String,
        direction: MovementDirection.values
            .firstWhere((d) => d.name == j['direction']),
        quantity: j['quantity'] as int,
        reason: j['reason'] as String,
        at: DateTime.parse(j['at'] as String),
        packagingUnit: PackagingUnit.values.firstWhere(
          (unit) => unit.name == j['packagingUnit'],
          orElse: () => PackagingUnit.individual,
        ),
        convertedBaseUnitQuantity:
            (j['convertedBaseUnitQuantity'] as int?) ?? j['quantity'] as int,
        itemName: j['itemName'] as String?,
        source: j['source'] as String?,
        performedBy: j['performedBy'] as String?,
        performedByName: j['performedByName'] as String?,
        stockBefore: j['stockBefore'] as int?,
        stockAfter: j['stockAfter'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemId': itemId,
        'direction': direction.name,
        'quantity': quantity,
        'reason': reason,
        'at': at.toIso8601String(),
        'packagingUnit': packagingUnit.name,
        'convertedBaseUnitQuantity': convertedBaseUnitQuantity,
        if (itemName != null) 'itemName': itemName,
        if (source != null) 'source': source,
        if (performedBy != null) 'performedBy': performedBy,
        if (performedByName != null) 'performedByName': performedByName,
        if (stockBefore != null) 'stockBefore': stockBefore,
        if (stockAfter != null) 'stockAfter': stockAfter,
      };
}
