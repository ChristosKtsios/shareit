import 'dart:async';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/location_permission_gate.dart';
import '../../../core/services/location_service.dart';
import '../../../core/utils/place_label.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/data/user_repository.dart';
import '../data/listing_model.dart';
import '../data/listing_repository.dart';
import '../data/tags_repository.dart';
import 'location_picker_screen.dart';

class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({super.key});
  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  ListingType _type = ListingType.offer;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final List<String> _tags = [];
  static const _maxTags = 5;

  DateTime? _availableFrom;
  DateTime? _availableUntil;
  TimeOfDay? _fromTime;
  TimeOfDay? _untilTime;

  bool _autoDelete = false;
  bool _loading = false;
  bool _uploadingImage = false;
  bool _locationLoading = true;
  GeoPoint? _location;
  String _locationLabel = '';
  List<String> _imageUrls = [];

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    // Κανονικοποίηση: πεζά, χωρίς #, χωρίς κενά/σύμβολα στις άκρες.
    final tag = raw
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'^#+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (tag.isEmpty || tag.length > 20) return;
    if (_tags.contains(tag) || _tags.length >= _maxTags) {
      _tagCtrl.clear();
      return;
    }
    setState(() => _tags.add(tag));
    _tagCtrl.clear();
  }

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  Future<void> _fetchLocation() async {
    setState(() => _locationLoading = true);
    try {
      final perm = await LocationPermissionGate.ensure();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Location permission not granted');
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(
            accuracy: LocationAccuracy.high,
            // ΧΩΡΙΣ timeLimit το getCurrentPosition ΔΕΝ επιστρέφει ποτέ σε
            // πραγματικές συσκευές Android όταν το GPS δεν πιάνει σήμα —
            // το loading έμενε true και το κουμπί «Δημοσίευση» ΝΕΚΡΟ.
            timeLimit: Duration(seconds: 12),
          ));
      final label =
          await LocationService.reverseGeocode(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _location = GeoPoint(pos.latitude, pos.longitude);
          // Αποθηκεύουμε ΜΟΝΟ πραγματικό τόπο ή κενό — ποτέ κείμενο εμφάνισης
          // (θα εμφανιζόταν στα ελληνικά σε ξενόγλωσσους και θα μόλυνε την
          // αναζήτηση). Η μετάφραση γίνεται στην εμφάνιση, βλ. PlaceLabel.
          _locationLabel = label ?? '';
          _locationLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationLabel = '';
          _locationLoading = false;
        });
      }
    }
  }

  Future<void> _openLocationPicker() async {
    final current = _location != null
        ? LatLng(_location!.latitude, _location!.longitude)
        : null;
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialLocation: current),
      ),
    );
    if (result != null) {
      setState(() {
        _location = GeoPoint(result.latitude, result.longitude);
        // Κενό μέχρι να απαντήσει το geocoding παρακάτω· η φόρμα δείχνει
        // μεταφρασμένο placeholder μέσω PlaceLabel.display().
        _locationLabel = '';
      });
      final label = await LocationService.reverseGeocode(
          result.latitude, result.longitude);
      if (label != null && mounted) {
        setState(() => _locationLabel = label);
      }
    }
  }

  Future<void> _pickImage() async {
    if (_imageUrls.length >= 5) {
      _snack('cl.maxPhotos'.tr());
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Text('cl.addPhoto'.tr(),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: Text('cl.takePhoto'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.primary),
              title: Text('cl.pickGallery'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final List<XFile> files = [];
    if (source == ImageSource.camera) {
      // Κάμερα → μία φωτογραφία.
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (photo != null) files.add(photo);
    } else {
      // Γκαλερί → πολλαπλή επιλογή (όπως πριν).
      files.addAll(await picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      ));
    }
    if (files.isEmpty) return;
    setState(() => _uploadingImage = true);
    try {
      final uid = ref.read(currentUserProvider)!.uid;
      for (final file in files) {
        try {
          final ref2 = FirebaseStorage.instance.ref(
              'listings/$uid/${DateTime.now().millisecondsSinceEpoch}_${file.name}.jpg');
          // Ρητό contentType — το Android δεν το συμπεραίνει, και τα storage
          // rules απαιτούν image/* (αλλιώς δεν ανεβαίνει καμία εικόνα αγγελίας).
          await ref2.putFile(
              File(file.path), SettableMetadata(contentType: 'image/jpeg'));
          final url = await ref2.getDownloadURL();
          if (mounted) setState(() => _imageUrls = [..._imageUrls, url]);
        } catch (e) {
          _snack('${'common.error'.tr()}: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _removeImage(String url) async {
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}
    setState(() => _imageUrls = _imageUrls.where((u) => u != url).toList());
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_availableFrom ?? DateTime.now())
        : (_availableUntil ??
            (_availableFrom ?? DateTime.now()).add(const Duration(days: 3)));
    final first = isFrom ? DateTime.now() : (_availableFrom ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppColors.primary, surface: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _availableFrom = picked;
          if (_availableUntil != null && _availableUntil!.isBefore(picked)) {
            _availableUntil = null;
            _untilTime = null;
            _autoDelete = false;
          }
        } else {
          _availableUntil = picked;
        }
      });
    }
  }

  Future<void> _pickTime({required bool isFrom}) async {
    final initial = isFrom
        ? (_fromTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (_untilTime ?? const TimeOfDay(hour: 18, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppColors.primary, surface: AppColors.surface),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromTime = picked;
        } else {
          _untilTime = picked;
        }
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  DateTime? _combineDateTime(DateTime? date, TimeOfDay? time) {
    if (date == null) return null;
    if (time == null) return date;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _publish() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _snack('cl.writeTitle'.tr());
      return;
    }
    if (_location == null) {
      _snack(AppStrings.errorLocation);
      return;
    }

    final from = _availableFrom;
    final until = _availableUntil;
    if (until != null && from != null && until.isBefore(from)) {
      _snack('cl.endBeforeStart'.tr());
      return;
    }

    setState(() => _loading = true);

    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    // tags + τοποθεσία μπαίνουν κι αυτά στα keywords: ο χρήστης που γράφει το
    // tag που βλέπει στην κάρτα («εργαλεια») ή την πόλη («Αθήνα») πρέπει να
    // βρίσκει την αγγελία.
    final keywords = ListingModel.generateKeywords(
      title,
      desc,
      tags: _tags,
      locationLabel: _locationLabel,
    );

    String firstName = 'common.userFallback'.tr();
    String? userAvatar;
    try {
      final userDoc = await UserRepository().get(user.uid);
      if (userDoc != null) {
        firstName =
            userDoc.firstName.isNotEmpty ? userDoc.firstName : 'common.userFallback'.tr();
        userAvatar = userDoc.avatarUrl;
      }
    } catch (_) {}

    final effectiveAutoDelete = (_availableUntil != null) ? _autoDelete : false;

    final listing = ListingModel(
      id: '',
      userId: user.uid,
      userFirstName: firstName,
      userAvatarUrl: userAvatar,
      type: _type,
      title: title,
      description: desc,
      imageUrls: _imageUrls,
      tags: _tags,
      searchKeywords: keywords,
      location: _location!,
      locationLabel: _locationLabel,
      availableFrom: _combineDateTime(_availableFrom, _fromTime),
      availableUntil: _combineDateTime(_availableUntil, _untilTime),
      hasFromTime: _fromTime != null,
      hasUntilTime: _untilTime != null,
      autoDelete: effectiveAutoDelete,
      rating: 0,
      createdAt: DateTime.now(),
      isActive: true,
    );

    try {
      await ListingRepository().createListing(listing);

      // Ενημέρωσε τους trending tag counters (best-effort — δεν μπλοκάρει).
      if (_tags.isNotEmpty) {
        try {
          await TagsRepository().incrementTags(_tags);
        } catch (_) {}
      }

      if (mounted) {
        _snack('cl.published'.tr());
        context.pop();
      }
    } catch (e) {
      _snack(AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final canAutoDelete = _availableUntil != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.newListing),
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SECTION 1: ΤΥΠΟΣ
              _SectionHeader(icon: Icons.swap_horiz, title: 'cl.step1'.tr()),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _BigTypeChip(
                      label: AppStrings.offer,
                      selected: _type == ListingType.offer,
                      color: AppColors.offer,
                      onTap: () => setState(() => _type = ListingType.offer)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BigTypeChip(
                      label: AppStrings.seek,
                      selected: _type == ListingType.seek,
                      color: AppColors.seek,
                      onTap: () => setState(() => _type = ListingType.seek)),
                ),
              ]),

              const SizedBox(height: 28),

              // SECTION 2: ΒΑΣΙΚΑ
              _SectionHeader(
                  icon: Icons.edit_note,
                  title: _type == ListingType.offer
                      ? 'cl.step2Offer'.tr()
                      : 'cl.step2Seek'.tr()),
              const SizedBox(height: 12),

              Text('cl.titleLabel'.tr(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: 'cl.titleHint'.tr(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'cl.titleHelp'.tr(),
                style: const TextStyle(color: AppColors.textHint, fontSize: 11),
              ),
              const SizedBox(height: 16),

              Text(AppStrings.description,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                maxLines: 5,
                maxLength: 500,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(hintText: 'cl.descHint'.tr()),
              ),
              const SizedBox(height: 4),
              Text(
                'cl.descTip'.tr(),
                style: const TextStyle(color: AppColors.textHint, fontSize: 11),
              ),

              const SizedBox(height: 16),

              // Tags (ετικέτες) — βοηθούν στην αναζήτηση ανά κατηγορία
              Text('cl.tagsLabel'.tr(namedArgs: {'max': '$_maxTags'}),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
              if (_tags.length < _maxTags)
                TextField(
                  controller: _tagCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  textInputAction: TextInputAction.done,
                  onSubmitted: _addTag,
                  decoration: InputDecoration(
                    hintText: 'cl.tagsHint'.tr(),
                    prefixIcon: const Icon(Icons.tag,
                        color: AppColors.textSecondary, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add, color: AppColors.primary),
                      onPressed: () => _addTag(_tagCtrl.text),
                    ),
                  ),
                ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _tags
                      .map((t) => Chip(
                            label: Text('#$t',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13)),
                            backgroundColor: AppColors.surfaceVariant,
                            deleteIconColor: AppColors.textSecondary,
                            onDeleted: () => _removeTag(t),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ],

              const SizedBox(height: 28),

              // SECTION 3: ΦΩΤΟΓΡΑΦΙΕΣ
              _SectionHeader(
                  icon: Icons.photo_library_outlined,
                  title: 'cl.step3'.tr(),
                  trailing: Text('${_imageUrls.length}',
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 12))),
              // Ήπια παρότρυνση — ΜΟΝΟ όσο δεν έχει προστεθεί φωτογραφία, ώστε
              // να μην ενοχλεί όποιον ήδη το έκανε. Οι αγγελίες χωρίς φωτό
              // εμπνέουν λιγότερη εμπιστοσύνη και αγνοούνται.
              if (_imageUrls.isEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.lightbulb_outline,
                      color: AppColors.deal, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('cl.photoTip'.tr(),
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 11.5)),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount:
                      _imageUrls.length + (_imageUrls.length < 5 ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    if (i == _imageUrls.length) {
                      return _AddPhotoButton(
                          loading: _uploadingImage, onTap: _pickImage);
                    }
                    return Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(_imageUrls[i],
                            width: 100, height: 100, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textHint)),
                      ),
                      Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImage(_imageUrls[i]),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                  color: AppColors.danger,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 14),
                            ),
                          )),
                    ]);
                  },
                ),
              ),

              const SizedBox(height: 28),

              // SECTION 4: ΤΟΠΟΘΕΣΙΑ
              _SectionHeader(
                  icon: Icons.location_on_outlined, title: 'cl.step4'.tr()),
              const SizedBox(height: 12),
              // Μία κάρτα-χάρτης: αυτόματη αρχική θέση η δική σου, πάτα για να
              // ανοίξει ο χάρτης και να βάλεις πινέζα όπου θέλεις.
              GestureDetector(
                onTap: _locationLoading ? null : _openLocationPicker,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _location != null
                            ? AppColors.primary
                            : AppColors.border,
                        width: _location != null ? 1.5 : 0.5),
                  ),
                  child: Row(children: [
                    _locationLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary))
                        : Icon(
                            _location != null
                                ? Icons.location_on
                                : Icons.map_outlined,
                            color: AppColors.primary,
                            size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _locationLoading
                                ? 'cl.locating'.tr()
                                : (_location != null
                                    ? PlaceLabel.display(_locationLabel)
                                    : 'cl.pickOnMap'.tr()),
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text('cl.tapMapHint'.tr(),
                              style: const TextStyle(
                                  color: AppColors.textHint, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.primary, size: 20),
                  ]),
                ),
              ),

              const SizedBox(height: 28),

              // SECTION 5: ΔΙΑΘΕΣΙΜΟΤΗΤΑ
              _SectionHeader(
                  icon: Icons.event_outlined, title: 'cl.step5'.tr()),
              const SizedBox(height: 4),
              Text(
                'cl.availHelp'.tr(),
                style: const TextStyle(color: AppColors.textHint, fontSize: 11),
              ),
              const SizedBox(height: 12),

              _AvailabilityRow(
                label: 'cl.from'.tr(),
                date: _availableFrom,
                time: _fromTime,
                onPickDate: () => _pickDate(isFrom: true),
                onPickTime: () => _pickTime(isFrom: true),
                onClearDate: () => setState(() {
                  _availableFrom = null;
                  _fromTime = null;
                }),
                onClearTime: () => setState(() => _fromTime = null),
                formatDate: _formatDate,
                formatTime: _formatTime,
              ),
              const SizedBox(height: 10),

              _AvailabilityRow(
                label: 'cl.until'.tr(),
                date: _availableUntil,
                time: _untilTime,
                onPickDate: () => _pickDate(isFrom: false),
                onPickTime: () => _pickTime(isFrom: false),
                onClearDate: () => setState(() {
                  _availableUntil = null;
                  _untilTime = null;
                  _autoDelete = false;
                }),
                onClearTime: () => setState(() => _untilTime = null),
                formatDate: _formatDate,
                formatTime: _formatTime,
              ),

              const SizedBox(height: 12),

              Opacity(
                opacity: canAutoDelete ? 1.0 : 0.5,
                child: Row(children: [
                  Switch(
                    value: _autoDelete,
                    onChanged: canAutoDelete
                        ? (v) => setState(() => _autoDelete = v)
                        : null,
                    activeThumbColor: AppColors.primary,
                    activeTrackColor: AppColors.primarySurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppStrings.autoDelete,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                        if (!canAutoDelete)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'cl.autoDeleteHelp'.tr(),
                              style: const TextStyle(
                                  color: AppColors.textHint, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _loading || _locationLoading ? null : _publish,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.background))
                    : Text(AppStrings.publish),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailabilityRow extends StatelessWidget {
  final String label;
  final DateTime? date;
  final TimeOfDay? time;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback onClearDate;
  final VoidCallback onClearTime;
  final String Function(DateTime) formatDate;
  final String Function(TimeOfDay) formatTime;

  const _AvailabilityRow({
    required this.label,
    required this.date,
    required this.time,
    required this.onPickDate,
    required this.onPickTime,
    required this.onClearDate,
    required this.onClearTime,
    required this.formatDate,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: GestureDetector(
            onTap: onPickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: date != null
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.border,
                    width: 0.5),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    color: AppColors.textSecondary, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    date != null ? formatDate(date!) : 'cl.date'.tr(),
                    style: TextStyle(
                        color: date != null
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                        fontSize: 13),
                  ),
                ),
                if (date != null)
                  GestureDetector(
                    onTap: onClearDate,
                    child: const Icon(Icons.close,
                        color: AppColors.textHint, size: 14),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: date != null ? onPickTime : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: date != null
                    ? AppColors.surfaceVariant
                    : AppColors.surfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: time != null
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.border,
                    width: 0.5),
              ),
              child: Row(children: [
                Icon(Icons.access_time,
                    color: date != null
                        ? AppColors.textSecondary
                        : AppColors.textHint,
                    size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    time != null ? formatTime(time!) : 'cl.time'.tr(),
                    style: TextStyle(
                        color: time != null
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                        fontSize: 13),
                  ),
                ),
                if (time != null)
                  GestureDetector(
                    onTap: onClearTime,
                    child: const Icon(Icons.close,
                        color: AppColors.textHint, size: 14),
                  ),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    // Minimal: διακριτική «eyebrow» ετικέτα — μικρή, uppercase, με αραιά
    // γράμματα και ήσυχο χρώμα. Το εικονίδιο παραμένει μικρό και ουδέτερο.
    return Row(
      children: [
        Icon(icon, color: AppColors.textHint, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _BigTypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _BigTypeChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Minimal: καθαρό segmented κουμπί, χωρίς emoji. Επιλεγμένο = λεπτό
    // περίγραμμα + διακριτικό tint + τικ. Μη επιλεγμένο = ήσυχο.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (selected) ...[
            Icon(Icons.check_circle, color: color, size: 16),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: TextStyle(
                  color: selected ? color : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _AddPhotoButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary))
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_photo_alternate_outlined,
                      color: AppColors.primary, size: 28),
                  const SizedBox(height: 4),
                  Text('cl.addPhotoMultiline'.tr(),
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 10),
                      textAlign: TextAlign.center),
                ]),
        ),
      );
}
