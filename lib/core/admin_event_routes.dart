import 'package:flutter/material.dart';

import '../features/campaigns/campaigns_pages.dart';
import '../features/community/confessions_pages.dart';
import '../features/events/events_pages.dart';
import '../features/marketplace/marketplace_pages.dart';
import '../features/points/point_requests_page.dart';
import '../features/review/content_reports_page.dart';
import '../features/review/review_page.dart';
import '../features/study/creation_requests_page.dart';
import '../features/study/material_requests_page.dart';
import '../features/study/materials_pages.dart';
import '../features/system/app_pages.dart';
import '../features/system/storage_page.dart';
import '../features/users/users_page.dart';
import '../features/users/verification_pages.dart';

/// Screen to open when an admin taps an event push. Null keeps them on Home.
Widget? pageForAdminEvent(String event) {
  switch (event) {
    case 'user_signup':
      return const UsersPage();
    case 'verification_submitted':
      return const VerificationRequestsPage();
    case 'material_uploaded':
      return const MaterialsPage();
    case 'file_uploaded':
      return const StoragePage();
    case 'material_request':
      return const MaterialRequestsPage();
    case 'creation_request':
      return const CreationRequestsPage();
    case 'point_purchase':
      return const PointRequestsPage();
    case 'event_submitted':
      return const EventsPage();
    case 'book_submitted':
      return const BooksPage();
    case 'job_submitted':
      return const JobsPage();
    case 'tuition_submitted':
      return const TuitionPage();
    case 'confession_submitted':
      return const ConfessionsPage();
    case 'book_report':
      return const ReviewQueuePage(
        resource: 'book_reports',
        status: 'needs_review',
      );
    case 'confession_report':
      return const ConfessionReportsPage();
    case 'content_report':
      return const ContentReportsPage();
    case 'app_feedback':
      return const AppFeedbackPage();
    case 'campaign_submitted':
      return const CampaignsPage();
    case 'campaign_payment':
      return const CampaignPaymentsPage();
    default:
      return null;
  }
}
