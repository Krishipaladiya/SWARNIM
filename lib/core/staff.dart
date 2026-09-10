import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Which slice of the queue. Mirrors the server's `QueueScope` - the wire value
/// is the name, so adding one on either side is a visible break rather than an
/// index that silently shifts.
enum QueueScope {
  mine('Mine', 'Mine'),
  myTeams('MyTeams', 'My team'),
  unassigned('Unassigned', 'Unclaimed'),
  all('All', 'All');

  const QueueScope(this.wire, this.label);

  final String wire;
  final String label;
}

/// The internal status set, not the four-way one the customer sees. Staff need
/// the real thing: "parts awaited" and "on site" are different jobs.
enum WorkStatus {
  newComplaint(1, 'New'),
  assigned(2, 'Assigned'),
  acknowledged(3, 'Acknowledged'),
  onSite(4, 'On site'),
  inProgress(5, 'In progress'),
  partsAwaited(6, 'Parts awaited'),
  workDone(7, 'Work done'),
  awaitingConfirmation(8, 'Awaiting customer OTP'),
  closed(9, 'Closed'),
  reopened(10, 'Reopened'),
  cancelled(11, 'Cancelled');

  const WorkStatus(this.code, this.label);

  final int code;
  final String label;

  static WorkStatus fromCode(int code) =>
      WorkStatus.values.firstWhere((s) => s.code == code, orElse: () => WorkStatus.newComplaint);
}

enum WorkPriority {
  low(1, 'Low'),
  normal(2, 'Normal'),
  high(3, 'High'),
  urgent(4, 'Urgent');

  const WorkPriority(this.code, this.label);

  final int code;
  final String label;

  static WorkPriority fromCode(int code) =>
      WorkPriority.values.firstWhere((p) => p.code == code, orElse: () => WorkPriority.normal);
}

class StaffComplaintRow {
  StaffComplaintRow({
    required this.id,
    required this.number,
    required this.title,
    required this.category,
    required this.status,
    required this.priority,
    required this.raisedAt,
    required this.isOverdue,
    required this.isOpen,
    required this.unitLabel,
    required this.projectName,
    required this.customerName,
    this.location,
    this.slaDueAt,
    this.assignedTeam,
    this.assignedStaff,
  });

  final String id;
  final String number;
  final String title;
  final String? location;
  final String category;
  final WorkStatus status;
  final WorkPriority priority;
  final DateTime raisedAt;
  final DateTime? slaDueAt;
  final bool isOverdue;
  final bool isOpen;
  final String unitLabel;
  final String projectName;
  final String customerName;
  final String? assignedTeam;
  final String? assignedStaff;

  bool get isUnclaimed => assignedStaff == null;

  /// "Tower A · 1203" style line. Built here so every screen says it the same way.
  String get where => [projectName, unitLabel].where((s) => s.isNotEmpty).join(' · ');

  factory StaffComplaintRow.fromJson(Map<String, dynamic> json) => StaffComplaintRow(
        id: json['id'] as String,
        number: json['number'] as String,
        title: json['title'] as String? ?? '',
        location: json['location'] as String?,
        category: json['category'] as String? ?? '',
        status: WorkStatus.fromCode(json['status'] as int? ?? 1),
        priority: WorkPriority.fromCode(json['priority'] as int? ?? 2),
        raisedAt: DateTime.parse(json['raisedAt'] as String),
        slaDueAt: json['slaDueAt'] == null ? null : DateTime.parse(json['slaDueAt'] as String),
        isOverdue: json['isOverdue'] as bool? ?? false,
        isOpen: json['isOpen'] as bool? ?? true,
        unitLabel: json['unitLabel'] as String? ?? '',
        projectName: json['projectName'] as String? ?? '',
        customerName: json['customerName'] as String? ?? '',
        assignedTeam: json['assignedTeam'] as String?,
        assignedStaff: json['assignedStaff'] as String?,
      );
}

class StaffEvent {
  StaffEvent({
    required this.at,
    required this.status,
    required this.by,
    required this.visibleToCustomer,
    this.note,
    this.partsUsed,
  });

  final DateTime at;
  final WorkStatus status;
  final String? note;
  final String? partsUsed;
  final String by;

  /// Drives the "internal" marker. Staff must be able to see at a glance which
  /// of their own notes the customer can read back.
  final bool visibleToCustomer;

  factory StaffEvent.fromJson(Map<String, dynamic> json) => StaffEvent(
        at: DateTime.parse(json['at'] as String),
        status: WorkStatus.fromCode(json['status'] as int? ?? 1),
        note: json['note'] as String?,
        partsUsed: json['partsUsed'] as String?,
        by: json['by'] as String? ?? '',
        visibleToCustomer: json['visibleToCustomer'] as bool? ?? false,
      );
}

