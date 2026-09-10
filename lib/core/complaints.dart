import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// What the API returns for a complaint in a list.
class ComplaintSummary {
  ComplaintSummary({
    required this.id,
    required this.number,
    required this.title,
    required this.category,
    required this.statusLabel,
    required this.isOpen,
    required this.raisedAt,
    this.location,
  });

  final String id;
  final String number;
  final String title;
  final String category;
  final String statusLabel;
  final bool isOpen;
  final DateTime raisedAt;
  final String? location;

  factory ComplaintSummary.fromJson(Map<String, dynamic> json) => ComplaintSummary(
        id: json['id'] as String,
        number: json['number'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? '',
        statusLabel: json['statusLabel'] as String? ?? 'Open',
        isOpen: json['isOpen'] as bool? ?? true,
        // The API always sends UTC with a trailing Z; toLocal is what puts it
        // in the customer's own timezone for display.
        raisedAt: DateTime.parse(json['raisedAt'] as String).toLocal(),
        location: json['location'] as String?,
      );
}

class ComplaintCategory {
  ComplaintCategory(this.id, this.name);

  final int id;
  final String name;

  factory ComplaintCategory.fromJson(Map<String, dynamic> json) =>
      ComplaintCategory(json['id'] as int, json['name'] as String);
}

/// A photo or video the customer picked but has not uploaded yet.
class PendingAttachment {
  PendingAttachment({required this.file, required this.isVideo});

  final File file;
  final bool isVideo;

  String get name => file.path.split(Platform.pathSeparator).last;
}

/// One attachment that failed to upload, so the UI can say which and why.
class AttachmentFailure {
  AttachmentFailure(this.name, this.reason);

  final String name;
  final String reason;
}

class ComplaintSubmission {
  ComplaintSubmission(this.complaint, this.failures);

  final ComplaintSummary complaint;
  final List<AttachmentFailure> failures;
}

/// One entry on the complaint's timeline.
class ComplaintEvent {
  ComplaintEvent({required this.at, required this.title, required this.by, this.note});

  final DateTime at;
  final String title;
  final String by;
  final String? note;

  factory ComplaintEvent.fromJson(Map<String, dynamic> json) => ComplaintEvent(
        at: DateTime.parse(json['at'] as String).toLocal(),
        title: json['title'] as String,
        by: json['by'] as String? ?? '',
        note: json['note'] as String?,
      );
}

class ComplaintAttachment {
  ComplaintAttachment({
    required this.id,
    required this.fileName,
    required this.isVideo,
    required this.sizeBytes,
    this.caption,
  });

  final String id;
  final String fileName;
  final bool isVideo;
  final int sizeBytes;
  final String? caption;

  factory ComplaintAttachment.fromJson(Map<String, dynamic> json) => ComplaintAttachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        isVideo: json['isVideo'] as bool? ?? false,
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        caption: json['caption'] as String?,
      );
}

class ComplaintDetail {
  ComplaintDetail({
    required this.summary,
    required this.timeline,
    required this.attachments,
    this.description,
    this.assignedTo,
    this.closedAt,
  });

  final ComplaintSummary summary;
  final List<ComplaintEvent> timeline;
  final List<ComplaintAttachment> attachments;
  final String? description;
  final String? assignedTo;
  final DateTime? closedAt;

  factory ComplaintDetail.fromJson(
    Map<String, dynamic> json,
    List<ComplaintAttachment> attachments,
  ) =>
      ComplaintDetail(
        summary: ComplaintSummary.fromJson(json['summary'] as Map<String, dynamic>),
        description: json['description'] as String?,
        assignedTo: json['assignedTo'] as String?,
        closedAt: json['closedAt'] == null
            ? null
            : DateTime.parse(json['closedAt'] as String).toLocal(),
        timeline: ((json['timeline'] as List?) ?? [])
            .map((e) => ComplaintEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        attachments: attachments,
      );
}

/// The code the customer reads out to the engineer.
class ClosureCode {
  ClosureCode({
    required this.complaintNumber,
    required this.complaintTitle,
    required this.engineerName,
    required this.code,
    required this.expiresAt,
    this.workSummary,
  });

  final String complaintNumber;
  final String complaintTitle;
  final String engineerName;
  final String code;
  final DateTime expiresAt;
  final String? workSummary;

