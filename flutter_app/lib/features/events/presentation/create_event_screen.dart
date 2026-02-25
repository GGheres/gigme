import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../app/routes.dart';
import '../../../core/constants/event_filters.dart';
import '../../../core/notifications/providers.dart';
import '../../../ui/components/action_buttons.dart';
import '../../../ui/components/app_toast.dart';
import '../../../ui/components/input_field.dart';
import '../../../ui/components/section_card.dart';
import '../../../ui/layout/app_scaffold.dart';
import '../../../ui/theme/app_colors.dart';
import '../../../ui/theme/app_spacing.dart';
import '../application/events_controller.dart';
import '../application/location_controller.dart';
import '../data/create_event_draft_store.dart';
import '../data/events_repository.dart';

/// CreateEventScreen represents create event screen.

class CreateEventScreen extends ConsumerStatefulWidget {
  /// CreateEventScreen creates event screen.
  const CreateEventScreen({super.key});

  /// createState creates state.

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

/// _CreateEventScreenState represents create event screen state.

class _CreateEventScreenState extends ConsumerState<CreateEventScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _draftStore = CreateEventDraftStore();

  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();

  DateTime? _startsAt;
  DateTime? _endsAt;
  LatLng? _selectedPoint;
  bool _isPrivate = false;
  bool _submitting = false;
  bool _uploading = false;
  bool _restoringDraft = false;
  bool _submissionCompleted = false;
  bool _showResumeReminder = false;
  Timer? _draftSaveDebounce;

  final List<String> _selectedFilters = <String>[];
  final List<_UploadedMedia> _uploadedMedia = <_UploadedMedia>[];

