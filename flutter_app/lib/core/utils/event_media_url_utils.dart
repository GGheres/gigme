/// buildEventMediaProxyUrl builds event media proxy url.
String buildEventMediaProxyUrl({
  required String apiUrl,
  required int eventId,
  required int index,
  String? accessKey,
}) {
  if (eventId <= 0 || index < 0) return '';

  final base = apiUrl.trim();
  if (base.isEmpty) return '';

  final parsed = Uri.tryParse(base);
  if (parsed == null) return '';

  final pathSegments = <String>[
    for (final segment in parsed.pathSegments)
      if (segment.isNotEmpty) segment,
    'media',
    'events',
    '$eventId',
    '$index',
  ];
  final key = (accessKey ?? '').trim();

  if (parsed.hasScheme || parsed.hasAuthority) {
    return parsed
        .replace(
          pathSegments: pathSegments,
          queryParameters:
              key.isEmpty ? null : <String, String>{'eventKey': key},
        )
        .toString();
  }

  final path = '/${pathSegments.join('/')}';
  if (key.isEmpty) return path;
  return '$path?eventKey=${Uri.encodeQueryComponent(key)}';
}
