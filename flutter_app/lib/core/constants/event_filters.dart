class EventFilterOption {
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
  EventFilterOption(id: 'dating', label: 'Знакомства', icon: '💘'),
  EventFilterOption(id: 'party', label: 'Вечеринки', icon: '🎉'),
  EventFilterOption(id: 'travel', label: 'Путешествия', icon: '✈️'),
  EventFilterOption(id: 'fun', label: 'Развлечения', icon: '✨'),
  EventFilterOption(id: 'bar', label: 'Бары', icon: '🍸'),
  EventFilterOption(id: 'feedme', label: 'Еда', icon: '🍔'),
  EventFilterOption(id: 'sport', label: 'Спорт', icon: '⚽'),
  EventFilterOption(id: 'study', label: 'Обучение', icon: '📚'),
  EventFilterOption(id: 'business', label: 'Бизнес', icon: '💼'),
];

const int kMaxEventFilters = 3;
const int kNearbyRadiusMeters = 100000;
const int kMaxMediaCount = 5;
const int kMaxUploadBytes = 5 * 1024 * 1024;
