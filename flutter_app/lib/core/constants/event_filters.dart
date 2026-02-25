/// EventFilterOption represents event filter option.
class EventFilterOption {
  /// EventFilterOption handles event filter option.
  const EventFilterOption({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final String icon;
}

const List<EventFilterOption> kEventFilters = [
  /// EventFilterOption handles event filter option.
  EventFilterOption(id: 'dating', label: 'Знакомства', icon: '💘'),

  /// EventFilterOption handles event filter option.
  EventFilterOption(id: 'party', label: 'Вечеринки', icon: '🎉'),

  /// EventFilterOption handles event filter option.
  EventFilterOption(id: 'travel', label: 'Путешествия', icon: '✈️'),

  /// EventFilterOption handles event filter option.
  EventFilterOption(id: 'fun', label: 'Развлечения', icon: '✨'),

  /// EventFilterOption handles event filter option.
  EventFilterOption(id: 'bar', label: 'Бары', icon: '🍸'),

  /// EventFilterOption handles event filter option.
  EventFilterOption(id: 'feedme', label: 'Еда', icon: '🍔'),

  /// EventFilterOption handles event filter option.
  EventFilterOption(id: 'sport', label: 'Спорт', icon: '⚽'),

  /// EventFilterOption handles event filter option.
  EventFilterOption(id: 'study', label: 'Обучение', icon: '📚'),

  /// EventFilterOption handles event filter option.
  EventFilterOption(id: 'business', label: 'Бизнес', icon: '💼'),
];

const int kMaxEventFilters = 3;
const int kNearbyRadiusMeters = 100000;
const int kMaxMediaCount = 5;
const int kMaxUploadBytes = 5 * 1024 * 1024;
