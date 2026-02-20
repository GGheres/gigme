import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_toast.dart';

Future<void> copyToClipboard(
  BuildContext context, {
  required String text,
  String successMessage = 'Скопировано в буфер обмена',
  String emptyMessage = 'Нет текста для копирования',
}) async {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    AppToast.show(
      context,
      message: emptyMessage,
      tone: AppToastTone.warning,
    );
    return;
  }

  await Clipboard.setData(ClipboardData(text: normalized));
  if (!context.mounted) return;

  AppToast.show(
    context,
    message: successMessage,
    tone: AppToastTone.success,
  );
}