  factory ClosureCode.fromJson(Map<String, dynamic> json) => ClosureCode(
        complaintNumber: json['complaintNumber'] as String,
        complaintTitle: json['complaintTitle'] as String,
        engineerName: json['engineerName'] as String,
        code: json['code'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
        workSummary: json['workSummary'] as String?,
      );
}

class ComplaintRepository {
  ComplaintRepository(this._dio);

  final Dio _dio;

  Future<List<ComplaintCategory>> categories() async {
    try {
      final response = await _dio.get('/api/v1/complaint-categories');
      return (response.data as List)
          .map((e) => ComplaintCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<List<ComplaintSummary>> list({bool? openOnly}) async {
    try {
      final response = await _dio.get(
        '/api/v1/complaints',
        queryParameters: openOnly == null ? null : {'open': openOnly},
      );
      return (response.data as List)
          .map((e) => ComplaintSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Creates the complaint, then uploads each attachment.
  ///
  /// The complaint is saved FIRST and attachments follow one by one. That order
  /// matters on a construction site: if the connection drops halfway through a
  /// video, the customer's complaint still exists rather than being lost with
  /// the upload. Failures are reported per file instead of failing the lot.
  Future<ComplaintSubmission> create({
    required int categoryId,
    required String? location,
    required String? description,
    required int priority,
    required List<PendingAttachment> attachments,
    void Function(int done, int total)? onProgress,
  }) async {
    ComplaintSummary complaint;

    try {
      final response = await _dio.post('/api/v1/complaints', data: {
        'categoryId': categoryId,
        'location': location,
        'description': description,
        'priority': priority,
      });
      complaint = ComplaintSummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }

    final failures = <AttachmentFailure>[];

    for (var i = 0; i < attachments.length; i++) {
      final attachment = attachments[i];
      try {
        await _upload(complaint.id, attachment);
      } on ApiException catch (e) {
        failures.add(AttachmentFailure(attachment.name, e.message));
      }
      onProgress?.call(i + 1, attachments.length);
    }

    return ComplaintSubmission(complaint, failures);
  }

  Future<void> _upload(String complaintId, PendingAttachment attachment) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          attachment.file.path,
          filename: attachment.name,
        ),
      });

      await _dio.post(
        '/api/v1/complaints/$complaintId/attachments',
        data: form,
        // A 100 MB video over a site connection needs far longer than the
        // client's default send timeout.
        options: Options(sendTimeout: const Duration(minutes: 5)),
      );
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Detail and attachments are two calls, fetched together so the screen has
  /// one loading state instead of two.
  Future<ComplaintDetail> detail(String complaintId) async {
    try {
      final results = await Future.wait([
        _dio.get('/api/v1/complaints/$complaintId'),
        _dio.get('/api/v1/complaints/$complaintId/attachments'),
      ]);

      final attachments = (results[1].data as List)
          .map((e) => ComplaintAttachment.fromJson(e as Map<String, dynamic>))
          .toList();

      return ComplaintDetail.fromJson(results[0].data as Map<String, dynamic>, attachments);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Returns null when nothing is outstanding - the API answers 404, which is
  /// the normal case, not an error worth showing.
  Future<ClosureCode?> pendingClosureCode(String complaintId) async {
    try {
      final response = await _dio.get('/api/v1/complaints/$complaintId/closure-code');
      return ClosureCode.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.from(e);
    }
  }

  Future<void> rejectClosure(String complaintId, String reason) async {
    try {
      await _dio.post('/api/v1/complaints/$complaintId/reject-closure',
          data: {'reason': reason});
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// The URL for an already-uploaded attachment. Needs the bearer token, so it
  /// is fetched through Dio rather than handed to Image.network.
  String fileUrl(String fileId) => '${AppConfig.apiBaseUrl}/api/v1/files/$fileId';
}

final complaintRepositoryProvider =
    Provider<ComplaintRepository>((ref) => ComplaintRepository(ref.watch(dioProvider)));

/// Categories change rarely, so this is fetched once and reused.
final complaintCategoriesProvider = FutureProvider<List<ComplaintCategory>>(
  (ref) => ref.watch(complaintRepositoryProvider).categories(),
);

/// The customer's complaints. Invalidate after filing one to refresh the list.
final myComplaintsProvider = FutureProvider<List<ComplaintSummary>>(
  (ref) => ref.watch(complaintRepositoryProvider).list(),
);

/// Detail for one complaint. Family so each complaint caches separately.
final complaintDetailProvider =
    FutureProvider.family<ComplaintDetail, String>((ref, id) =>
        ref.watch(complaintRepositoryProvider).detail(id));
