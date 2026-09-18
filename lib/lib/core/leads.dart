import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Mirrors the server's LeadStatus. Won and Lost close a lead; everything else
/// keeps it in somebody's follow-up list.
enum LeadStatus {
  newLead(1, 'New'),
  contacted(2, 'Contacted'),
  qualified(3, 'Qualified'),
  visitPlanned(4, 'Visit planned'),
  visited(5, 'Visited'),
  negotiating(6, 'Negotiating'),
  won(7, 'Booked'),
  lost(8, 'Lost');

  const LeadStatus(this.code, this.label);

  final int code;
  final String label;

  bool get isOpen => this != won && this != lost;

  static LeadStatus fromCode(int code) =>
      LeadStatus.values.firstWhere((s) => s.code == code, orElse: () => LeadStatus.newLead);
}

enum FollowUpChannel {
  call(1, 'Call'),
  whatsApp(2, 'WhatsApp'),
  siteVisit(3, 'Site visit'),
  meeting(4, 'Meeting'),
  email(5, 'Email'),
  note(6, 'Note');

  const FollowUpChannel(this.code, this.label);

  final int code;
  final String label;

  static FollowUpChannel fromCode(int code) =>
      FollowUpChannel.values.firstWhere((c) => c.code == code, orElse: () => FollowUpChannel.call);
}

class Lead {
  Lead({
    required this.id,
    required this.number,
    required this.fullName,
    required this.mobile,
    required this.status,
    required this.isOpen,
    required this.createdAt,
    required this.followUpCount,
    this.city,
    this.source,
    this.unitType,
    this.projectName,
    this.owner,
    this.nextFollowUpOn,
    this.lastContactedAt,
  });

  final String id;
  final String number;
  final String fullName;
  final String mobile;
  final String? city;
  final String? source;
  final String? unitType;
  final String? projectName;
  final LeadStatus status;
  final bool isOpen;
  final String? owner;
  final DateTime? nextFollowUpOn;
  final DateTime? lastContactedAt;
  final DateTime createdAt;
  final int followUpCount;

