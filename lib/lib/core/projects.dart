import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class ProjectSlide {
  ProjectSlide({required this.id, required this.imageUrl, this.caption});

  final String id;

  /// Path relative to the API host. Public slides resolve without a token;
  /// the signed-in variant needs one, which is why the widget is told which.
  final String imageUrl;
  final String? caption;

  factory ProjectSlide.fromJson(Map<String, dynamic> json) => ProjectSlide(
        id: json['id'] as String,
        imageUrl: json['imageUrl'] as String? ?? '',
        caption: json['caption'] as String?,
      );
}

class ProjectShowcase {
  ProjectShowcase({
    required this.id,
    required this.name,
    required this.slides,
    this.city,
    this.tagline,
  });

  final String id;
  final String name;
  final String? city;
  final String? tagline;
  final List<ProjectSlide> slides;

  factory ProjectShowcase.fromJson(Map<String, dynamic> json) => ProjectShowcase(
        id: json['projectId'] as String,
        name: json['name'] as String? ?? '',
        city: json['city'] as String?,
        tagline: json['tagline'] as String?,
        slides: ((json['slides'] as List?) ?? [])
            .map((e) => ProjectSlide.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProjectRepository {
  ProjectRepository(this._dio);

  final Dio _dio;

  Future<List<ProjectShowcase>> showcase({required bool signedIn}) async {
    try {
      final response = await _dio.get(signedIn ? '/api/v1/projects' : '/api/v1/public/projects');
      return (response.data as List)
          .map((e) => ProjectShowcase.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}

final projectRepositoryProvider =
    Provider<ProjectRepository>((ref) => ProjectRepository(ref.watch(dioProvider)));

/// The login screen's slider. Public images only, and no token is sent.
final publicShowcaseProvider = FutureProvider<List<ProjectShowcase>>(
  (ref) => ref.watch(projectRepositoryProvider).showcase(signedIn: false),
);

/// The home screen's slider. Includes images the builder kept off the open
/// internet - the customer has already proved who they are.
final customerShowcaseProvider = FutureProvider<List<ProjectShowcase>>(
  (ref) => ref.watch(projectRepositoryProvider).showcase(signedIn: true),
);
