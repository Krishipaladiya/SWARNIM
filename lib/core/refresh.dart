import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'complaints.dart';
import 'documents.dart';
import 'http_cache.dart';
import 'leads.dart';
import 'projects.dart';
import 'staff.dart';
import 'unit.dart';

/// Reloads everything the app is showing, from the server.
///
/// ## Why this is one function
///
/// Every screen used to invalidate the two or three providers it knew about.
/// That is correct for pull-to-refresh on that one screen and wrong for a
/// refresh button, which the user reasonably expects to mean "fetch it all
/// again" - counts in the header, the list under it, the slider, the
/// dashboard. Spreading that across screens would mean each one holding a
/// list of providers it does not own, and a provider added later being missed
/// everywhere at once.
///
/// ## The two halves, and why both are needed
///
/// Invalidating a provider makes it re-run its request. It does NOT make that
/// request reach the server: a fresh entry in the disk cache is answered off
/// the disk without any network call at all, so invalidation on its own gave
/// the screen back the bytes it was already showing. That was the whole of the
/// "refresh does not work" complaint - the providers were doing exactly what
/// they were told.
///
/// So the cache is told first, then the providers. Order matters: marking the
/// cache after invalidating would leave the re-issued requests racing a flag
/// that was not set yet.
Future<void> refreshEverything(WidgetRef ref) async {
  // Stored files keep their year-long caching - see HttpDiskCache. This makes
  // the lists and the dashboards revalidate, which is where staleness is
  // actually visible.
  (await HttpDiskCache.open()).revalidateAll();

  // Listed explicitly rather than discovered. Riverpod has no "invalidate
  // everything", and a container-wide reset would also throw away the auth
  // state and sign the user out mid-refresh.
  //
  // Deliberately NOT here: tokenStoreProvider, authControllerProvider,
  // dioProvider and the repository providers. Those hold the session and the
  // HTTP client, not data - re-creating them on a refresh would drop the
  // signed-in user's tokens and the in-flight connection.

  // The customer's own screens.
  ref.invalidate(dashboardProvider);
  ref.invalidate(myComplaintsProvider);
  ref.invalidate(complaintCategoriesProvider);
  ref.invalidate(complaintDetailProvider);
  ref.invalidate(documentsProvider);

  // Banners and project photographs.
  ref.invalidate(appSliderProvider);
  ref.invalidate(publicShowcaseProvider);
  ref.invalidate(customerShowcaseProvider);

  // Staff screens. Harmless for a customer, who simply never watches them.
  ref.invalidate(staffCountsProvider);
  ref.invalidate(staffQueueProvider);
  ref.invalidate(staffHomeQueueProvider);
  ref.invalidate(staffComplaintProvider);
  ref.invalidate(assigneesProvider);

  // Leads.
  ref.invalidate(leadsProvider);
  ref.invalidate(leadCountsProvider);
  ref.invalidate(leadDetailProvider);
}
