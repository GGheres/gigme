import 'package:flutter/material.dart';

class AppShadows {
  const AppShadows._();

  static const List<BoxShadow> surface = <BoxShadow>[
    BoxShadow(
      color: Color(0x29141022),
      blurRadius: 28,
      offset: Offset(0, 12),
    ),
  ];

  static const List<BoxShadow> hover = <BoxShadow>[
    BoxShadow(
      color: Color(0x33141022),
      blurRadius: 34,
      offset: Offset(0, 16),
    ),
  ];

  static const List<BoxShadow> button = <BoxShadow>[
    BoxShadow(
      color: Color(0x266A4CFF),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> buttonHover = <BoxShadow>[
    BoxShadow(
      color: Color(0x336A4CFF),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];
}
