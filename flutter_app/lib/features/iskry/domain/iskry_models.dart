import '../../../core/utils/json_utils.dart';

/// IskryTransferProductModel represents a public ISKRY transfer product.
class IskryTransferProductModel {
  /// IskryTransferProductModel parses a backend transfer card.
  factory IskryTransferProductModel.fromJson(dynamic json) {
    final map = asMap(json);
    return IskryTransferProductModel(
      id: asString(map['id']),
      eventId: asInt(map['eventId']),
      name: asString(map['name']),
      direction: asString(map['direction']).toUpperCase(),
      priceCents: asInt(map['priceCents']),
      info: asMap(map['info']),
      capacity: asInt(map['capacity']),
      soldCount: asInt(map['soldCount']),
      availableSeats: asInt(map['availableSeats']),
      isActive: asBool(map['isActive']),
    );
  }

  /// IskryTransferProductModel stores the public transfer card payload.
  IskryTransferProductModel({
    required this.id,
    required this.eventId,
    required this.name,
    required this.direction,
    required this.priceCents,
    required this.info,
    required this.capacity,
    required this.soldCount,
    required this.availableSeats,
    required this.isActive,
  });

  final String id;
  final int eventId;
  final String name;
  final String direction;
  final int priceCents;
  final Map<String, dynamic> info;
  final int capacity;
  final int soldCount;
  final int availableSeats;
  final bool isActive;

  /// label returns a user-facing product title.
  String get label {
    if (name.trim().isNotEmpty) return name.trim();
    switch (direction) {
      case 'BACK':
        return 'Трансфер обратно';
      case 'ROUNDTRIP':
        return 'Трансфер туда и обратно';
      case 'THERE':
      default:
        return 'Трансфер туда';
    }
  }

  /// departurePoint returns a mapped departure point value when present.
  String get departurePoint => _stringField('pickupPoint', 'departurePoint');

  /// departureDateTime returns a mapped departure datetime/time value when present.
  String get departureDateTime => _stringField('departureDatetime', 'time');

  /// arrivalPoint returns a mapped arrival point value when present.
  String get arrivalPoint => _stringField('arrivalPoint');

  /// description returns a long-form product description when present.
  String get description => _stringField('description', 'notes');

  /// _stringField reads the first non-empty string from several info keys.
  String _stringField(String primary, [String secondary = '']) {
    final keys = <String>[primary];
    if (secondary.trim().isNotEmpty) {
      keys.add(secondary);
    }
    for (final key in keys) {
      final value = asString(info[key]).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }
}

/// IskryLandingModel represents the public /iskry payload.
class IskryLandingModel {
  /// IskryLandingModel parses a public landing response.
  factory IskryLandingModel.fromJson(dynamic json) {
    final map = asMap(json);
    return IskryLandingModel(
      eventId: asInt(map['eventId']),
      eventTitle: asString(map['eventTitle']),
      eventDescription: asString(map['eventDescription']),
      eventAccessKey: asString(map['eventAccessKey']),
      startsAt: asDateTime(map['startsAt']),
      transferPaymentEnabled: asBool(map['transferPaymentEnabled']),
      products:
          asList(
            map['products'],
          ).map(IskryTransferProductModel.fromJson).toList(),
    );
  }

  /// IskryLandingModel stores public event and transfer product data.
  IskryLandingModel({
    required this.eventId,
    required this.eventTitle,
    required this.eventDescription,
    required this.eventAccessKey,
    required this.startsAt,
    required this.transferPaymentEnabled,
    required this.products,
  });

  final int eventId;
  final String eventTitle;
  final String eventDescription;
  final String eventAccessKey;
  final DateTime? startsAt;
  final bool transferPaymentEnabled;
  final List<IskryTransferProductModel> products;
}
