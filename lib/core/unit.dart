import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'complaints.dart';

/// Everything the home screen shows about the customer's flat.
class UnitDashboard {
  UnitDashboard({
    required this.loginId,
    required this.unitNumber,
    required this.buildingName,
    required this.projectName,
    required this.customerName,
    required this.progressPercent,
    required this.isUnderMaintenance,
    required this.activeComplaints,
    this.floorNumber,
    this.unitType,
    this.progressNote,
    this.maintenanceEndsOn,
    this.maintenanceDaysRemaining,
  });

  final String loginId;
  final String unitNumber;
  final int? floorNumber;
  final String? unitType;
  final String buildingName;
  final String projectName;
  final String customerName;

  final int progressPercent;
  final String? progressNote;

  /// False once the builder's cover has lapsed - the app then hides
  /// "File complaint" rather than letting the customer hit a server rejection.
  final bool isUnderMaintenance;
  final DateTime? maintenanceEndsOn;
  final int? maintenanceDaysRemaining;

  final List<ComplaintSummary> activeComplaints;

  /// "SWH-A-1203" style label built from the parts the API returns.
  String get unitLabel => loginId.isNotEmpty ? loginId : unitNumber;

  String get locationLine => [
        buildingName,
        if (floorNumber != null) 'Floor $floorNumber',
        if (unitType != null && unitType!.isNotEmpty) unitType!,
      ].join(', ');

  factory UnitDashboard.fromJson(Map<String, dynamic> json) => UnitDashboard(
        loginId: json['loginId'] as String? ?? '',
        unitNumber: json['unitNumber'] as String? ?? '',
        floorNumber: json['floorNumber'] as int?,
        unitType: json['unitType'] as String?,
        buildingName: json['buildingName'] as String? ?? '',
        projectName: json['projectName'] as String? ?? '',
        customerName: json['customerName'] as String? ?? '',
        progressPercent: json['progressPercent'] as int? ?? 0,
        progressNote: json['progressNote'] as String?,
        isUnderMaintenance: json['isUnderMaintenance'] as bool? ?? true,
        maintenanceEndsOn: json['maintenanceEndsOn'] == null
            ? null
            : DateTime.parse(json['maintenanceEndsOn'] as String),
        maintenanceDaysRemaining: json['maintenanceDaysRemaining'] as int?,
        activeComplaints: ((json['activeComplaints'] as List?) ?? [])
            .map((e) => ComplaintSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class UnitRepository {
  UnitRepository(this._dio);

  final Dio _dio;

  Future<UnitDashboard> dashboard() async {
    try {
      final response = await _dio.get('/api/v1/me/unit');
      return UnitDashboard.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.from(e);
    }
  }
}

final unitRepositoryProvider =
    Provider<UnitRepository>((ref) => UnitRepository(ref.watch(dioProvider)));

final dashboardProvider =
    FutureProvider<UnitDashboard>((ref) => ref.watch(unitRepositoryProvider).dashboard());
