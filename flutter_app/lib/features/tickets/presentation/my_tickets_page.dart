import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

class MyTicketsPage extends ConsumerStatefulWidget {
  const MyTicketsPage({super.key});

  @override
  ConsumerState<MyTicketsPage> createState() => _MyTicketsPageState();
}

class _MyTicketsPageState extends ConsumerState<MyTicketsPage> {
  bool _loading = true;
  String? _error;
  List<TicketModel> _tickets = <TicketModel>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Authorization required';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ref
          .read(ticketingRepositoryProvider)
          .listMyTickets(token: token);
      if (!mounted) return;
      setState(() {
        _tickets = response.items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My tickets'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text(_error!))
              : _tickets.isEmpty
                  ? const Center(child: Text('No tickets yet'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _tickets.length,
                      itemBuilder: (context, index) {
                        final ticket = _tickets[index];
                        final status = ticket.status;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: statusTint(status),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Ticket ${ticket.id}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Chip(
                                      label: Text(status),
                                      backgroundColor:
                                          statusColor(status, context)
                                              .withValues(alpha: 0.12),
                                      side: BorderSide(
                                          color: statusColor(status, context)),
                                      labelStyle: TextStyle(
                                          color: statusColor(status, context),
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                    'Type: ${ticket.ticketType}  ·  Qty: ${ticket.quantity}'),
                                if (ticket.redeemedAt != null)
                                  Text(
                                      'Redeemed at: ${ticket.redeemedAt!.toLocal()}'),
                                const SizedBox(height: 10),
                                if (ticket.qrPayload.trim().isNotEmpty)
                                  Center(
                                    child: QrImageView(
                                      data: ticket.qrPayload,
                                      size: 180,
                                      backgroundColor: Colors.white,
                                    ),
                                  )
                                else
                                  const Text(
                                      'QR will be available after payment confirmation.'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
