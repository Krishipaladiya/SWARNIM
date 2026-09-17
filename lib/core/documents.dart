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
      final file = File('${dir.path}/$safe${document.isPdf ? '.pdf' : '.jpg'}');

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