  List<TextEditingController> get _draftControllers => [
        _titleCtrl,
        _descriptionCtrl,
        _capacityCtrl,
        _contactCtrl,
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
        ref.read(localReminderServiceProvider).cancelCreateEventReminder());
    for (final controller in _draftControllers) {
      controller.addListener(_onDraftChanged);
    }
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    final draftBeforeDispose = _snapshotDraft();
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _draftControllers) {
      controller.removeListener(_onDraftChanged);
    }
    _draftSaveDebounce?.cancel();
    if (!_submissionCompleted) {
      if (draftBeforeDispose.hasMeaningfulData) {
        unawaited(
          ref.read(localReminderServiceProvider).scheduleCreateEventReminder(),
        );
      } else {
        unawaited(
            ref.read(localReminderServiceProvider).cancelCreateEventReminder());
      }
      unawaited(_persistDraft());
    }
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _capacityCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_persistDraft());
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final draft = _snapshotDraft();
      if (draft.hasMeaningfulData) {
        _showResumeReminder = true;
        unawaited(
          ref.read(localReminderServiceProvider).scheduleCreateEventReminder(),
        );
      } else {
        unawaited(
            ref.read(localReminderServiceProvider).cancelCreateEventReminder());
      }
      unawaited(_persistDraft());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(
          ref.read(localReminderServiceProvider).cancelCreateEventReminder());
      if (_showResumeReminder) {
        _showResumeReminder = false;
        if (!mounted) return;
        AppToast.show(
          context,
          message:
              'Черновик события сохранен. Завершите публикацию, когда будете готовы.',
          tone: AppToastTone.warning,
        );
      }
    }
  }

  void _onDraftChanged() {
    if (_restoringDraft) return;
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    if (_restoringDraft || _submissionCompleted) return;
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_persistDraft());
    });
  }

  Future<void> _restoreDraft() async {
    _restoringDraft = true;
    try {
      final draft = await _draftStore.load();
      if (!mounted || draft == null) return;

      setState(() {
        _titleCtrl.text = draft.title;
        _descriptionCtrl.text = draft.description;
        _capacityCtrl.text = draft.capacity;
        _contactCtrl.text = draft.contact;
        _startsAt = draft.startsAt;
        _endsAt = draft.endsAt;
        _selectedPoint = draft.selectedPoint;
        _isPrivate = draft.isPrivate;
        _selectedFilters
          ..clear()
          ..addAll(draft.filters);
        _uploadedMedia
          ..clear()
          ..addAll(
            draft.mediaUrls.map(_UploadedMedia.fromStoredUrl),
          );
      });

      if (!mounted) return;
      AppToast.show(
        context,
        message: 'Восстановили черновик события. Завершите публикацию.',
        tone: AppToastTone.warning,
      );
    } finally {
      _restoringDraft = false;
    }
  }

  CreateEventDraft _snapshotDraft() {
    return CreateEventDraft(
      title: _titleCtrl.text,
      description: _descriptionCtrl.text,
      capacity: _capacityCtrl.text,
      contact: _contactCtrl.text,
      startsAt: _startsAt,
      endsAt: _endsAt,
      selectedPoint: _selectedPoint,
      isPrivate: _isPrivate,
      filters: List<String>.from(_selectedFilters),
      mediaUrls: _uploadedMedia.map((item) => item.fileUrl).toList(),
    );
  }

  void _resetFormAfterSuccessfulSubmit() {
    _draftSaveDebounce?.cancel();
    _submissionCompleted = true;

    _titleCtrl.clear();
    _descriptionCtrl.clear();
    _capacityCtrl.clear();
    _contactCtrl.clear();

    _startsAt = null;
    _endsAt = null;
    _selectedPoint = null;
    _isPrivate = false;
    _showResumeReminder = false;
    _selectedFilters.clear();
    _uploadedMedia.clear();

    _submissionCompleted = false;
  }

  Future<void> _persistDraft() async {
    if (_restoringDraft || _submissionCompleted) return;
    _draftSaveDebounce?.cancel();
    await _draftStore.save(_snapshotDraft());
  }

  void _updateStateAndSave(VoidCallback updateState) {
    setState(updateState);
    _scheduleDraftSave();
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationControllerProvider).state;

    _selectedPoint ??= location.userLocation ?? location.center;

    return AppScaffold(
      title: 'Создать событие',
      subtitle: 'Короткая форма с понятными шагами',
      titleColor: Theme.of(context).colorScheme.onSurface,
      subtitleColor:
          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      scrollable: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: '1. Основная информация',
              subtitle: 'Название, описание и формат события',
              child: Column(
                children: [
                  InputField(
                    controller: _titleCtrl,
                    maxLength: 80,
                    label: 'Название',
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Введите название';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  InputField(
                    controller: _descriptionCtrl,
                    maxLength: 1000,
                    minLines: 4,
                    maxLines: 7,
                    label: 'Описание',
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Добавьте описание';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _buildFilters(context),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              title: '2. Дата и лимиты',
              child: Column(
                children: [
                  _DateTimeField(
                    label: 'Начало',
                    value: _startsAt,
                    onChanged: (value) =>
                        _updateStateAndSave(() => _startsAt = value),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _DateTimeField(
                    label: 'Окончание (необязательно)',
                    value: _endsAt,
                    onChanged: (value) =>
                        _updateStateAndSave(() => _endsAt = value),
                    clearable: true,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  InputField(
                    controller: _capacityCtrl,
                    keyboardType: TextInputType.number,
                    label: 'Лимит участников (необязательно)',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              title: '3. Контакты',
              subtitle: 'Укажите способ связи в одном поле',
              child: Column(
                children: [
                  InputField(
                    controller: _contactCtrl,
                    maxLength: 120,
                    label: 'Контакт',
                    hint:
                        '@telegram, +7986342232, user@email.com, snapchat:username, messenger:username',
                    validator: (value) =>
                        _validateUnifiedContact((value ?? '').trim()),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Приватное событие (по ссылке)'),
                    value: _isPrivate,
                    onChanged: (value) =>
                        _updateStateAndSave(() => _isPrivate = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              title: '4. Локация',
              subtitle: 'Поставьте точку на карте',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 230,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _selectedPoint ?? location.center,
                          initialZoom: 12,
                          onTap: (_, point) =>
                              _updateStateAndSave(() => _selectedPoint = point),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'gigme_flutter',
                          ),
                          if (_selectedPoint != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _selectedPoint!,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.location_pin,
                                    color: AppColors.danger,
                                    size: 38,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _selectedPoint == null
                        ? 'Нажмите на карту, чтобы выбрать точку'
                        : 'Выбрано: ${_selectedPoint!.latitude.toStringAsFixed(5)}, ${_selectedPoint!.longitude.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              title: '5. Фото',
              subtitle: '${_uploadedMedia.length}/$kMaxMediaCount загружено',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SecondaryButton(
                    label: _uploading ? 'Загрузка…' : 'Выбрать фото',
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed:
                        _uploading || _uploadedMedia.length >= kMaxMediaCount
                            ? null
                            : _pickAndUploadMedia,
                    outline: true,
                  ),
                  if (_uploadedMedia.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _uploadedMedia.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.xs),
                        itemBuilder: (context, index) {
                          final item = _uploadedMedia[index];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: item.previewBytes == null
                                    ? Image.network(
                                        item.fileUrl,
                                        width: 90,
                                        height: 90,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) {
                                          return Container(
                                            width: 90,
                                            height: 90,
                                            color: Colors.black12,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons
                                                  .image_not_supported_outlined,
                                            ),
                                          );
                                        },
                                      )
                                    : Image.memory(
                                        item.previewBytes!,
                                        width: 90,
                                        height: 90,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                              Positioned(
                                right: 2,
                                top: 2,
                                child: InkWell(
                                  onTap: () => _updateStateAndSave(
                                      () => _uploadedMedia.removeAt(index)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: _submitting ? 'Создаем…' : 'Создать событие',
              icon: const Icon(Icons.check_circle_outline_rounded),
              onPressed: (_submitting || _uploading) ? null : _submit,
              expand: true,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Теги события',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: kEventFilters.map((filter) {
              final active = _selectedFilters.contains(filter.id);
              final limitReached =
                  !active && _selectedFilters.length >= kMaxEventFilters;
              return FilterChip(
                selected: active,
                label: Text('${filter.icon} ${filter.label}'),
                onSelected: limitReached
                    ? null
                    : (_) {
                        _updateStateAndSave(() {
                          if (active) {
                            _selectedFilters.remove(filter.id);
                          } else {
                            _selectedFilters.add(filter.id);
                          }
                        });
                      },
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_selectedFilters.length}/$kMaxEventFilters выбрано',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadMedia() async {
    final remaining = kMaxMediaCount - _uploadedMedia.length;
    if (remaining <= 0) return;

    final picked = await _picker.pickMultiImage(imageQuality: 90);
    if (picked.isEmpty) return;

    setState(() => _uploading = true);

    try {
      final events = ref.read(eventsControllerProvider);
      for (final file in picked.take(remaining)) {
        final bytes = await file.readAsBytes();
        if (bytes.lengthInBytes > kMaxUploadBytes) {
          _showError(
              '"${file.name}" превышает лимит ${kMaxUploadBytes ~/ (1024 * 1024)} МБ');
          continue;
        }

        final ext = p.extension(file.name).toLowerCase();
        final contentType = lookupMimeType(file.name, headerBytes: bytes) ??
            (ext == '.png'
                ? 'image/png'
                : ext == '.webp'
                    ? 'image/webp'
                    : 'image/jpeg');

        if (!(contentType == 'image/jpeg' ||
            contentType == 'image/png' ||
            contentType == 'image/webp')) {
          _showError(
              'Неподдерживаемый формат ${file.name}. Используйте jpeg/png/webp.');
          continue;
        }

        final uploadedUrl = await events.uploadImage(
          fileName: file.name,
          contentType: contentType,
          bytes: bytes,
        );

        if (!mounted) return;
        _updateStateAndSave(() {
          _uploadedMedia.add(_UploadedMedia(
            fileUrl: uploadedUrl,
            previewBytes: bytes,
          ));
        });
      }
    } catch (error) {
      _showError('$error');
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final startsAt = _startsAt;
    final selectedPoint = _selectedPoint;

    if (startsAt == null) {
      _showError('Выберите дату и время начала');
      return;
    }
    if (_endsAt != null && _endsAt!.isBefore(startsAt)) {
      _showError('Дата завершения должна быть позже начала');
      return;
    }
    if (selectedPoint == null) {
      _showError('Выберите точку события на карте');
      return;
    }

    final contact = _contactCtrl.text.trim();
    final contactValidationError = _validateUnifiedContact(contact);
    if (contactValidationError != null) {
      _showError(contactValidationError);
      return;
    }
    final resolvedContact = _resolveContactPayload(contact);

    final capacity = int.tryParse(_capacityCtrl.text.trim());
    if (_capacityCtrl.text.trim().isNotEmpty &&
        (capacity == null || capacity <= 0)) {
      _showError('Лимит участников должен быть больше 0');
      return;
    }

    setState(() => _submitting = true);
    try {
      final payload = CreateEventPayload(
        title: _titleCtrl.text.trim(),
        description: _descriptionCtrl.text.trim(),
        startsAt: startsAt,
        endsAt: _endsAt,
        lat: selectedPoint.latitude,
        lng: selectedPoint.longitude,
        capacity: capacity,
        media: _uploadedMedia.map((item) => item.fileUrl).toList(),
        filters: _selectedFilters,
        isPrivate: _isPrivate,
        contactTelegram: resolvedContact.contactTelegram,
        contactWhatsapp: resolvedContact.contactWhatsapp,
        contactWechat: null,
        contactFbMessenger: resolvedContact.contactFbMessenger,
        contactSnapchat: resolvedContact.contactSnapchat,
        addressLabel:
            '${selectedPoint.latitude.toStringAsFixed(5)}, ${selectedPoint.longitude.toStringAsFixed(5)}',
      );

      final events = ref.read(eventsControllerProvider);
      final eventId = await events.createEvent(payload);
      await _draftStore.clear();
      await ref.read(localReminderServiceProvider).cancelCreateEventReminder();

      if (!mounted) return;
      _resetFormAfterSuccessfulSubmit();
      setState(() {});

      final center = ref.read(locationControllerProvider).state.center;
      unawaited(events.refresh(center: center));
      await context.push(AppRoutes.event(eventId));
    } catch (error) {
      _showError('$error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    AppToast.show(context, message: message, tone: AppToastTone.error);
  }

  String? _validateUnifiedContact(String value) {
    if (value.isEmpty) {
      return 'Укажите контакт';
    }
    if (_runeLength(value) > 120) {
      return 'Контакт не должен превышать 120 символов';
    }
    if (_isSupportedContact(value)) {
      return null;
    }
    return 'Используйте формат @telegram, +7986342232, email, snapchat или messenger';
  }

  bool _isSupportedContact(String value) {
    return _telegramContactPattern.hasMatch(value) ||
        _phoneContactPattern.hasMatch(value) ||
        _emailContactPattern.hasMatch(value) ||
        _snapchatContactPattern.hasMatch(value) ||
        _messengerContactPattern.hasMatch(value);
  }

  _ResolvedContactPayload _resolveContactPayload(String value) {
    if (_telegramContactPattern.hasMatch(value)) {
      return _ResolvedContactPayload(contactTelegram: value);
    }
    if (_phoneContactPattern.hasMatch(value)) {
      return _ResolvedContactPayload(contactWhatsapp: value);
    }
    if (_emailContactPattern.hasMatch(value)) {
      return _ResolvedContactPayload(contactFbMessenger: value);
    }
    if (_snapchatContactPattern.hasMatch(value)) {
      return _ResolvedContactPayload(contactSnapchat: value);
    }
    return _ResolvedContactPayload(contactFbMessenger: value);
  }

  int _runeLength(String value) {
    return value.runes.length;
  }

  static final RegExp _telegramContactPattern =
      RegExp(r'^@[a-zA-Z0-9_]{3,32}$');
  static final RegExp _phoneContactPattern =
      RegExp(r'^\+[0-9][0-9\s\-()]{6,19}$');
  static final RegExp _emailContactPattern =
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _snapchatContactPattern = RegExp(
    r'^snapchat\s*[:@-]?\s*[a-zA-Z0-9._-]{2,32}$',
    caseSensitive: false,
  );
  static final RegExp _messengerContactPattern = RegExp(
    r'^messenger\s*[:@-]?\s*.+$',
    caseSensitive: false,
  );
}

/// _UploadedMedia represents uploaded media.

class _UploadedMedia {
  /// _UploadedMedia handles uploaded media.
  _UploadedMedia({
    required this.fileUrl,
    this.previewBytes,
  });

  /// _UploadedMedia handles uploaded media.

  factory _UploadedMedia.fromStoredUrl(String fileUrl) {
    return _UploadedMedia(fileUrl: fileUrl);
  }

  final String fileUrl;
  final Uint8List? previewBytes;
}

/// _ResolvedContactPayload represents resolved contact payload.

class _ResolvedContactPayload {
  /// _ResolvedContactPayload handles resolved contact payload.
  const _ResolvedContactPayload({
    this.contactTelegram,
    this.contactWhatsapp,
    this.contactFbMessenger,
    this.contactSnapchat,
  });

  final String? contactTelegram;
  final String? contactWhatsapp;
  final String? contactFbMessenger;
  final String? contactSnapchat;
}

/// _DateTimeField represents date time field.

class _DateTimeField extends StatelessWidget {
  /// _DateTimeField handles date time field.
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.clearable = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool clearable;

  /// build renders the widget tree for this component.

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: clearable && value != null
            ? IconButton(
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.clear_rounded),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(value == null
                ? 'Не выбрано'
                : value!.toLocal().toString().substring(0, 16)),
          ),
          TextButton(
            onPressed: () => _pick(context),
            child: const Text('Выбрать'),
          ),
        ],
      ),
    );
  }

  /// _pick handles internal pick behavior.

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value ?? now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }
}
