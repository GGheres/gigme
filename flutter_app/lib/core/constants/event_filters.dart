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
  EventFilterOption(id: 'dating', label: 'Dating', icon: '💘'),
  EventFilterOption(id: 'party', label: 'Party', icon: '🎉'),
  EventFilterOption(id: 'travel', label: 'Travel', icon: '✈️'),
  EventFilterOption(id: 'fun', label: 'Fun', icon: '✨'),
  EventFilterOption(id: 'bar', label: 'Bar', icon: '🍸'),
  EventFilterOption(id: 'feedme', label: 'Food', icon: '🍔'),
  EventFilterOption(id: 'sport', label: 'Sport', icon: '⚽'),
  EventFilterOption(id: 'study', label: 'Study', icon: '📚'),
  EventFilterOption(id: 'business', label: 'Business', icon: '💼'),
];

const int kMaxEventFilters = 3;
const int kNearbyRadiusMeters = 100000;
const int kMaxMediaCount = 5;
const int kMaxUploadBytes = 5 * 1024 * 1024;
