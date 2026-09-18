import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';

class CustomerDocument {
  CustomerDocument({
    required this.id,
    required this.title,
    required this.category,
    required this.addedAt,
    required this.sizeBytes,
    required this.contentType,
    required this.isPdf,
    required this.scopeLabel,
    required this.requiresAcknowledgement,
    this.description,
    this.documentNumber,
    this.issuedDate,
    this.acknowledgedAt,
  });

  final String id;
  final String title;
  final String? description;
  final String category;
  final String? documentNumber;
  final DateTime? issuedDate;
  final DateTime addedAt;
  final int sizeBytes;
  final String contentType;
  final bool isPdf;

  /// The file extension this document must be saved under.
  ///
  /// It decides whether the phone can open the file at all. Android and iOS
  /// both pick the viewing app from the extension, so a spreadsheet written to
  /// disk as ".jpg" - which is what happened before, because the name was
  /// built from isPdf alone - is a file nothing on the phone will open.
  String get fileExtension => switch (contentType) {
        'application/pdf' => '.pdf',
        'image/png' => '.png',
        'image/webp' => '.webp',
        'image/heic' || 'image/heif' => '.heic',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => '.docx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => '.xlsx',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation' => '.pptx',
        'application/msword' => '.doc',
        'application/vnd.ms-excel' => '.xls',
        'application/vnd.ms-powerpoint' => '.ppt',
        'text/csv' => '.csv',
        'text/plain' => '.txt',
        _ => '.jpg',
      };

  /// What KIND of document this is, for choosing an icon. Grouped rather than
  /// one case per type: the list only ever needs to say "a spreadsheet", and
  /// enumerating nine content types at the call site would put the mapping in
  /// the widget instead of on the model.
  DocumentKind get kind => switch (contentType) {
        'application/pdf' => DocumentKind.pdf,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
        'application/msword' =>
          DocumentKind.word,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
        'application/vnd.ms-excel' ||
        'text/csv' =>
          DocumentKind.sheet,
        'application/vnd.openxmlformats-officedocument.presentationml.presentation' ||
        'application/vnd.ms-powerpoint' =>
          DocumentKind.slides,
        'text/plain' => DocumentKind.text,
        _ => DocumentKind.image,
      };

  /// "Yours", "Your flat" or the building name - so the customer can tell their
  /// own agreement from a notice sent to the whole tower.
  final String scopeLabel;

  final bool requiresAcknowledgement;
  final DateTime? acknowledgedAt;

  bool get needsAcknowledgement => requiresAcknowledgement && acknowledgedAt == null;

  /// Sub-kilobyte files rounded to "0 KB", which reads as a failed upload.
  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes bytes';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).round()} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory CustomerDocument.fromJson(Map<String, dynamic> json) => CustomerDocument(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        category: json['category'] as String? ?? '',
        documentNumber: json['documentNumber'] as String?,
        issuedDate:
            json['issuedDate'] == null ? null : DateTime.parse(json['issuedDate'] as String),
        addedAt: DateTime.parse(json['addedAt'] as String),
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        contentType: json['contentType'] as String? ?? '',
        isPdf: json['isPdf'] as bool? ?? false,
        scopeLabel: json['scopeLabel'] as String? ?? '',
        requiresAcknowledgement: json['requiresAcknowledgement'] as bool? ?? false,
        acknowledgedAt: json['acknowledgedAt'] == null
            ? null
            : DateTime.parse(json['acknowledgedAt'] as String),
      );
}

class DocumentRepository {
  DocumentRepository(this._dio);

  final Dio _dio;

  Future<List<CustomerDocument>> list() async {
    try {
      final response = await _dio.get('/api/v1/me/documents');
      return (response.data as List)
          .map((e) => CustomerDocument.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Downloads a document to a private cache file and returns its path.
  ///
  /// Through Dio, so the auth interceptor attaches the bearer token - the
  /// endpoint is allocation-scoped and a plain URL handed to the OS would come
  /// back as a 401 page rendered as a broken PDF.
  ///
  /// Written to the app's cache directory, not to Downloads: a customer's sale
  /// agreement should leave with the app when they uninstall it, and should not
  /// sit in a folder every other app on the phone can read.
  Future<File> download(CustomerDocument document) async {
    try {
      final response = await _dio.get<List<int>>(
        '/api/v1/me/documents/${document.id}',
        options: Options(responseType: ResponseType.bytes),
      );

      final dir = await getTemporaryDirectory();
      final safe = document.title.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '_');
      final file = File('${dir.path}/$safe${document.fileExtension}');

      await file.writeAsBytes(response.data ?? const []);
      return file;
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<String> acknowledge(String id) async {
    try {
      final response = await _dio.post('/api/v1/me/documents/$id/acknowledge');
      final data = response.data;
      return data is Map<String, dynamic> ? (data['message'] as String? ?? '') : '';
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}

final documentRepositoryProvider =
    Provider<DocumentRepository>((ref) => DocumentRepository(ref.watch(dioProvider)));

final documentsProvider =
    FutureProvider<List<CustomerDocument>>((ref) => ref.watch(documentRepositoryProvider).list());

/// The document kinds the list shows a distinct icon for.
enum DocumentKind { pdf, word, sheet, slides, text, image }
