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
    required this.sonicStageTitle,
    required this.sonicStageDescription,
    required this.sonicStageImageUrl,
    required this.lensoundStageTitle,
    required this.lensoundStageDescription,
    required this.lensoundStageImageUrl,
    required this.spaceStageTitle,
    required this.spaceStageDescription,
    required this.spaceStageImageUrl,
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
      sonicStageTitle: asString(map['sonicStageTitle']),
      sonicStageDescription: asString(map['sonicStageDescription']),
      sonicStageImageUrl: asString(map['sonicStageImageUrl']),
      lensoundStageTitle: asString(map['lensoundStageTitle']),
      lensoundStageDescription: asString(map['lensoundStageDescription']),
      lensoundStageImageUrl: asString(map['lensoundStageImageUrl']),
      spaceStageTitle: asString(map['spaceStageTitle']),
      spaceStageDescription: asString(map['spaceStageDescription']),
      spaceStageImageUrl: asString(map['spaceStageImageUrl']),
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
      sonicStageTitle: 'Sonic Stage',
      sonicStageDescription:
          'Главная волна фестиваля: плотный звук, энергичные live-сеты и пик ночной программы для тех, кто приходит за движением.',
      sonicStageImageUrl: '',
      lensoundStageTitle: 'Lensound Stage',
      lensoundStageDescription:
          'Сцена для глубокого прослушивания: объемные электронные текстуры, аудиовизуальные переходы и более камерная атмосфера.',
      lensoundStageImageUrl: '',
      spaceStageTitle: 'Space Stage',
      spaceStageDescription:
          'Иммерсивная зона фестиваля: перформансы, экспериментальные форматы, встречи комьюнити и ощущение отдельной орбиты внутри события.',
      spaceStageImageUrl: '',
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
  final String sonicStageTitle;
  final String sonicStageDescription;
  final String sonicStageImageUrl;
  final String lensoundStageTitle;
  final String lensoundStageDescription;
  final String lensoundStageImageUrl;
  final String spaceStageTitle;
  final String spaceStageDescription;
  final String spaceStageImageUrl;
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
    String? sonicStageTitle,
    String? sonicStageDescription,
    String? sonicStageImageUrl,
    String? lensoundStageTitle,
    String? lensoundStageDescription,
    String? lensoundStageImageUrl,
    String? spaceStageTitle,
    String? spaceStageDescription,
    String? spaceStageImageUrl,
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
      sonicStageTitle: sonicStageTitle ?? this.sonicStageTitle,
      sonicStageDescription:
          sonicStageDescription ?? this.sonicStageDescription,
      sonicStageImageUrl: sonicStageImageUrl ?? this.sonicStageImageUrl,
      lensoundStageTitle: lensoundStageTitle ?? this.lensoundStageTitle,
      lensoundStageDescription:
          lensoundStageDescription ?? this.lensoundStageDescription,
      lensoundStageImageUrl:
          lensoundStageImageUrl ?? this.lensoundStageImageUrl,
      spaceStageTitle: spaceStageTitle ?? this.spaceStageTitle,
      spaceStageDescription:
          spaceStageDescription ?? this.spaceStageDescription,
      spaceStageImageUrl: spaceStageImageUrl ?? this.spaceStageImageUrl,
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
      sonicStageTitle: _pick(sonicStageTitle, defaults.sonicStageTitle),
      sonicStageDescription:
          _pick(sonicStageDescription, defaults.sonicStageDescription),
      sonicStageImageUrl: sonicStageImageUrl.trim(),
      lensoundStageTitle:
          _pick(lensoundStageTitle, defaults.lensoundStageTitle),
      lensoundStageDescription:
          _pick(lensoundStageDescription, defaults.lensoundStageDescription),
      lensoundStageImageUrl: lensoundStageImageUrl.trim(),
      spaceStageTitle: _pick(spaceStageTitle, defaults.spaceStageTitle),
      spaceStageDescription:
          _pick(spaceStageDescription, defaults.spaceStageDescription),
      spaceStageImageUrl: spaceStageImageUrl.trim(),
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
      'sonicStageTitle': sonicStageTitle.trim(),
      'sonicStageDescription': sonicStageDescription.trim(),
      'sonicStageImageUrl': sonicStageImageUrl.trim(),
      'lensoundStageTitle': lensoundStageTitle.trim(),
      'lensoundStageDescription': lensoundStageDescription.trim(),
      'lensoundStageImageUrl': lensoundStageImageUrl.trim(),
      'spaceStageTitle': spaceStageTitle.trim(),
      'spaceStageDescription': spaceStageDescription.trim(),
      'spaceStageImageUrl': spaceStageImageUrl.trim(),
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
