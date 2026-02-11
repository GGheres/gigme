import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/ticketing_repository.dart';
import '../domain/ticketing_models.dart';
import 'ticketing_ui_utils.dart';

class AdminProductsPage extends ConsumerStatefulWidget {
  const AdminProductsPage({super.key});

  @override
  ConsumerState<AdminProductsPage> createState() => _AdminProductsPageState();
}

class _AdminProductsPageState extends ConsumerState<AdminProductsPage> {
  final TextEditingController _eventCtrl = TextEditingController();
  final TextEditingController _ticketPriceCtrl = TextEditingController();
  final TextEditingController _transferPriceCtrl = TextEditingController();
  final TextEditingController _transferTimeCtrl = TextEditingController();
  final TextEditingController _transferPickupCtrl = TextEditingController();
  final TextEditingController _transferNotesCtrl = TextEditingController();

  String _ticketType = 'SINGLE';
  String _transferDirection = 'THERE';

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<TicketProductModel> _ticketProducts = <TicketProductModel>[];
  List<TransferProductModel> _transferProducts = <TransferProductModel>[];

  @override
  void initState() {
    super.initState();
    _ticketPriceCtrl.text = '0';
    _transferPriceCtrl.text = '0';
    unawaited(_load());
  }

  @override
  void dispose() {
    _eventCtrl.dispose();
    _ticketPriceCtrl.dispose();
    _transferPriceCtrl.dispose();
    _transferTimeCtrl.dispose();
    _transferPickupCtrl.dispose();
    _transferNotesCtrl.dispose();
    super.dispose();
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
    final eventId = int.tryParse(_eventCtrl.text.trim());

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(ticketingRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repo.listAdminTicketProducts(
            token: token, eventId: (eventId ?? 0) > 0 ? eventId : null),
        repo.listAdminTransferProducts(
            token: token, eventId: (eventId ?? 0) > 0 ? eventId : null),
      ]);
      if (!mounted) return;
      setState(() {
        _ticketProducts = results[0] as List<TicketProductModel>;
        _transferProducts = results[1] as List<TransferProductModel>;
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

  Future<void> _createTicketProduct() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    final eventId = int.tryParse(_eventCtrl.text.trim()) ?? 0;
    final price = int.tryParse(_ticketPriceCtrl.text.trim()) ?? -1;
    if (token.isEmpty || eventId <= 0 || price < 0) {
      _showMessage('Event ID and valid ticket price are required');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(ticketingRepositoryProvider).createAdminTicketProduct(
            token: token,
            eventId: eventId,
            type: _ticketType,
            priceCents: price,
          );
      _showMessage('Ticket product created');
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTransferProduct() async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    final eventId = int.tryParse(_eventCtrl.text.trim()) ?? 0;
    final price = int.tryParse(_transferPriceCtrl.text.trim()) ?? -1;
    if (token.isEmpty || eventId <= 0 || price < 0) {
      _showMessage('Event ID and valid transfer price are required');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(ticketingRepositoryProvider).createAdminTransferProduct(
        token: token,
        eventId: eventId,
        direction: _transferDirection,
        priceCents: price,
        info: <String, dynamic>{
          'time': _transferTimeCtrl.text.trim(),
          'pickupPoint': _transferPickupCtrl.text.trim(),
          'notes': _transferNotesCtrl.text.trim(),
        },
      );
      _showMessage('Transfer product created');
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTicketProduct(String id) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .deleteAdminTicketProduct(token: token, productId: id);
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTransferProduct(String id) async {
    final token = ref.read(authControllerProvider).state.token?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketingRepositoryProvider)
          .deleteAdminTransferProduct(token: token, productId: id);
      await _load();
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin products'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if ((_error ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                TextField(
                  controller: _eventCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Event ID (required for create/filter)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: _load, child: const Text('Apply event filter')),
                const SizedBox(height: 14),
                Text('Create ticket product',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _ticketType,
                        items: const [
                          DropdownMenuItem(
                              value: 'SINGLE', child: Text('SINGLE')),
                          DropdownMenuItem(
                              value: 'GROUP2', child: Text('GROUP2')),
                          DropdownMenuItem(
                              value: 'GROUP10', child: Text('GROUP10')),
                        ],
                        onChanged: (value) =>
                            setState(() => _ticketType = value ?? 'SINGLE'),
                        decoration: const InputDecoration(labelText: 'Type'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ticketPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Price cents'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _createTicketProduct,
                  child: Text(_busy ? 'Please wait…' : 'Create ticket product'),
                ),
                const SizedBox(height: 14),
                Text('Create transfer product',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _transferDirection,
                  decoration: const InputDecoration(labelText: 'Direction'),
                  items: const [
                    DropdownMenuItem(value: 'THERE', child: Text('THERE')),
                    DropdownMenuItem(value: 'BACK', child: Text('BACK')),
                    DropdownMenuItem(
                        value: 'ROUNDTRIP', child: Text('ROUNDTRIP')),
                  ],
                  onChanged: (value) =>
                      setState(() => _transferDirection = value ?? 'THERE'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _transferPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price cents'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _transferTimeCtrl,
                  decoration: const InputDecoration(labelText: 'Transfer time'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _transferPickupCtrl,
                  decoration: const InputDecoration(labelText: 'Pickup point'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _transferNotesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _createTransferProduct,
                  child:
                      Text(_busy ? 'Please wait…' : 'Create transfer product'),
                ),
                const SizedBox(height: 16),
                Text('Ticket products (${_ticketProducts.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._ticketProducts.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(
                          '${item.type} · ${formatMoney(item.priceCents)}'),
                      subtitle: Text(
                          'Event ${item.eventId} · sold ${item.soldCount} · active ${item.isActive}'),
                      trailing: IconButton(
                        onPressed:
                            _busy ? null : () => _deleteTicketProduct(item.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Transfer products (${_transferProducts.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._transferProducts.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(
                          '${item.direction} · ${formatMoney(item.priceCents)}'),
                      subtitle: Text(
                          'Event ${item.eventId} · ${item.infoLabel} · active ${item.isActive}'),
                      trailing: IconButton(
                        onPressed: _busy
                            ? null
                            : () => _deleteTransferProduct(item.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
