import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_toast.dart';

/// copyToClipboard handles copy to clipboard.

Future<void> copyToClipboard(
  BuildContext context, {
  required String text,
  String successMessage = 'Скопировано в буфер обмена',
  String emptyMessage = 'Нет текста для копирования',
  String errorMessage =
      'Не удалось скопировать. Проверьте доступ к буферу обмена.',
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

  try {
    await Clipboard.setData(ClipboardData(text: normalized));
  } catch (_) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: errorMessage,
      tone: AppToastTone.error,
    );
    return;
  }

  if (!context.mounted) return;

  AppToast.show(
    context,
    message: successMessage,
    tone: AppToastTone.success,
  );
}
