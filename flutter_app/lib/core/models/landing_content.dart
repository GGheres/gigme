import '../utils/json_utils.dart';

/// LandingContent represents landing content.

class LandingContent {
  /// LandingContent handles landing content.
  const LandingContent({
    required this.heroEyebrow,
    required this.heroTitle,
    required this.heroDescription,
    required this.heroPrimaryCtaLabel,
    required this.aboutTitle,
    required this.aboutDescription,
    required this.partnersTitle,
    required this.partnersDescription,
    required this.footerText,
  });

  /// LandingContent handles landing content.

  factory LandingContent.fromJson(dynamic json) {
    final map = asMap(json);
    return LandingContent(
      heroEyebrow: asString(map['heroEyebrow']),
      heroTitle: asString(map['heroTitle']),
      heroDescription: asString(map['heroDescription']),
      heroPrimaryCtaLabel: asString(map['heroPrimaryCtaLabel']),
      aboutTitle: asString(map['aboutTitle']),
      aboutDescription: asString(map['aboutDescription']),
      partnersTitle: asString(map['partnersTitle']),
      partnersDescription: asString(map['partnersDescription']),
      footerText: asString(map['footerText']),
    ).withFallbackDefaults();
  }

  /// LandingContent handles landing content.

  factory LandingContent.defaults() {
    return const LandingContent(
      heroEyebrow: 'SPACEFESTIVAL',
      heroTitle: 'Spacefestival 2026',
      heroDescription:
          'Три экрана музыки, перформансов и нетворкинга. Лови билет, открывай Space App и следи за обновлениями в реальном времени.',
      heroPrimaryCtaLabel: 'Купить Билет',
      aboutTitle: 'О мероприятии',
      aboutDescription:
          'О мероприятии: сеты артистов, иммерсивные зоны, локальные бренды и серия партнерских активностей. Вся программа обновляется на лендинге.',
      partnersTitle: 'Партнеры и контакты',
      partnersDescription:
          'Партнерская сетка формируется. Следите за новыми анонсами.',
      footerText: 'SPACE',
    );
  }

  final String heroEyebrow;
  final String heroTitle;
  final String heroDescription;
  final String heroPrimaryCtaLabel;
  final String aboutTitle;
  final String aboutDescription;
  final String partnersTitle;
  final String partnersDescription;
  final String footerText;

  /// copyWith handles copy with.

  LandingContent copyWith({
    String? heroEyebrow,
    String? heroTitle,
    String? heroDescription,
    String? heroPrimaryCtaLabel,
    String? aboutTitle,
    String? aboutDescription,
    String? partnersTitle,
    String? partnersDescription,
    String? footerText,
  }) {
    return LandingContent(
      heroEyebrow: heroEyebrow ?? this.heroEyebrow,
      heroTitle: heroTitle ?? this.heroTitle,
      heroDescription: heroDescription ?? this.heroDescription,
      heroPrimaryCtaLabel: heroPrimaryCtaLabel ?? this.heroPrimaryCtaLabel,
      aboutTitle: aboutTitle ?? this.aboutTitle,
      aboutDescription: aboutDescription ?? this.aboutDescription,
      partnersTitle: partnersTitle ?? this.partnersTitle,
      partnersDescription: partnersDescription ?? this.partnersDescription,
      footerText: footerText ?? this.footerText,
    );
  }

  /// withFallbackDefaults configures fallback defaults.

  LandingContent withFallbackDefaults() {
    final defaults = LandingContent.defaults();
    return LandingContent(
      heroEyebrow: _pick(heroEyebrow, defaults.heroEyebrow),
      heroTitle: _pick(heroTitle, defaults.heroTitle),
      heroDescription: _pick(heroDescription, defaults.heroDescription),
      heroPrimaryCtaLabel:
          _pick(heroPrimaryCtaLabel, defaults.heroPrimaryCtaLabel),
      aboutTitle: _pick(aboutTitle, defaults.aboutTitle),
      aboutDescription: _pick(aboutDescription, defaults.aboutDescription),
      partnersTitle: _pick(partnersTitle, defaults.partnersTitle),
      partnersDescription:
          _pick(partnersDescription, defaults.partnersDescription),
      footerText: _pick(footerText, defaults.footerText),
    );
  }

  /// toJson handles to json.

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'heroEyebrow': heroEyebrow.trim(),
      'heroTitle': heroTitle.trim(),
      'heroDescription': heroDescription.trim(),
      'heroPrimaryCtaLabel': heroPrimaryCtaLabel.trim(),
      'aboutTitle': aboutTitle.trim(),
      'aboutDescription': aboutDescription.trim(),
      'partnersTitle': partnersTitle.trim(),
      'partnersDescription': partnersDescription.trim(),
      'footerText': footerText.trim(),
    };
  }
}

/// _pick handles internal pick behavior.

String _pick(String raw, String fallback) {
  final value = raw.trim();
  if (value.isEmpty) return fallback;
  return value;
}
