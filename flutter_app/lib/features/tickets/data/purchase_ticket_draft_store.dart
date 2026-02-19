import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/json_utils.dart';

class PurchaseTicketDraft {
  PurchaseTicketDraft({
    required this.ticketQuantities,
    required this.selectedTransferId,
    required this.transferQty,
    required this.paymentMethod,
    required this.promoCode,
    required this.showPaymentCheckout,
  });

  factory PurchaseTicketDraft.fromJson(dynamic json) {
    final map = asMap(json);
    final rawQuantities = asMap(map['ticketQuantities']);
    final ticketQuantities = <String, int>{};
    rawQuantities.forEach((key, value) {
      final id = key.toString().trim();
      final quantity = asInt(value);
      if (id.isEmpty || quantity <= 0) return;
      ticketQuantities[id] = quantity;
    });

    final selectedTransferId = asString(map['selectedTransferId']).trim();

    return PurchaseTicketDraft(
      ticketQuantities: ticketQuantities,
      selectedTransferId:
          selectedTransferId.isNotEmpty ? selectedTransferId : null,
      transferQty: asInt(map['transferQty'], fallback: 1).clamp(1, 20).toInt(),
      paymentMethod: asString(map['paymentMethod'], fallback: 'PHONE'),
      promoCode: asString(map['promoCode']),
      showPaymentCheckout: asBool(map['showPaymentCheckout']),
    );
  }

  final Map<String, int> ticketQuantities;
  final String? selectedTransferId;
  final int transferQty;
  final String paymentMethod;
  final String promoCode;
  final bool showPaymentCheckout;

  bool get hasMeaningfulData {
    final hasTickets = ticketQuantities.values.any((value) => value > 0);
    return hasTickets ||
        (selectedTransferId ?? '').trim().isNotEmpty ||
        paymentMethod.trim().toUpperCase() != 'PHONE' ||
        promoCode.trim().isNotEmpty ||
        showPaymentCheckout;
  }

  Map<String, dynamic> toJson() {
    final cleanQuantities = <String, int>{};
    ticketQuantities.forEach((key, value) {
      final id = key.trim();
      if (id.isEmpty || value <= 0) return;
      cleanQuantities[id] = value;
    });

    return <String, dynamic>{
      'ticketQuantities': cleanQuantities,
      'selectedTransferId': selectedTransferId?.trim(),
      'transferQty': transferQty.clamp(1, 20),
      'paymentMethod': paymentMethod.trim().isEmpty ? 'PHONE' : paymentMethod,
      'promoCode': promoCode.trim(),
      'showPaymentCheckout': showPaymentCheckout,
    };
  }
}

class PurchaseTicketDraftStore {
  static const String _storagePrefix = 'gigme_purchase_ticket_draft_';

  Future<PurchaseTicketDraft?> load({required int eventId}) async {
    if (eventId <= 0) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(eventId));
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      final draft = PurchaseTicketDraft.fromJson(decoded);
      if (!draft.hasMeaningfulData) return null;
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required int eventId,
    required PurchaseTicketDraft draft,
  }) async {
    if (eventId <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    if (!draft.hasMeaningfulData) {
      await prefs.remove(_key(eventId));
      return;
    }
    await prefs.setString(_key(eventId), jsonEncode(draft.toJson()));
  }

  Future<void> clear({required int eventId}) async {
    if (eventId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(eventId));
  }

  String _key(int eventId) => '$_storagePrefix$eventId';
}