  /// Follow-up date has passed and the lead is still live.
  bool get isOverdue {
    if (!isOpen || nextFollowUpOn == null) return false;
    final today = DateTime.now();
    final due = nextFollowUpOn!;
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  bool get isDueToday {
    if (!isOpen || nextFollowUpOn == null) return false;
    final today = DateTime.now();
    final due = nextFollowUpOn!;
    return due.year == today.year && due.month == today.month && due.day == today.day;
  }

  factory Lead.fromJson(Map<String, dynamic> json) => Lead(
        id: json['id'] as String,
        number: json['number'] as String,
        fullName: json['fullName'] as String? ?? '',
        mobile: json['mobile'] as String? ?? '',
        city: json['city'] as String?,
        source: json['source'] as String?,
        unitType: json['unitTypeInterest'] as String?,
        projectName: json['projectName'] as String?,
        status: LeadStatus.fromCode(json['status'] as int? ?? 1),
        isOpen: json['isOpen'] as bool? ?? true,
        owner: json['owner'] as String?,
        nextFollowUpOn: json['nextFollowUpOn'] == null
            ? null
            : DateTime.parse(json['nextFollowUpOn'] as String),
        lastContactedAt: json['lastContactedAt'] == null
            ? null
            : DateTime.parse(json['lastContactedAt'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        followUpCount: json['followUpCount'] as int? ?? 0,
      );
}

class LeadFollowUp {
  LeadFollowUp({
    required this.channel,
    required this.contactedAt,
    required this.by,
    this.staffNote,
    this.customerAnswer,
    this.statusAfter,
  });

  final FollowUpChannel channel;
  final DateTime contactedAt;

  /// What we said.
  final String? staffNote;

  /// What they said back - kept separate so it survives as their words.
  final String? customerAnswer;

  final LeadStatus? statusAfter;
  final String by;

  factory LeadFollowUp.fromJson(Map<String, dynamic> json) => LeadFollowUp(
        channel: FollowUpChannel.fromCode(json['channel'] as int? ?? 1),
        contactedAt: DateTime.parse(json['contactedAt'] as String),
        staffNote: json['staffNote'] as String?,
        customerAnswer: json['customerAnswer'] as String?,
        statusAfter: json['statusAfter'] == null
            ? null
            : LeadStatus.fromCode(json['statusAfter'] as int),
        by: json['by'] as String? ?? '',
      );
}

class LeadDetail {
  LeadDetail({
    required this.lead,
    required this.followUps,
    this.altMobile,
    this.email,
    this.budgetMin,
    this.budgetMax,
    this.notes,
    this.lostReason,
  });

  final Lead lead;
  final String? altMobile;
  final String? email;
  final num? budgetMin;
  final num? budgetMax;
  final String? notes;
  final String? lostReason;
  final List<LeadFollowUp> followUps;

  factory LeadDetail.fromJson(Map<String, dynamic> json) => LeadDetail(
        lead: Lead.fromJson(json['row'] as Map<String, dynamic>),
        altMobile: json['altMobile'] as String?,
        email: json['email'] as String?,
        budgetMin: json['budgetMin'] as num?,
        budgetMax: json['budgetMax'] as num?,
        notes: json['notes'] as String?,
        lostReason: json['lostReason'] as String?,
        followUps: ((json['followUps'] as List?) ?? [])
            .map((e) => LeadFollowUp.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class LeadPage {
  LeadPage({required this.items, required this.total, required this.pageCount});

  final List<Lead> items;
  final int total;
  final int pageCount;

  factory LeadPage.fromJson(Map<String, dynamic> json) => LeadPage(
        items: ((json['items'] as List?) ?? [])
            .map((e) => Lead.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int? ?? 0,
        pageCount: json['pageCount'] as int? ?? 1,
      );
}

class LeadRepository {
  LeadRepository(this._dio);

  final Dio _dio;

  Future<LeadPage> list({
    bool mine = true,
    bool? openOnly = true,
    bool due = false,
    String? search,
  }) async {
    try {
      final response = await _dio.get('/api/v1/staff/leads', queryParameters: {
        'mine': mine,
        'openOnly': ?openOnly,
        'due': due,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'pageSize': 50,
      });
      return LeadPage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<LeadDetail> detail(String id) async {
    try {
      final response = await _dio.get('/api/v1/staff/leads/$id');
      return LeadDetail.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Existing lead on the same number, so a second record for one person is
  /// caught before it is created rather than merged later.
  Future<Lead?> findByMobile(String mobile) async {
    try {
      final response = await _dio.get('/api/v1/staff/leads/by-mobile/$mobile');
      if (response.statusCode == 204 || response.data == null) return null;
      return Lead.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      // A failed duplicate check must never block capturing a lead - the whole
      // point is that the salesperson is standing in front of somebody.
      return null;
    }
  }

  Future<String> create({
    required String fullName,
    required String mobile,
    String? altMobile,
    String? email,
    String? city,
    String? source,
    String? unitType,
    num? budgetMin,
    num? budgetMax,
    DateTime? nextFollowUpOn,
    String? notes,
  }) async {
    return _post('/api/v1/staff/leads', {
      'fullName': fullName.trim(),
      'mobile': mobile.trim(),
      'altMobile': ?_clean(altMobile),
      'email': ?_clean(email),
      'city': ?_clean(city),
      'source': ?_clean(source),
      'unitTypeInterest': ?_clean(unitType),
      'budgetMin': ?budgetMin,
      'budgetMax': ?budgetMax,
      'nextFollowUpOn': ?_date(nextFollowUpOn),
      'notes': ?_clean(notes),
    });
  }

  Future<String> addFollowUp(
    String leadId, {
    required FollowUpChannel channel,
    String? staffNote,
    String? customerAnswer,
    LeadStatus? statusAfter,
    DateTime? nextFollowUpOn,
    String? lostReason,
  }) async {
    return _post('/api/v1/staff/leads/$leadId/follow-ups', {
      'channel': channel.code,
      'staffNote': ?_clean(staffNote),
      'customerAnswer': ?_clean(customerAnswer),
      'statusAfter': ?statusAfter?.code,
      'nextFollowUpOn': ?_date(nextFollowUpOn),
      'lostReason': ?_clean(lostReason),
    });
  }

  Future<String> _post(String path, Map<String, Object?> body) async {
    try {
      final response = await _dio.post(path, data: body);
      final data = response.data;
      return data is Map<String, dynamic> ? (data['message'] as String? ?? '') : '';
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  static String? _clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

  /// Date only, no time and no zone - a follow-up is on a day, not at an
  /// instant, and sending a UTC timestamp shifts it across midnight in IST.
  static String? _date(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
}

final leadRepositoryProvider =
    Provider<LeadRepository>((ref) => LeadRepository(ref.watch(dioProvider)));

/// Which slice of the pipeline the list is showing.
enum LeadScope { due, mine, all }

class LeadFilter {
  const LeadFilter({this.scope = LeadScope.due, this.search = ''});

  final LeadScope scope;
  final String search;

  LeadFilter copyWith({LeadScope? scope, String? search}) =>
      LeadFilter(scope: scope ?? this.scope, search: search ?? this.search);

  @override
  bool operator ==(Object other) =>
      other is LeadFilter && other.scope == scope && other.search == search;

  @override
  int get hashCode => Object.hash(scope, search);
}

class LeadFilterController extends Notifier<LeadFilter> {
  @override
  LeadFilter build() => const LeadFilter();

  void setScope(LeadScope scope) => state = state.copyWith(scope: scope);
  void setSearch(String value) => state = state.copyWith(search: value);
}

final leadFilterProvider =
    NotifierProvider<LeadFilterController, LeadFilter>(LeadFilterController.new);

final leadsProvider = FutureProvider<LeadPage>((ref) {
  final filter = ref.watch(leadFilterProvider);

  return ref.watch(leadRepositoryProvider).list(
        mine: filter.scope != LeadScope.all,
        due: filter.scope == LeadScope.due,
        openOnly: filter.scope == LeadScope.due ? true : null,
        search: filter.search,
      );
});

final leadDetailProvider = FutureProvider.family<LeadDetail, String>(
  (ref, id) => ref.watch(leadRepositoryProvider).detail(id),
);

final leadCountsProvider =
    FutureProvider<({int open, int dueToday, int overdue, int wonThisMonth})>((ref) async {
  final response = await ref.watch(dioProvider).get('/api/v1/staff/leads/counts');
  final d = response.data as Map<String, dynamic>;

  return (
    open: d['open'] as int? ?? 0,
    dueToday: d['dueToday'] as int? ?? 0,
    overdue: d['overdue'] as int? ?? 0,
    wonThisMonth: d['wonThisMonth'] as int? ?? 0,
  );
});