class StaffComplaintDetail {
  StaffComplaintDetail({
    required this.row,
    required this.preferredSlot,
    required this.attachmentCount,
    required this.reopenCount,
    required this.timeline,
    required this.nextStatuses,
    this.description,
    this.customerMobile,
  });

  final StaffComplaintRow row;
  final String? description;
  final String? customerMobile;
  final int preferredSlot;
  final int attachmentCount;
  final int reopenCount;
  final List<StaffEvent> timeline;

  /// What the server will accept next. The status picker is built from this, so
  /// it can never offer a move that would come back as an error.
  final List<WorkStatus> nextStatuses;

  String get slotLabel => switch (preferredSlot) {
        1 => 'Morning',
        2 => 'Evening',
        _ => 'Any time',
      };

  factory StaffComplaintDetail.fromJson(Map<String, dynamic> json) => StaffComplaintDetail(
        row: StaffComplaintRow.fromJson(json['row'] as Map<String, dynamic>),
        description: json['description'] as String?,
        customerMobile: json['customerMobile'] as String?,
        preferredSlot: json['preferredSlot'] as int? ?? 0,
        attachmentCount: json['attachmentCount'] as int? ?? 0,
        reopenCount: json['reopenCount'] as int? ?? 0,
        timeline: ((json['timeline'] as List?) ?? [])
            .map((e) => StaffEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextStatuses: ((json['nextStatuses'] as List?) ?? [])
            .map((e) => WorkStatus.fromCode(e as int))
            .toList(),
      );
}

class StaffQueuePage {
  StaffQueuePage({
    required this.items,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.hasMore,
  });

  final List<StaffComplaintRow> items;
  final int page;
  final int pageCount;
  final int total;
  final bool hasMore;

  factory StaffQueuePage.fromJson(Map<String, dynamic> json) => StaffQueuePage(
        items: ((json['items'] as List?) ?? [])
            .map((e) => StaffComplaintRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        page: json['page'] as int? ?? 1,
        pageCount: json['pageCount'] as int? ?? 1,
        total: json['total'] as int? ?? 0,
        hasMore: json['hasMore'] as bool? ?? false,
      );
}

class Assignee {
  Assignee({required this.id, required this.name, this.designation});

  final String id;
  final String name;
  final String? designation;

  factory Assignee.fromJson(Map<String, dynamic> json) => Assignee(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        designation: json['designation'] as String?,
      );
}

class StaffRepository {
  StaffRepository(this._dio);

  final Dio _dio;

  /// Identifies an image from its first bytes. Only the formats the server
  /// accepts; anything else is sent as JPEG and left for the server to refuse,
  /// because guessing harder here would just move the rejection.
  static (String extension, String mimeType) _sniff(List<int> head) {
    bool starts(List<int> magic) =>
        head.length >= magic.length &&
        Iterable<int>.generate(magic.length).every((i) => head[i] == magic[i]);

    if (starts([0x89, 0x50, 0x4E, 0x47])) return ('png', 'image/png');
    if (starts([0x47, 0x49, 0x46, 0x38])) return ('gif', 'image/gif');
    if (head.length >= 12 &&
        starts([0x52, 0x49, 0x46, 0x46]) &&
        head[8] == 0x57 && head[9] == 0x45 && head[10] == 0x42 && head[11] == 0x50) {
      return ('webp', 'image/webp');
    }
    return ('jpg', 'image/jpeg');
  }

