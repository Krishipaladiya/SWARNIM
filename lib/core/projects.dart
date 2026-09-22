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

/// A slide on the app's home screen, curated in Admin Central.
///
/// Deliberately not a [ProjectSlide]. A project photograph documents a
/// building; this is an announcement aimed at residents, and while the two
/// shared a source the banner on every home screen changed whenever somebody
/// uploaded a tower photo.
class AppSlide {
  AppSlide({required this.id, required this.imageUrl, this.caption, this.linkUrl});

  final String id;

  /// Path relative to the API host. Needs a token, so this is the signed-in
  /// screen only - the login screen keeps the public project showcase.
  final String imageUrl;
  final String? caption;
  final String? linkUrl;

  factory AppSlide.fromJson(Map<String, dynamic> json) => AppSlide(
        id: json['id'] as String,
        imageUrl: json['imageUrl'] as String? ?? '',
        caption: json['caption'] as String?,
        linkUrl: json['linkUrl'] as String?,
      );
}

class ProjectRepository {
  ProjectRepository(this._dio);

  final Dio _dio;

  /// The home slider. Its own endpoint, unrelated to projects.
  Future<List<AppSlide>> slider() async {
    try {
      final response = await _dio.get('/api/v1/slider');
      return (response.data as List)
          .map((e) => AppSlide.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }

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
/// The home screen's slider. Separate from the project showcase, so adding a
/// banner does not touch project photography and vice versa.
final appSliderProvider = FutureProvider<List<AppSlide>>(
  (ref) => ref.watch(projectRepositoryProvider).slider(),
);

final publicShowcaseProvider = FutureProvider<List<ProjectShowcase>>(
  (ref) => ref.watch(projectRepositoryProvider).showcase(signedIn: false),
);

/// The home screen's slider. Includes images the builder kept off the open
/// internet - the customer has already proved who they are.
final customerShowcaseProvider = FutureProvider<List<ProjectShowcase>>(
  (ref) => ref.watch(projectRepositoryProvider).showcase(signedIn: true),
);
