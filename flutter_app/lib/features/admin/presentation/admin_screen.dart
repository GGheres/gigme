import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/models/admin_models.dart';
import '../../../core/models/landing_content.dart';
import '../../../core/models/landing_event.dart';
import '../../../core/utils/date_time_utils.dart';
import '../../../core/widgets/premium_loading_view.dart';
import '../../auth/application/auth_controller.dart';
import '../../tickets/presentation/admin_orders_page.dart';
import '../../tickets/presentation/admin_products_page.dart';
import '../../tickets/presentation/admin_qr_scanner_page.dart';
import '../../tickets/presentation/admin_stats_page.dart';
import '../data/admin_repository.dart';

// TODO(ui-migration): convert admin tabs/tables/forms to AppScaffold + tokenized App* components.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  final TextEditingController _adminLoginCtrl = TextEditingController();
  final TextEditingController _adminPasswordCtrl = TextEditingController();
  final TextEditingController _adminTelegramIdCtrl = TextEditingController();
  bool _adminLoginBusy = false;
  String? _adminLoginError;

  final TextEditingController _usersSearchCtrl = TextEditingController();
  String _usersBlockedFilter = 'all';
  bool _usersLoading = false;
  String? _usersError;
  List<AdminUser> _users = <AdminUser>[];
  int _usersTotal = 0;

  final TextEditingController _blockReasonCtrl = TextEditingController();
  bool _userDetailLoading = false;
  String? _userDetailError;
  AdminUserDetailResponse? _userDetail;
  bool _userBlockBusy = false;

  String _broadcastAudience = 'all';
  final TextEditingController _broadcastMessageCtrl = TextEditingController();
  final TextEditingController _broadcastUserIdsCtrl = TextEditingController();
  final TextEditingController _broadcastMinBalanceCtrl =
      TextEditingController();
  final TextEditingController _broadcastLastSeenAfterCtrl =
      TextEditingController();
  final List<_BroadcastButtonDraft> _broadcastButtons = [
    _BroadcastButtonDraft(text: '', url: ''),
  ];
  bool _broadcastsLoading = false;
  bool _broadcastCreateBusy = false;
  int? _broadcastStartBusyId;
  String? _broadcastsError;
  List<AdminBroadcast> _broadcasts = <AdminBroadcast>[];
  int _broadcastsTotal = 0;

  final TextEditingController _parserSourceTitleCtrl = TextEditingController();
  final TextEditingController _parserSourceInputCtrl = TextEditingController();
  String _parserSourceType = 'auto';
  bool _parserSourcesLoading = false;
  bool _parserCreateSourceBusy = false;
  int? _parserSourceBusyId;
  String? _parserError;
  List<AdminParserSource> _parserSources = <AdminParserSource>[];
  int _parserSourcesTotal = 0;

  final TextEditingController _parserQuickInputCtrl = TextEditingController();
  String _parserQuickType = 'auto';
  bool _parserQuickBusy = false;

  String _parsedStatusFilter = 'all';
  bool _parsedLoading = false;
  List<AdminParsedEvent> _parsedEvents = <AdminParsedEvent>[];
  int _parsedTotal = 0;
  int? _parserGeocodeBusyId;
  int? _parserImportBusyId;
  int? _parserRejectBusyId;
  int? _parserDeleteBusyId;
  final Map<int, _ParserDraft> _parserDrafts = <int, _ParserDraft>{};

  final TextEditingController _landingEventIdCtrl = TextEditingController();
  final TextEditingController _landingHeroEyebrowCtrl = TextEditingController();
  final TextEditingController _landingHeroTitleCtrl = TextEditingController();
  final TextEditingController _landingHeroDescriptionCtrl =
      TextEditingController();
  final TextEditingController _landingHeroCtaCtrl = TextEditingController();
  final TextEditingController _landingAboutTitleCtrl = TextEditingController();
  final TextEditingController _landingAboutDescriptionCtrl =
      TextEditingController();
  final TextEditingController _landingPartnersTitleCtrl =
      TextEditingController();
  final TextEditingController _landingPartnersDescriptionCtrl =
      TextEditingController();
  final TextEditingController _landingFooterCtrl = TextEditingController();
  final TextEditingController _landingImageUrlCtrl = TextEditingController();
  bool _landingPublishedValue = true;
  bool _landingLoading = false;
  bool _landingBusy = false;
  bool _landingImageBusy = false;
  bool _landingContentBusy = false;
  int? _landingActionEventId;
  String? _landingError;
  List<LandingEvent> _landingEvents = <LandingEvent>[];
  int _landingTotal = 0;

  bool _accessDenied = false;
  String? _lastAuthedToken;

  String? get _token => ref.read(authControllerProvider).state.token;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();

    _adminLoginCtrl.dispose();
    _adminPasswordCtrl.dispose();
    _adminTelegramIdCtrl.dispose();

    _usersSearchCtrl.dispose();
    _blockReasonCtrl.dispose();

    _broadcastMessageCtrl.dispose();
    _broadcastUserIdsCtrl.dispose();
    _broadcastMinBalanceCtrl.dispose();
    _broadcastLastSeenAfterCtrl.dispose();

    _parserSourceTitleCtrl.dispose();
    _parserSourceInputCtrl.dispose();
    _parserQuickInputCtrl.dispose();
    _landingEventIdCtrl.dispose();
    _landingHeroEyebrowCtrl.dispose();
    _landingHeroTitleCtrl.dispose();
    _landingHeroDescriptionCtrl.dispose();
    _landingHeroCtaCtrl.dispose();
    _landingAboutTitleCtrl.dispose();
    _landingAboutDescriptionCtrl.dispose();
    _landingPartnersTitleCtrl.dispose();
    _landingPartnersDescriptionCtrl.dispose();
    _landingFooterCtrl.dispose();
    _landingImageUrlCtrl.dispose();
    for (final item in _broadcastButtons) {
      item.dispose();
    }
    for (final draft in _parserDrafts.values) {
      draft.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).state;
    final token = authState.token?.trim() ?? '';

    if (token.isNotEmpty && token != _lastAuthedToken) {
      _lastAuthedToken = token;
      unawaited(_bootstrapLoads());
    }

    if (token.isEmpty) {
      _lastAuthedToken = null;
      return _buildAdminLogin();
    }

    if (_accessDenied) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(child: Text('Access denied (401/403).')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin panel'),
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.profile),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh all',
            onPressed: _bootstrapLoads,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Users'),
            Tab(text: 'Broadcasts'),
            Tab(text: 'Parser'),
            Tab(text: 'Orders'),
            Tab(text: 'Scanner'),
            Tab(text: 'Products'),
            Tab(text: 'Stats'),
            Tab(text: 'Landing'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersTab(),
          _buildBroadcastsTab(),
          _buildParserTab(),
          const AdminOrdersPage(embedded: true),
          const AdminQrScannerPage(embedded: true),
          const AdminProductsPage(embedded: true),
          const AdminStatsPage(embedded: true),
          _buildLandingTab(),
        ],
      ),
    );
  }

  Widget _buildAdminLogin() {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              TextField(
                controller: _adminLoginCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _adminPasswordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _adminTelegramIdCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Telegram ID (optional)'),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _adminLoginBusy ? null : _handleAdminLogin,
                child: Text(_adminLoginBusy ? 'Signing in…' : 'Sign in'),
              ),
              if ((_adminLoginError ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _adminLoginError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _usersSearchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Search by name/username/TG ID',
                ),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _usersBlockedFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _usersBlockedFilter = value);
                unawaited(_loadUsers());
              },
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _usersLoading ? null : _loadUsers,
              child: Text(_usersLoading ? 'Loading…' : 'Load'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if ((_usersError ?? '').trim().isNotEmpty)
          Text(_usersError!, style: const TextStyle(color: Colors.red)),
        Row(
          children: [
            Text('Total: $_usersTotal'),
          ],
        ),
        const SizedBox(height: 8),
        if (_users.isEmpty && !_usersLoading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No users found.'),
            ),
          )
        else
          ..._users.map(
            (user) => Card(
              child: ListTile(
                onTap: () => _openUserDetail(user.id),
                leading: CircleAvatar(
                  backgroundImage: user.photoUrl.trim().isEmpty
                      ? null
                      : NetworkImage(user.photoUrl),
                  child: user.photoUrl.trim().isEmpty
                      ? Text(user.displayName.trim().isNotEmpty
                          ? user.displayName
                              .trim()
                              .substring(0, 1)
                              .toUpperCase()
                          : 'U')
                      : null,
                ),
                title: Text(user.displayName),
                subtitle: Text(
                    '@${user.username.isEmpty ? 'no_username' : user.username} • TG ${user.telegramId}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${user.balanceTokens} GT'),
                    const SizedBox(height: 4),
                    Text(user.isBlocked ? 'Blocked' : 'Active'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBroadcastsTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create broadcast',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _broadcastAudience,
                  items: const [
                    DropdownMenuItem(
                        value: 'all', child: Text('All active users')),
                    DropdownMenuItem(
                        value: 'selected', child: Text('Selected user IDs')),
                    DropdownMenuItem(
                        value: 'filter', child: Text('Filter-based')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _broadcastAudience = value);
                  },
                  decoration: const InputDecoration(labelText: 'Audience'),
                ),
                const SizedBox(height: 10),
                if (_broadcastAudience == 'selected') ...[
                  TextField(
                    controller: _broadcastUserIdsCtrl,
                    decoration: const InputDecoration(
                        labelText: 'User IDs (comma-separated)'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_broadcastAudience == 'filter') ...[
                  TextField(
                    controller: _broadcastMinBalanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Min balance (optional)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _broadcastLastSeenAfterCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Last seen after (ISO, optional)',
                      hintText: '2026-02-08T10:30:00Z',
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _broadcastMessageCtrl,
                  maxLength: 4096,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Message'),
                ),
                const SizedBox(height: 6),
                Text('Buttons', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                ..._broadcastButtons.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: item.textCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Text'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: item.urlCtrl,
                            decoration: const InputDecoration(labelText: 'URL'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: _broadcastButtons.length <= 1
                              ? null
                              : () {
                                  setState(() {
                                    _broadcastButtons.removeAt(index).dispose();
                                  });
                                },
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _broadcastButtons
                          .add(_BroadcastButtonDraft(text: '', url: '')));
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add button'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _broadcastCreateBusy ? null : _createBroadcast,
                  child: Text(
                      _broadcastCreateBusy ? 'Creating…' : 'Create broadcast'),
                ),
                if ((_broadcastsError ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_broadcastsError!,
                      style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('History ($_broadcastsTotal)'),
            const Spacer(),
            TextButton.icon(
              onPressed: _broadcastsLoading ? null : _loadBroadcasts,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ],
        ),
        if (_broadcasts.isEmpty && !_broadcastsLoading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No broadcasts yet.'),
            ),
          )
        else
          ..._broadcasts.map(
            (item) => Card(
              child: ListTile(
                title: Text('#${item.id} • ${item.audience} • ${item.status}'),
                subtitle: Text(
                  '${item.sent}/${item.failed}/${item.targeted} • ${formatDateTime(item.createdAt)}\n${item.message}',
                ),
                isThreeLine: true,
                trailing: item.status == 'pending'
                    ? OutlinedButton(
                        onPressed: _broadcastStartBusyId == item.id
                            ? null
                            : () => _startBroadcast(item.id),
                        child: Text(_broadcastStartBusyId == item.id
                            ? 'Starting…'
                            : 'Start'),
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildParserTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Parser sources',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _parserSourceTitleCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Title (optional)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _parserSourceInputCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Source input (URL or channel)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _parserSourceType,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('auto')),
                    DropdownMenuItem(
                        value: 'telegram', child: Text('telegram')),
                    DropdownMenuItem(value: 'web', child: Text('web')),
                    DropdownMenuItem(
                        value: 'instagram', child: Text('instagram')),
                    DropdownMenuItem(value: 'vk', child: Text('vk')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _parserSourceType = value);
                  },
                  decoration: const InputDecoration(labelText: 'Source type'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed:
                      _parserCreateSourceBusy ? null : _createParserSource,
                  child:
                      Text(_parserCreateSourceBusy ? 'Saving…' : 'Add source'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Sources: $_parserSourcesTotal'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed:
                          _parserSourcesLoading ? null : _loadParserSources,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                ..._parserSources.map(
                  (source) => Card(
                    child: ListTile(
                      title: Text(source.title.trim().isEmpty
                          ? '#${source.id}'
                          : source.title),
                      subtitle: Text(
                          '${source.sourceType} • ${source.input}\nLast parsed: ${formatDateTime(source.lastParsedAt)}'),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          OutlinedButton(
                            onPressed: _parserSourceBusyId == source.id
                                ? null
                                : () => _parseSource(source.id),
                            child: Text(_parserSourceBusyId == source.id
                                ? '…'
                                : 'Parse'),
                          ),
                          OutlinedButton(
                            onPressed: _parserSourceBusyId == source.id
                                ? null
                                : () => _toggleParserSource(source),
                            child: Text(source.isActive ? 'Disable' : 'Enable'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quick parse',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _parserQuickInputCtrl,
                  decoration:
                      const InputDecoration(labelText: 'URL or channel'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _parserQuickType,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('auto')),
                    DropdownMenuItem(
                        value: 'telegram', child: Text('telegram')),
                    DropdownMenuItem(value: 'web', child: Text('web')),
                    DropdownMenuItem(
                        value: 'instagram', child: Text('instagram')),
                    DropdownMenuItem(value: 'vk', child: Text('vk')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _parserQuickType = value);
                  },
                  decoration: const InputDecoration(labelText: 'Source type'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _parserQuickBusy ? null : _parseQuick,
                  child: Text(_parserQuickBusy ? 'Parsing…' : 'Run parse'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            DropdownButton<String>(
              value: _parsedStatusFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All statuses')),
                DropdownMenuItem(value: 'pending', child: Text('pending')),
                DropdownMenuItem(value: 'imported', child: Text('imported')),
                DropdownMenuItem(value: 'rejected', child: Text('rejected')),
                DropdownMenuItem(value: 'error', child: Text('error')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _parsedStatusFilter = value);
                unawaited(_loadParsedEvents());
              },
            ),
            const Spacer(),
            Text('Parsed: $_parsedTotal'),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _parsedLoading ? null : _loadParsedEvents,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ],
        ),
        if ((_parserError ?? '').trim().isNotEmpty)
          Text(_parserError!, style: const TextStyle(color: Colors.red)),
        ..._parsedEvents.map((item) => _buildParsedEventCard(item)),
      ],
    );
  }

  Widget _buildLandingTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Landing texts',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _landingHeroEyebrowCtrl,
                  decoration: const InputDecoration(labelText: 'Hero eyebrow'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landingHeroTitleCtrl,
                  decoration: const InputDecoration(labelText: 'Hero title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landingHeroDescriptionCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration:
                      const InputDecoration(labelText: 'Hero description'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landingHeroCtaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hero primary CTA label',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landingAboutTitleCtrl,
                  decoration: const InputDecoration(labelText: 'About title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landingAboutDescriptionCtrl,
                  minLines: 2,
                  maxLines: 6,
                  decoration:
                      const InputDecoration(labelText: 'About description'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landingPartnersTitleCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Partners title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landingPartnersDescriptionCtrl,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Partners description',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landingFooterCtrl,
                  decoration: const InputDecoration(labelText: 'Footer text'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _landingContentBusy ? null : _saveLandingContent,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_landingContentBusy ? 'Saving…' : 'Save texts'),
                ),
                if ((_landingError ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_landingError!,
                      style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Publish event on landing',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _landingEventIdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Event ID',
                          hintText: 'e.g. 123',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<bool>(
                      value: _landingPublishedValue,
                      items: const [
                        DropdownMenuItem<bool>(
                            value: true, child: Text('Publish')),
                        DropdownMenuItem<bool>(
                            value: false, child: Text('Unpublish')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _landingPublishedValue = value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _landingImageUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Card image URL',
                    hintText: 'https://example.com/cover.jpg',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _landingBusy || _landingImageBusy
                          ? null
                          : _applyLandingPublicationFromInput,
                      child: Text(_landingBusy ? 'Saving…' : 'Apply'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _landingBusy || _landingImageBusy
                          ? null
                          : _saveLandingEventImageFromInput,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                          _landingImageBusy ? 'Saving…' : 'Save card image'),
                    ),
                  ],
                ),
                if ((_landingError ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_landingError!,
                      style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('Published events: $_landingTotal'),
            const Spacer(),
            TextButton.icon(
              onPressed: _landingLoading ? null : _loadLanding,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ],
        ),
        if (_landingLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              height: 180,
              child: PremiumLoadingView(
                compact: true,
                text: 'LANDING • LOADING • ',
                subtitle: 'Загружаем публикации',
              ),
            ),
          ),
        if (_landingEvents.isEmpty && !_landingLoading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No events published on landing yet.'),
            ),
          )
        else
          ..._landingEvents.map(
            (event) => Card(
              child: ListTile(
                onTap: () {
                  setState(() {
                    _landingEventIdCtrl.text = '${event.id}';
                    _landingImageUrlCtrl.text = event.thumbnailUrl.trim();
                    _landingPublishedValue = true;
                  });
                },
                leading: _buildLandingEventThumbnail(event.thumbnailUrl),
                title: Text('${event.title} (#${event.id})'),
                subtitle: Text(
                  '${formatDateTime(event.startsAt)} • ${event.addressLabel.isEmpty ? 'No address' : event.addressLabel}',
                ),
                isThreeLine: false,
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton(
                      onPressed: () => context.push(AppRoutes.event(event.id)),
                      child: const Text('Open'),
                    ),
                    FilledButton.tonal(
                      onPressed: _landingBusy || _landingImageBusy
                          ? null
                          : () => _setLandingPublished(
                              eventId: event.id, published: false),
                      child: Text(_landingActionEventId == event.id
                          ? '…'
                          : 'Unpublish'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLandingEventThumbnail(String rawUrl) {
    const size = 52.0;
    final url = rawUrl.trim();

    Widget fallback() {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.blueGrey.withValues(alpha: 0.18),
          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.4)),
        ),
        child: const Icon(Icons.image_outlined, size: 18),
      );
    }

    if (url.isEmpty) {
      return fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => fallback(),
      ),
    );
  }

  Widget _buildParsedEventCard(AdminParsedEvent item) {
    final draft = _parserDrafts[item.id] ?? _ParserDraft.fromParsed(item);
    _parserDrafts[item.id] = draft;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${item.name.isEmpty ? 'Untitled' : item.name} • ${item.status}'),
            if (item.importedEventId != null) ...[
              const SizedBox(height: 4),
              Text('Event ID: #${item.importedEventId}'),
            ],
            const SizedBox(height: 4),
            Text(
                '${item.sourceType} • parsed ${formatDateTime(item.parsedAt)}'),
            if (item.location.trim().isNotEmpty)
              Text('Location: ${item.location}'),
            if (item.parserError.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(item.parserError,
                    style: const TextStyle(color: Colors.red)),
              ),
            if (item.status == 'pending') ...[
              const SizedBox(height: 10),
              TextField(
                controller: draft.titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: draft.descriptionCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: draft.startsAtCtrl,
                decoration: const InputDecoration(
                  labelText: 'StartsAt ISO (optional)',
                  hintText: '2026-02-08T18:30:00Z',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: draft.latCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Lat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: draft.lngCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Lng'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: draft.addressCtrl,
                decoration: const InputDecoration(labelText: 'Address label'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: draft.linksCtrl,
                minLines: 3,
                maxLines: 6,
                decoration:
                    const InputDecoration(labelText: 'Links (one per line)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: draft.mediaCtrl,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Media URLs (one per line)'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _parserGeocodeBusyId == item.id
                        ? null
                        : () => _geocodeDraft(item),
                    child: Text(_parserGeocodeBusyId == item.id
                        ? 'Geocoding…'
                        : 'Geocode'),
                  ),
                  FilledButton(
                    onPressed: _parserImportBusyId == item.id
                        ? null
                        : () => _importParsed(item),
                    child: Text(_parserImportBusyId == item.id
                        ? 'Importing…'
                        : 'Import to events'),
                  ),
                  OutlinedButton(
                    onPressed: _parserRejectBusyId == item.id
                        ? null
                        : () => _rejectParsed(item.id),
                    child: Text(_parserRejectBusyId == item.id
                        ? 'Rejecting…'
                        : 'Reject'),
                  ),
                  OutlinedButton(
                    onPressed: _parserDeleteBusyId == item.id
                        ? null
                        : () => _deleteParsed(item.id),
                    child: Text(_parserDeleteBusyId == item.id
                        ? 'Deleting…'
                        : 'Delete'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (item.importedEventId != null)
                    FilledButton.tonal(
                      onPressed: () =>
                          context.push(AppRoutes.event(item.importedEventId!)),
                      child: Text('Open event #${item.importedEventId}'),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _parserDeleteBusyId == item.id
                        ? null
                        : () => _deleteParsed(item.id),
                    child: Text(_parserDeleteBusyId == item.id
                        ? 'Deleting…'
                        : 'Delete from DB'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _bootstrapLoads() async {
    await Future.wait<void>([
      _loadUsers(),
      _loadBroadcasts(),
      _loadParserSources(),
      _loadParsedEvents(),
      _loadLanding(),
    ]);
  }

  Future<void> _handleAdminLogin() async {
    final username = _adminLoginCtrl.text.trim();
    final password = _adminPasswordCtrl.text;
    final telegramId = int.tryParse(_adminTelegramIdCtrl.text.trim());
    if (username.isEmpty || password.isEmpty) {
      setState(() => _adminLoginError = 'Enter username and password');
      return;
    }

    setState(() {
      _adminLoginBusy = true;
      _adminLoginError = null;
    });

    try {
      final response = await ref.read(adminRepositoryProvider).login(
            username: username,
            password: password,
            telegramId: telegramId,
          );
      await ref.read(authControllerProvider).applySession(response.session);
      setState(() {
        _accessDenied = false;
      });
      if (!mounted) return;
      await _bootstrapLoads();
    } catch (error) {
      setState(() {
        _adminLoginError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _adminLoginBusy = false;
        });
      }
    }
  }

  Future<void> _loadUsers() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _usersLoading = true;
      _usersError = null;
    });

    try {
      final blocked = _usersBlockedFilter == 'all'
          ? null
          : _usersBlockedFilter == 'blocked'
              ? 'true'
              : 'false';
      final response = await ref.read(adminRepositoryProvider).listUsers(
            token: token,
            search: _usersSearchCtrl.text.trim(),
            blocked: blocked,
            limit: 50,
            offset: 0,
          );
      setState(() {
        _users = response.items;
        _usersTotal = response.total;
      });
    } catch (error) {
      _handleAdminError(error, setter: (value) => _usersError = value);
    } finally {
      if (mounted) {
        setState(() {
          _usersLoading = false;
        });
      }
    }
  }

  Future<void> _openUserDetail(int userId) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _userDetailLoading = true;
      _userDetailError = null;
      _userDetail = null;
    });

    try {
      final detail = await ref
          .read(adminRepositoryProvider)
          .getUser(token: token, id: userId);
      setState(() {
        _userDetail = detail;
      });
    } catch (error) {
      _handleAdminError(error, setter: (value) => _userDetailError = value);
    } finally {
      if (mounted) {
        setState(() {
          _userDetailLoading = false;
        });
      }
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final detail = _userDetail;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: _userDetailLoading
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: SizedBox(
                      height: 180,
                      child: PremiumLoadingView(
                        compact: true,
                        text: 'USER DETAILS • LOADING • ',
                        subtitle: 'Загружаем пользователя',
                      ),
                    ),
                  )
                : (_userDetailError ?? '').isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_userDetailError!,
                            style: const TextStyle(color: Colors.red)),
                      )
                    : detail == null
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('User not found'),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(detail.user.displayName,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 6),
                              Text(
                                  'TG: ${detail.user.telegramId} • @${detail.user.username}'),
                              const SizedBox(height: 6),
                              Text('Balance: ${detail.user.balanceTokens} GT'),
                              Text(
                                  'Last seen: ${formatDateTime(detail.user.lastSeenAt)}'),
                              const SizedBox(height: 10),
                              if (!detail.user.isBlocked)
                                TextField(
                                  controller: _blockReasonCtrl,
                                  decoration: const InputDecoration(
                                      labelText: 'Block reason (optional)'),
                                ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _userBlockBusy
                                    ? null
                                    : () async {
                                        final navigator = Navigator.of(context);
                                        await _toggleBlockUser(detail.user);
                                        if (!mounted) return;
                                        navigator.pop();
                                      },
                                child: Text(
                                  _userBlockBusy
                                      ? 'Saving…'
                                      : detail.user.isBlocked
                                          ? 'Unblock'
                                          : 'Block user',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                  'Created events (${detail.createdEvents.length})',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 6),
                              ...detail.createdEvents.map(
                                (event) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('${event.title} (#${event.id})'),
                                  subtitle: Text(
                                      '${formatDateTime(event.startsAt)} • ${event.participantsCount} going'),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    context.push(AppRoutes.event(event.id));
                                  },
                                ),
                              ),
                            ],
                          ),
          ),
        );
      },
    );
  }

  Future<void> _toggleBlockUser(AdminUser user) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _userBlockBusy = true;
      _userDetailError = null;
    });

    try {
      if (user.isBlocked) {
        await ref
            .read(adminRepositoryProvider)
            .unblockUser(token: token, id: user.id);
      } else {
        await ref.read(adminRepositoryProvider).blockUser(
              token: token,
              id: user.id,
              reason: _blockReasonCtrl.text.trim(),
            );
      }
      _blockReasonCtrl.clear();
      await _loadUsers();
      final detail = await ref
          .read(adminRepositoryProvider)
          .getUser(token: token, id: user.id);
      setState(() {
        _userDetail = detail;
      });
    } catch (error) {
      _handleAdminError(error, setter: (value) => _userDetailError = value);
    } finally {
      if (mounted) {
        setState(() {
          _userBlockBusy = false;
        });
      }
    }
  }

  Future<void> _loadBroadcasts() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _broadcastsLoading = true;
      _broadcastsError = null;
    });

    try {
      final response =
          await ref.read(adminRepositoryProvider).listBroadcasts(token: token);
      setState(() {
        _broadcasts = response.items;
        _broadcastsTotal = response.total;
      });
    } catch (error) {
      _handleAdminError(error, setter: (value) => _broadcastsError = value);
    } finally {
      if (mounted) {
        setState(() {
          _broadcastsLoading = false;
        });
      }
    }
  }

  Future<void> _createBroadcast() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    final message = _broadcastMessageCtrl.text.trim();
    if (message.isEmpty) {
      setState(() => _broadcastsError = 'Message is required');
      return;
    }

    setState(() {
      _broadcastCreateBusy = true;
      _broadcastsError = null;
    });

    try {
      final cleanedButtons = _broadcastButtons
          .map(
            (item) => BroadcastButton(
              text: item.textCtrl.text.trim(),
              url: item.urlCtrl.text.trim(),
            ),
          )
          .where((item) => item.text.isNotEmpty && item.url.isNotEmpty)
          .toList();

      List<int>? userIds;
      Map<String, dynamic>? filters;

      if (_broadcastAudience == 'selected') {
        userIds = _broadcastUserIdsCtrl.text
            .split(',')
            .map((value) => int.tryParse(value.trim()))
            .whereType<int>()
            .where((value) => value > 0)
            .toList();
        if (userIds.isEmpty) {
          throw AppException('Provide at least one valid user ID');
        }
      }

      if (_broadcastAudience == 'filter') {
        filters = <String, dynamic>{'blocked': false};
        final minBalance = int.tryParse(_broadcastMinBalanceCtrl.text.trim());
        if (minBalance != null && minBalance >= 0) {
          filters['minBalance'] = minBalance;
        }
        final lastSeenAfter = _broadcastLastSeenAfterCtrl.text.trim();
        if (lastSeenAfter.isNotEmpty) {
          final parsed = DateTime.tryParse(lastSeenAfter);
          if (parsed == null) {
            throw AppException('lastSeenAfter must be valid ISO date');
          }
          filters['lastSeenAfter'] = parsed.toUtc().toIso8601String();
        }
      }

      await ref.read(adminRepositoryProvider).createBroadcast(
            token: token,
            audience: _broadcastAudience,
            message: message,
            userIds: userIds,
            filters: filters,
            buttons: cleanedButtons,
          );

      _broadcastMessageCtrl.clear();
      _broadcastUserIdsCtrl.clear();
      _broadcastMinBalanceCtrl.clear();
      _broadcastLastSeenAfterCtrl.clear();
      setState(() {
        for (final item in _broadcastButtons) {
          item.dispose();
        }
        _broadcastButtons
          ..clear()
          ..add(_BroadcastButtonDraft(text: '', url: ''));
      });

      await _loadBroadcasts();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _broadcastsError = value);
    } finally {
      if (mounted) {
        setState(() {
          _broadcastCreateBusy = false;
        });
      }
    }
  }

  Future<void> _startBroadcast(int id) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _broadcastStartBusyId = id;
      _broadcastsError = null;
    });

    try {
      await ref
          .read(adminRepositoryProvider)
          .startBroadcast(token: token, id: id);
      await _loadBroadcasts();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _broadcastsError = value);
    } finally {
      if (mounted) {
        setState(() {
          _broadcastStartBusyId = null;
        });
      }
    }
  }

  Future<void> _loadParserSources() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _parserSourcesLoading = true;
      _parserError = null;
    });

    try {
      final response = await ref
          .read(adminRepositoryProvider)
          .listParserSources(token: token);
      setState(() {
        _parserSources = response.items;
        _parserSourcesTotal = response.total;
      });
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parserSourcesLoading = false;
        });
      }
    }
  }

  Future<void> _createParserSource() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    final input = _parserSourceInputCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _parserError = 'Source input is required');
      return;
    }

    setState(() {
      _parserCreateSourceBusy = true;
      _parserError = null;
    });

    try {
      await ref.read(adminRepositoryProvider).createParserSource(
            token: token,
            sourceType: _parserSourceType,
            input: input,
            title: _parserSourceTitleCtrl.text.trim(),
            isActive: true,
          );

      _parserSourceTitleCtrl.clear();
      _parserSourceInputCtrl.clear();
      await _loadParserSources();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parserCreateSourceBusy = false;
        });
      }
    }
  }

  Future<void> _toggleParserSource(AdminParserSource source) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _parserSourceBusyId = source.id;
      _parserError = null;
    });

    try {
      await ref.read(adminRepositoryProvider).updateParserSource(
            token: token,
            id: source.id,
            isActive: !source.isActive,
          );
      await _loadParserSources();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parserSourceBusyId = null;
        });
      }
    }
  }

  Future<void> _parseSource(int sourceId) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _parserSourceBusyId = sourceId;
      _parserError = null;
    });

    try {
      final result = await ref
          .read(adminRepositoryProvider)
          .parseSource(token: token, id: sourceId);
      if (result.error.trim().isNotEmpty) {
        setState(() => _parserError = result.error);
      }
      await _loadParserSources();
      await _loadParsedEvents();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parserSourceBusyId = null;
        });
      }
    }
  }

  Future<void> _parseQuick() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    final input = _parserQuickInputCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _parserError = 'Quick parse input is required');
      return;
    }

    setState(() {
      _parserQuickBusy = true;
      _parserError = null;
    });

    try {
      final result = await ref.read(adminRepositoryProvider).parseInput(
            token: token,
            sourceType: _parserQuickType,
            input: input,
          );
      if (result.error.trim().isNotEmpty) {
        setState(() => _parserError = result.error);
      } else {
        _parserQuickInputCtrl.clear();
      }
      await _loadParsedEvents();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parserQuickBusy = false;
        });
      }
    }
  }

  Future<void> _loadParsedEvents() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _parsedLoading = true;
      _parserError = null;
    });

    try {
      final status = _parsedStatusFilter == 'all' ? null : _parsedStatusFilter;
      final response = await ref.read(adminRepositoryProvider).listParsedEvents(
            token: token,
            status: status,
          );
      setState(() {
        _parsedEvents = response.items;
        _parsedTotal = response.total;
        for (final item in response.items) {
          _parserDrafts.putIfAbsent(
              item.id, () => _ParserDraft.fromParsed(item));
        }
      });
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parsedLoading = false;
        });
      }
    }
  }

  Future<void> _geocodeDraft(AdminParsedEvent item) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    final draft = _parserDrafts[item.id]!;
    final query = draft.addressCtrl.text.trim().isNotEmpty
        ? draft.addressCtrl.text.trim()
        : (draft.titleCtrl.text.trim().isNotEmpty
            ? draft.titleCtrl.text.trim()
            : item.location.trim());
    if (query.isEmpty) {
      setState(() => _parserError = 'Address/title required for geocode');
      return;
    }

    setState(() {
      _parserGeocodeBusyId = item.id;
      _parserError = null;
    });

    try {
      final response = await ref
          .read(adminRepositoryProvider)
          .geocode(token: token, query: query, limit: 1);
      if (response.items.isEmpty) {
        setState(() => _parserError = 'No geocode results found');
        return;
      }
      final first = response.items.first;
      setState(() {
        draft.latCtrl.text = first.lat.toString();
        draft.lngCtrl.text = first.lng.toString();
        if (draft.addressCtrl.text.trim().isEmpty) {
          draft.addressCtrl.text = first.displayName;
        }
      });
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parserGeocodeBusyId = null;
        });
      }
    }
  }

  Future<void> _importParsed(AdminParsedEvent item) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    final draft = _parserDrafts[item.id]!;
    final lat = double.tryParse(draft.latCtrl.text.trim());
    final lng = double.tryParse(draft.lngCtrl.text.trim());
    if (lat == null || lng == null) {
      setState(() => _parserError = 'Lat/Lng are required for import');
      return;
    }

    String? startsAt;
    if (draft.startsAtCtrl.text.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(draft.startsAtCtrl.text.trim());
      if (parsed == null) {
        setState(() => _parserError = 'startsAt must be valid ISO');
        return;
      }
      startsAt = parsed.toUtc().toIso8601String();
    }

    final links = _dedupeTrimmed(draft.linksCtrl.text.split(RegExp(r'\r?\n')));
    final media = _dedupeTrimmed(draft.mediaCtrl.text.split(RegExp(r'\r?\n')));

    setState(() {
      _parserImportBusyId = item.id;
      _parserError = null;
    });

    try {
      final eventId = await ref.read(adminRepositoryProvider).importParsedEvent(
            token: token,
            id: item.id,
            title: draft.titleCtrl.text.trim(),
            description: draft.descriptionCtrl.text.trim(),
            startsAt: startsAt,
            lat: lat,
            lng: lng,
            addressLabel: draft.addressCtrl.text.trim(),
            media: media,
            links: links,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported as event #$eventId')),
      );
      await _loadParsedEvents();
      if (!mounted) return;
      context.push(AppRoutes.event(eventId));
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parserImportBusyId = null;
        });
      }
    }
  }

  Future<void> _rejectParsed(int id) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _parserRejectBusyId = id;
      _parserError = null;
    });

    try {
      await ref
          .read(adminRepositoryProvider)
          .rejectParsedEvent(token: token, id: id);
      await _loadParsedEvents();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parserRejectBusyId = null;
        });
      }
    }
  }

  Future<void> _deleteParsed(int id) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _parserDeleteBusyId = id;
      _parserError = null;
    });

    try {
      await ref
          .read(adminRepositoryProvider)
          .deleteParsedEvent(token: token, id: id);
      await _loadParsedEvents();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _parserError = value);
    } finally {
      if (mounted) {
        setState(() {
          _parserDeleteBusyId = null;
        });
      }
    }
  }

  Future<void> _loadLanding() async {
    setState(() {
      _landingLoading = true;
      _landingError = null;
    });

    try {
      final repository = ref.read(adminRepositoryProvider);
      final responses = await Future.wait<dynamic>([
        repository.listLandingEvents(limit: 100, offset: 0),
        repository.getLandingContent(),
      ]);
      final eventsResponse = responses[0] as LandingEventsResponse;
      final content = responses[1] as LandingContent;
      if (!mounted) return;
      setState(() {
        _landingEvents = eventsResponse.items;
        _landingTotal = eventsResponse.total;
      });
      _applyLandingContentToControllers(content);
    } catch (error) {
      _handleAdminError(error, setter: (value) => _landingError = value);
    } finally {
      if (mounted) {
        setState(() {
          _landingLoading = false;
        });
      }
    }
  }

  void _applyLandingContentToControllers(LandingContent content) {
    _landingHeroEyebrowCtrl.text = content.heroEyebrow;
    _landingHeroTitleCtrl.text = content.heroTitle;
    _landingHeroDescriptionCtrl.text = content.heroDescription;
    _landingHeroCtaCtrl.text = content.heroPrimaryCtaLabel;
    _landingAboutTitleCtrl.text = content.aboutTitle;
    _landingAboutDescriptionCtrl.text = content.aboutDescription;
    _landingPartnersTitleCtrl.text = content.partnersTitle;
    _landingPartnersDescriptionCtrl.text = content.partnersDescription;
    _landingFooterCtrl.text = content.footerText;
  }

  LandingContent _landingContentFromInputs() {
    return LandingContent(
      heroEyebrow: _landingHeroEyebrowCtrl.text.trim(),
      heroTitle: _landingHeroTitleCtrl.text.trim(),
      heroDescription: _landingHeroDescriptionCtrl.text.trim(),
      heroPrimaryCtaLabel: _landingHeroCtaCtrl.text.trim(),
      aboutTitle: _landingAboutTitleCtrl.text.trim(),
      aboutDescription: _landingAboutDescriptionCtrl.text.trim(),
      partnersTitle: _landingPartnersTitleCtrl.text.trim(),
      partnersDescription: _landingPartnersDescriptionCtrl.text.trim(),
      footerText: _landingFooterCtrl.text.trim(),
    );
  }

  Future<void> _saveLandingContent() async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _landingContentBusy = true;
      _landingError = null;
    });

    try {
      await ref.read(adminRepositoryProvider).updateLandingContent(
            token: token,
            content: _landingContentFromInputs(),
          );
      if (!mounted) return;
      await _loadLanding();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _landingError = value);
    } finally {
      if (mounted) {
        setState(() {
          _landingContentBusy = false;
        });
      }
    }
  }

  Future<void> _applyLandingPublicationFromInput() async {
    final id = int.tryParse(_landingEventIdCtrl.text.trim());
    if (id == null || id <= 0) {
      setState(() => _landingError = 'Valid event ID is required');
      return;
    }
    await _setLandingPublished(eventId: id, published: _landingPublishedValue);
  }

  Future<void> _saveLandingEventImageFromInput() async {
    final id = int.tryParse(_landingEventIdCtrl.text.trim());
    if (id == null || id <= 0) {
      setState(() => _landingError = 'Valid event ID is required');
      return;
    }

    final imageUrl = _landingImageUrlCtrl.text.trim();
    if (imageUrl.isEmpty) {
      setState(() => _landingError = 'Image URL is required');
      return;
    }
    if (!_isHttpUrl(imageUrl)) {
      setState(() => _landingError = 'Image URL must be a valid http(s) link');
      return;
    }

    await _saveLandingEventImage(eventId: id, imageUrl: imageUrl);
  }

  Future<void> _saveLandingEventImage({
    required int eventId,
    required String imageUrl,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _landingImageBusy = true;
      _landingActionEventId = eventId;
      _landingError = null;
    });

    try {
      final repository = ref.read(adminRepositoryProvider);
      final existingMedia = await repository.getEventMedia(
        token: token,
        eventId: eventId,
      );
      final mergedMedia = _mergeLandingCardImage(
        existingMedia: existingMedia,
        imageUrl: imageUrl,
      );
      await repository.updateEventMedia(
        token: token,
        eventId: eventId,
        media: mergedMedia,
      );
      if (!mounted) return;
      await _loadLanding();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _landingError = value);
    } finally {
      if (mounted) {
        setState(() {
          _landingImageBusy = false;
          _landingActionEventId = null;
        });
      }
    }
  }

  List<String> _mergeLandingCardImage({
    required List<String> existingMedia,
    required String imageUrl,
  }) {
    final normalized = imageUrl.trim();
    final out = <String>[];
    final seen = <String>{};

    if (normalized.isNotEmpty) {
      out.add(normalized);
      seen.add(normalized.toLowerCase());
    }

    for (final raw in existingMedia) {
      final candidate = raw.trim();
      if (candidate.isEmpty) continue;
      final key = candidate.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(candidate);
      if (out.length >= 5) {
        break;
      }
    }

    return out;
  }

  bool _isHttpUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return false;
    }
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  Future<void> _setLandingPublished({
    required int eventId,
    required bool published,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) return;

    setState(() {
      _landingBusy = true;
      _landingActionEventId = eventId;
      _landingError = null;
    });

    try {
      await ref.read(adminRepositoryProvider).setLandingPublished(
            token: token,
            eventId: eventId,
            published: published,
          );
      if (!mounted) return;
      if (_landingEventIdCtrl.text.trim() == '$eventId') {
        _landingEventIdCtrl.clear();
      }
      await _loadLanding();
    } catch (error) {
      _handleAdminError(error, setter: (value) => _landingError = value);
    } finally {
      if (mounted) {
        setState(() {
          _landingBusy = false;
          _landingActionEventId = null;
        });
      }
    }
  }

  void _handleAdminError(Object error, {void Function(String value)? setter}) {
    if (!mounted) return;
    if (error is AppException && (error.isUnauthorized || error.isForbidden)) {
      setState(() {
        _accessDenied = true;
      });
      return;
    }

    final message = error.toString();
    if (setter != null) {
      setState(() {
        setter(message);
      });
    }
  }
}