  Future<StaffQueuePage> queue({
    QueueScope scope = QueueScope.myTeams,
    bool? openOnly = true,
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get('/api/v1/staff/complaints', queryParameters: {
        'scope': scope.wire,
        'openOnly': ?openOnly,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'page': page,
        'pageSize': pageSize,
      });
      return StaffQueuePage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<StaffComplaintDetail> detail(String id) async {
    try {
      final response = await _dio.get('/api/v1/staff/complaints/$id');
      return StaffComplaintDetail.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<Assignee>> assignees() async {
    try {
      final response = await _dio.get('/api/v1/staff/assignees');
      return (response.data as List)
          .map((e) => Assignee.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<String> claim(String id) => _post('/api/v1/staff/complaints/$id/claim', null);

  Future<String> assign(String id, {String? staffId, String? note}) =>
      _post('/api/v1/staff/complaints/$id/assign', {
        'staffId': ?staffId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  Future<String> addUpdate(
    String id, {
    WorkStatus? status,
    String? note,
    String? partsUsed,
    required bool visibleToCustomer,
  }) =>
      _post('/api/v1/staff/complaints/$id/updates', {
        if (status != null) 'status': status.code,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (partsUsed != null && partsUsed.trim().isNotEmpty) 'partsUsed': partsUsed.trim(),
        'visibleToCustomer': visibleToCustomer,
      });

  /// Uploads a photo against a complaint and returns the stored file's id.
  ///
  /// Used for the proof-of-work photo the server requires before it will issue
  /// a closure code.
  Future<String> uploadPhoto(String complaintId, String path, {String? caption}) async {
    try {
      // The server sniffs magic bytes and rejects a file whose content does not
      // match its declared type. image_picker re-encodes to JPEG when asked to
      // resize but keeps the original name, so a picked .png arrives as JPEG
      // bytes - trusting the extension is how that becomes a rejected upload.
      final file = File(path);
      final head = await file.openRead(0, 12).expand((c) => c).toList();
      final (extension, mimeType) = _sniff(head);

      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          path,
          filename: 'proof.$extension',
          contentType: DioMediaType.parse(mimeType),
        ),
        'caption': ?caption,
      });

      final response = await _dio.post(
        '/api/v1/staff/complaints/$complaintId/attachments',
        data: form,
        // Site connections are slow and a phone photo is several megabytes.
        options: Options(sendTimeout: const Duration(minutes: 5)),
      );

      return (response.data as Map<String, dynamic>)['id'] as String;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Asks the server to issue the customer's closure code. The code itself is
  /// never returned here - it goes to the customer's app, and the engineer has
  /// to be told it out loud. That is the whole point of the control.
  ///
  /// [proofFileId] comes from [uploadPhoto]. The server can be configured to
  /// insist on one, which is why the app uploads first and requests second
  /// rather than the other way round.
  Future<void> requestClosureCode(
    String id, {
    String? workSummary,
    String? proofFileId,
    double? latitude,
    double? longitude,
  }) async {
    await _post('/api/v1/staff/complaints/$id/closure-code', {
      if (workSummary != null && workSummary.trim().isNotEmpty) 'workSummary': workSummary.trim(),
      'proofFileId': ?proofFileId,
      'latitude': ?latitude,
      'longitude': ?longitude,
    });
  }

  Future<String> closeWithCode(String id, String code) =>
      _post('/api/v1/staff/complaints/$id/close', {'code': code.trim()});

  Future<String> _post(String path, Map<String, Object?>? body) async {
    try {
      final response = await _dio.post(path, data: body ?? const <String, Object?>{});
      final data = response.data;
      return data is Map<String, dynamic> ? (data['message'] as String? ?? '') : '';
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}

final staffRepositoryProvider =
    Provider<StaffRepository>((ref) => StaffRepository(ref.watch(dioProvider)));

/// The queue filter the staff screens share, so switching tabs and coming back
/// does not silently reset what the person was looking at.
class QueueFilter {
  const QueueFilter({
    this.scope = QueueScope.myTeams,
    this.openOnly = true,
    this.search = '',
  });

  final QueueScope scope;
  final bool openOnly;
  final String search;

  QueueFilter copyWith({QueueScope? scope, bool? openOnly, String? search}) => QueueFilter(
        scope: scope ?? this.scope,
        openOnly: openOnly ?? this.openOnly,
        search: search ?? this.search,
      );

  @override
  bool operator ==(Object other) =>
      other is QueueFilter &&
      other.scope == scope &&
      other.openOnly == openOnly &&
      other.search == search;

  @override
  int get hashCode => Object.hash(scope, openOnly, search);
}

class QueueFilterController extends Notifier<QueueFilter> {
  @override
  QueueFilter build() => const QueueFilter();

  void setScope(QueueScope scope) => state = state.copyWith(scope: scope);
  void setOpenOnly(bool value) => state = state.copyWith(openOnly: value);
  void setSearch(String value) => state = state.copyWith(search: value);
}

final queueFilterProvider =
    NotifierProvider<QueueFilterController, QueueFilter>(QueueFilterController.new);

/// The queue for the current filter. Watching the filter means changing a chip
/// refetches without any manual plumbing.
final staffQueueProvider = FutureProvider<StaffQueuePage>((ref) {
  final filter = ref.watch(queueFilterProvider);
  return ref.watch(staffRepositoryProvider).queue(
        scope: filter.scope,
        openOnly: filter.openOnly,
        search: filter.search,
      );
});

final staffComplaintProvider = FutureProvider.family<StaffComplaintDetail, String>(
  (ref, id) => ref.watch(staffRepositoryProvider).detail(id),
);

final assigneesProvider =
    FutureProvider<List<Assignee>>((ref) => ref.watch(staffRepositoryProvider).assignees());

/// Home-screen counts. Three separate calls rather than one summary endpoint:
/// each is a cheap COUNT the server already computes for paging, and it avoids
/// inventing an endpoint that would need changing every time a tile does.
final staffCountsProvider = FutureProvider<({int mine, int unclaimed, int overdue})>((ref) async {
  final repo = ref.watch(staffRepositoryProvider);

  final results = await Future.wait([
    repo.queue(scope: QueueScope.mine, pageSize: 1),
    repo.queue(scope: QueueScope.unassigned, pageSize: 1),
    repo.queue(scope: QueueScope.myTeams, pageSize: 100),
  ]);

  return (
    mine: results[0].total,
    unclaimed: results[1].total,
    overdue: results[2].items.where((r) => r.isOverdue).length,
  );
});
