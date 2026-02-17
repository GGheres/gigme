import 'package:flutter_test/flutter_test.dart';

import 'package:gigme_flutter/features/tickets/domain/ticketing_models.dart';

void main() {
  group('TicketModel.status', () {
    test('uses orderStatus from backend when provided', () {
      final ticket = TicketModel.fromJson({
        'id': 't-1',
        'orderId': 'o-1',
        'orderStatus': 'CANCELED',
        'userId': 1,
        'eventId': 10,
        'ticketType': 'SINGLE',
        'quantity': 1,
        'qrPayload': '',
        'redeemedAt': null,
        'createdAt': '2026-02-17T10:00:00Z',
      });

      expect(ticket.status, 'CANCELED');
    });

    test('falls back to PAID when orderStatus is missing and not redeemed', () {
      final ticket = TicketModel.fromJson({
        'id': 't-2',
        'orderId': 'o-2',
        'userId': 1,
        'eventId': 10,
        'ticketType': 'SINGLE',
        'quantity': 1,
        'qrPayload': '',
        'redeemedAt': null,
        'createdAt': '2026-02-17T10:00:00Z',
      });

      expect(ticket.status, 'PAID');
    });

    test('falls back to REDEEMED when orderStatus is missing and redeemed', () {
      final ticket = TicketModel.fromJson({
        'id': 't-3',
        'orderId': 'o-3',
        'userId': 1,
        'eventId': 10,
        'ticketType': 'SINGLE',
        'quantity': 1,
        'qrPayload': '',
        'redeemedAt': '2026-02-17T10:30:00Z',
        'createdAt': '2026-02-17T10:00:00Z',
      });

      expect(ticket.status, 'REDEEMED');
    });
  });
}