class _BroadcastButtonDraft {
  _BroadcastButtonDraft({required String text, required String url})
      : textCtrl = TextEditingController(text: text),
        urlCtrl = TextEditingController(text: url);

  final TextEditingController textCtrl;
  final TextEditingController urlCtrl;

  void dispose() {
    textCtrl.dispose();
    urlCtrl.dispose();
  }
}

class _ParserDraft {
  factory _ParserDraft.fromParsed(AdminParsedEvent item) {
    final imageLinks = _dedupeTrimmed(item.links.where(_isImageLink).toList());
    final eventLinks = _dedupeTrimmed(
        item.links.where((link) => !_isImageLink(link)).toList());

    return _ParserDraft(
      titleCtrl: TextEditingController(text: item.name),
      descriptionCtrl: TextEditingController(text: item.description),
      startsAtCtrl: TextEditingController(
          text: item.dateTime?.toUtc().toIso8601String() ?? ''),
      latCtrl: TextEditingController(text: '52.37'),
      lngCtrl: TextEditingController(text: '4.90'),
      addressCtrl: TextEditingController(text: item.location),
      linksCtrl: TextEditingController(text: eventLinks.join('\n')),
      mediaCtrl: TextEditingController(text: imageLinks.join('\n')),
    );
  }
  _ParserDraft({
    required this.titleCtrl,
    required this.descriptionCtrl,
    required this.startsAtCtrl,
    required this.latCtrl,
    required this.lngCtrl,
    required this.addressCtrl,
    required this.linksCtrl,
    required this.mediaCtrl,
  });

  final TextEditingController titleCtrl;
  final TextEditingController descriptionCtrl;
  final TextEditingController startsAtCtrl;
  final TextEditingController latCtrl;
  final TextEditingController lngCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController linksCtrl;
  final TextEditingController mediaCtrl;

  void dispose() {
    titleCtrl.dispose();
    descriptionCtrl.dispose();
    startsAtCtrl.dispose();
    latCtrl.dispose();
    lngCtrl.dispose();
    addressCtrl.dispose();
    linksCtrl.dispose();
    mediaCtrl.dispose();
  }
}

bool _isImageLink(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) return false;
  if (RegExp(r'\.(jpg|jpeg|png|webp|gif|bmp|svg)(\?|$)').hasMatch(trimmed)) {
    return true;
  }
  if (trimmed.contains('/photo') ||
      trimmed.contains('/image') ||
      trimmed.contains('/img')) {
    return true;
  }
  return false;
}

List<String> _dedupeTrimmed(List<String> values) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    final key = value.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(value);
  }
  return out;
}
