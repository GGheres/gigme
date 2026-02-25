import 'package:flutter/material.dart';

/// AppShadows represents app shadows.

class AppShadows {
  /// AppShadows handles app shadows.
  const AppShadows._();

  static const List<BoxShadow> surface = <BoxShadow>[
    /// BoxShadow handles box shadow.
    BoxShadow(
      color: Color(0x1A0B1328),
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> hover = <BoxShadow>[
    /// BoxShadow handles box shadow.
    BoxShadow(
      color: Color(0x220B1328),
      blurRadius: 30,
      offset: Offset(0, 14),
    ),
  ];

  static const List<BoxShadow> button = <BoxShadow>[
    /// BoxShadow handles box shadow.
    BoxShadow(
      color: Color(0x335868F9),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> buttonHover = <BoxShadow>[
    /// BoxShadow handles box shadow.
    BoxShadow(
      color: Color(0x445868F9),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}
