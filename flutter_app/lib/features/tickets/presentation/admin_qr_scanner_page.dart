import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';

class AdminQrScannerPage extends ConsumerStatefulWidget {
  const AdminQrScannerPage({super.key});

  @override
  ConsumerState<AdminQrScannerPage> createState() => _AdminQrScannerPageState();
}

class _AdminQrScannerPageState extends ConsumerState<AdminQrScannerPage> {
  final TextEditingController _ticketIdCtrl = TextEditingController();
  final TextEditingController _payloadCtrl = TextEditingController();
  bool _busy = false;
  String? _message;
  String? _lastPayload;

  @override
  void dispose() {
    _ticketIdCtrl.dispose();
    _payloadCtrl.dispose();
    super.dispose();
  }

  Future<void> _redeem(
      {required String ticketId, String qrPayload = ''}) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    if (ticketId.trim().isEmpty && qrPayload.trim().isEmpty) {
      setState(() => _message = 'Ticket ID or QR payload is required');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final result = await ref.read(ticketingRepositoryProvider).redeemTicket(
            token: token,
            ticketId: ticketId.trim(),
            qrPayload: qrPayload,
          );
      if (!mounted) return;
      setState(() => _message =
          'Redeemed: ${result.ticket.id} · order status ${result.orderStatus}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _onScanPayload(String payload) async {
    if (_busy || payload.trim().isEmpty) return;
    if (_lastPayload == payload) return;
    _lastPayload = payload;
    final ticketId = _extractTicketId(payload) ?? '';
    _payloadCtrl.text = payload;
    if (ticketId.isNotEmpty) {
      _ticketIdCtrl.text = ticketId;
    }
    await _redeem(ticketId: ticketId, qrPayload: payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin QR scanner'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
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
          const Text('Fallback manual redeem (if camera not available)'),
          const SizedBox(height: 8),
          TextField(
            controller: _ticketIdCtrl,
            decoration: const InputDecoration(labelText: 'Ticket ID'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _payloadCtrl,
            maxLines: 3,
            decoration:
                const InputDecoration(labelText: 'QR payload (optional)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _redeem(
                      ticketId: _ticketIdCtrl.text.trim(),
                      qrPayload: _payloadCtrl.text.trim(),
                    ),
            child: Text(_busy ? 'Redeeming…' : 'Redeem ticket'),
          ),
          if ((_message ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_message!),
          ],
        ],
      ),
    );
  }

  String? _extractTicketId(String token) {
    final parts = token.split('.');
    if (parts.length != 2) return null;
    try {
      final normalized = base64.normalize(parts.first);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(decoded);
      if (data is Map<String, dynamic>) {
        final ticketId = data['ticketId'];
        if (ticketId is String && ticketId.trim().isNotEmpty) {
          return ticketId.trim();
        }
      }
      if (data is Map) {
        final ticketId = data['ticketId'];
        if (ticketId is String && ticketId.trim().isNotEmpty) {
          return ticketId.trim();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
