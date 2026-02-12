import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';

class AdminQrScannerPage extends ConsumerStatefulWidget {
  const AdminQrScannerPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  ConsumerState<AdminQrScannerPage> createState() => _AdminQrScannerPageState();
}

enum _ScannerMessageTone {
  info,
  success,
  error,
}

class _DecodedQrPayload {
  const _DecodedQrPayload({
    required this.ticketId,
    required this.eventId,
    required this.userId,
    required this.ticketType,
    required this.quantity,
  });

  final String ticketId;
  final int eventId;
  final int userId;
  final String ticketType;
  final int quantity;
}

class _AdminQrScannerPageState extends ConsumerState<AdminQrScannerPage> {
  final TextEditingController _ticketIdCtrl = TextEditingController();
  final TextEditingController _payloadCtrl = TextEditingController();
  bool _busy = false;
  String? _message;
  _ScannerMessageTone _messageTone = _ScannerMessageTone.info;
  String? _lastPayload;
  _DecodedQrPayload? _decodedQr;

  @override
  void dispose() {
    _ticketIdCtrl.dispose();
    _payloadCtrl.dispose();
    super.dispose();
  }

  Future<void> _redeem(
      {required String ticketId, String qrPayload = ''}) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) {
      setState(() {
        _message = 'Требуется авторизация';
        _messageTone = _ScannerMessageTone.error;
      });
      return;
    }
    if (ticketId.trim().isEmpty && qrPayload.trim().isEmpty) {
      setState(() {
        _message = 'Укажите ticketId или qrPayload';
        _messageTone = _ScannerMessageTone.error;
      });
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final result = await ref.read(ticketingRepositoryProvider).redeemTicket(
            token: token,
            ticketId: ticketId.trim(),
            qrPayload: qrPayload,
          );
      if (!mounted) return;
      setState(() {
        _message =
            'Билет ${result.ticket.id} пропущен. Статус заказа: ${result.orderStatus}';
        _messageTone = _ScannerMessageTone.success;
        _ticketIdCtrl.text = result.ticket.id;
        _decodedQr = _DecodedQrPayload(
          ticketId: result.ticket.id,
          eventId: result.ticket.eventId,
          userId: result.ticket.userId,
          ticketType: result.ticket.ticketType,
          quantity: result.ticket.quantity,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = '$error';
        _messageTone = _ScannerMessageTone.error;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _onScanPayload(String payload) {
    if (_busy || payload.trim().isEmpty) return;
    if (_lastPayload == payload) return;

    final decoded = _decodePayload(payload);
    setState(() {
      _lastPayload = payload;
      _payloadCtrl.text = payload;
      _decodedQr = decoded;
      if (decoded != null && decoded.ticketId.isNotEmpty) {
        _ticketIdCtrl.text = decoded.ticketId;
      }
      if (decoded == null) {
        _message =
            'QR считан, но данные билета не распознаны. Можно проверить вручную.';
        _messageTone = _ScannerMessageTone.error;
      } else {
        _message =
            'QR считан: билет ${decoded.ticketId}. Нажмите «Пропустить билет».';
        _messageTone = _ScannerMessageTone.info;
      }
    });
  }

  void _clearForm() {
    setState(() {
      _ticketIdCtrl.clear();
      _payloadCtrl.clear();
      _decodedQr = null;
      _lastPayload = null;
      _message = null;
      _messageTone = _ScannerMessageTone.info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Сканируйте QR и подтвердите проход кнопкой ниже'),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 280,
            child: MobileScanner(
              onDetect: (capture) {
                final code = capture.barcodes.isNotEmpty
                    ? (capture.barcodes.first.rawValue ?? '')
                    : '';
                if (code.trim().isEmpty) return;
                _onScanPayload(code.trim());
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_decodedQr != null) ...[
          Card(
            color: const Color(0xFFE3F2FD),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Билет: ${_decodedQr!.ticketId}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Событие: ${_decodedQr!.eventId}'),
                  Text('Пользователь: ${_decodedQr!.userId}'),
                  Text('Тип: ${_decodedQr!.ticketType}'),
                  Text('Кол-во людей: ${_decodedQr!.quantity}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const Text('Ручной ввод (если камера недоступна)'),
        const SizedBox(height: 8),
        TextField(
          controller: _ticketIdCtrl,
          decoration: const InputDecoration(labelText: 'Ticket ID'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _payloadCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'QR payload (optional)'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _redeem(
                          ticketId: _ticketIdCtrl.text.trim(),
                          qrPayload: _payloadCtrl.text.trim(),
                        ),
                child: Text(_busy ? 'Проверка…' : 'Пропустить билет'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : _clearForm,
              child: const Text('Сбросить'),
            ),
          ],
        ),
        if ((_message ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _messageBackgroundColor(),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_message!),
          ),
        ],
      ],
    );

    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin QR scanner'),
      ),
      body: body,
    );
  }

  _DecodedQrPayload? _decodePayload(String token) {
    final parts = token.split('.');
    if (parts.length != 2) return null;
    try {
      final normalized = base64.normalize(parts.first);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(decoded);
      final map = data is Map ? data : null;
      if (map == null) return null;

      final ticketId = (map['ticketId'] ?? '').toString().trim();
      final eventId = _parseInt(map['eventId']);
      final userId = _parseInt(map['userId']);
      final ticketType = (map['ticketType'] ?? '').toString().trim();
      final quantity = _parseInt(map['quantity']);

      if (ticketId.isEmpty ||
          eventId <= 0 ||
          userId <= 0 ||
          ticketType.isEmpty ||
          quantity <= 0) {
        return null;
      }

      return _DecodedQrPayload(
        ticketId: ticketId,
        eventId: eventId,
        userId: userId,
        ticketType: ticketType,
        quantity: quantity,
      );
    } catch (_) {
      return null;
    }
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  Color _messageBackgroundColor() {
    switch (_messageTone) {
      case _ScannerMessageTone.success:
        return const Color(0xFFE8F5E9);
      case _ScannerMessageTone.error:
        return const Color(0xFFFFEBEE);
      case _ScannerMessageTone.info:
        return const Color(0xFFE3F2FD);
    }
  }
}
