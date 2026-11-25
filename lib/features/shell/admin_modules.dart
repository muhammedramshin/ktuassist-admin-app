import 'package:flutter/material.dart';
import '../../widgets/ui.dart';
import '../campaigns/campaigns_pages.dart';
import '../campaigns/home_stories_page.dart';
import '../users/roles_pages.dart';
import '../review/content_reports_page.dart';
import '../points/point_requests_page.dart';
import '../study/material_requests_page.dart';
import '../study/exam_calendars_page.dart';
import '../system/scrapers_page.dart';
import '../community/confessions_pages.dart';
import '../dashboard/dashboard_pages.dart';
import '../dashboard/listing_insights_page.dart';
import '../events/events_pages.dart';
import '../marketplace/marketplace_pages.dart';
import '../notifications/notifications_pages.dart';
import '../points/points_pages.dart';
import '../review/review_page.dart';
import '../study/academic_pages.dart';
import '../study/academic_term_page.dart';
import '../study/creation_requests_page.dart';
import '../study/materials_pages.dart';
import '../study/timetable_pages.dart';
import '../system/app_pages.dart';
import '../system/listing_expiry_page.dart';
import '../system/security_page.dart';
import '../system/storage_page.dart';
import '../forms/forms_pages.dart';
import '../users/user_activities_page.dart';
import '../users/verification_pages.dart';

class AdminModule {
  const AdminModule(
    this.label,
    this.icon,
    this.builder, {
    this.caption = '',
    this.keywords = '',
  });
  final String label, caption, keywords;
  final IconData icon;
  final WidgetBuilder builder;
}

class ModuleGroup {
  const ModuleGroup(this.title, this.icon, this.tone, this.modules);
  final String title;
  final IconData icon;
  final Tone tone;
  final List<AdminModule> modules;
}

final moduleGroups = <ModuleGroup>[
  ModuleGroup('Overview', Icons.insights_rounded, Tone.brand, [
    AdminModule(
      'Listing insights',
      Icons.bar_chart_rounded,
      (_) => const ListingInsightsPage(),
      caption: 'Events, books, jobs and tuition',
    ),
    AdminModule(
      'Content reports',
      Icons.flag_outlined,
      (_) => const ContentReportsPage(),
      caption: 'Reported content and decisions',
    ),
    AdminModule(
      'Analytics',
      Icons.query_stats_rounded,
      (_) => const AnalyticsPage(),
      caption: 'Clarity traffic & behaviour',
    ),
    AdminModule(
      'Live users',
      Icons.sensors_rounded,
      (_) => const LiveUsersPage(),
      caption: 'Who is online right now',
    ),
    AdminModule(
      'Moderation history',
      Icons.history_rounded,
      (_) => const ReviewQueuePage(history: true),
      caption: 'Undo recent actions',
      keywords: 'undo audit',
    ),
  ]),
  ModuleGroup('Study', Icons.school_rounded, Tone.info, [
    AdminModule(
      'Exam calendars',
      Icons.calendar_month_rounded,
      (_) => const ExamCalendarsPage(),
      caption: 'Build and publish schedules',
      keywords: 'timetable grid exams',
    ),
    AdminModule(
      'Exam reports',
      Icons.event_busy_outlined,
      (_) => const ExamReportsPage(),
      caption: 'Student timetable corrections',
    ),
    AdminModule(
      'Material requests',
      Icons.request_page_outlined,
      (_) => const MaterialRequestsPage(),
      caption: 'Contributions and rewards',
    ),
    AdminModule(
      'Materials',
      Icons.description_outlined,
      (_) => const MaterialsPage(),
      caption: 'Notes, papers and uploads',
      keywords: 'notes pdf',
    ),
    AdminModule(
      'Creation requests',
      Icons.playlist_add_check_rounded,
      (_) => const CreationRequestsPage(),
      caption: 'Requested subjects & courses',
    ),
    AdminModule(
      'Legacy timetables',
      Icons.calendar_month_outlined,
      (_) => const TimetablesPage(),
      caption: 'Exam timetables',
    ),
    AdminModule(
      'Academic term',
      Icons.event_repeat_rounded,
      (_) => const AcademicTermPage(),
      caption: 'Current semester calendar',
    ),
    AdminModule(
      'Subjects',
      Icons.menu_book_outlined,
      (_) => const SubjectsPage(),
    ),
    AdminModule(
      'Colleges',
      Icons.account_balance_outlined,
      (_) => const CollegesPage(),
    ),
    AdminModule(
      'Universities',
      Icons.location_city_outlined,
      (_) => const UniversitiesPage(),
    ),
    AdminModule('Schemes', Icons.layers_outlined, (_) => const SchemesPage()),
    AdminModule(
      'Courses',
      Icons.auto_stories_outlined,
      (_) => const CoursesPage(),
    ),
    AdminModule(
      'Branches',
      Icons.account_tree_outlined,
      (_) => const BranchesPage(),
    ),
    AdminModule(
      'Semesters',
      Icons.format_list_numbered_rounded,
      (_) => const SemestersPage(),
    ),
    AdminModule(
      'Material types',
      Icons.category_outlined,
      (_) => const MaterialTypesPage(),
    ),
  ]),
  ModuleGroup('Community', Icons.forum_rounded, Tone.violet, [
    AdminModule(
      'Events',
      Icons.event_outlined,
      (_) => const EventsPage(),
      caption: 'Approve and manage events',
    ),
    AdminModule(
      'Event categories',
      Icons.label_outline_rounded,
      (_) => const EventCategoriesPage(),
    ),
    AdminModule('Tags', Icons.sell_outlined, (_) => const TagsPage()),
    AdminModule(
      'Confessions',
      Icons.chat_bubble_outline_rounded,
      (_) => const ConfessionsPage(),
      caption: 'Anonymous posts',
    ),
    AdminModule(
      'Confession reports',
      Icons.flag_outlined,
      (_) => const ConfessionReportsPage(),
      keywords: 'abuse report',
    ),
    AdminModule(
      'Confession categories',
      Icons.folder_open_outlined,
      (_) => const ConfessionCategoriesPage(),
    ),
  ]),
  ModuleGroup('Marketplace', Icons.storefront_rounded, Tone.success, [
    AdminModule(
      'Books',
      Icons.import_contacts_outlined,
      (_) => const BooksPage(),
      caption: 'Second-hand book listings',
    ),
    AdminModule(
      'Book categories',
      Icons.collections_bookmark_outlined,
      (_) => const BookCategoriesPage(),
    ),
    AdminModule(
      'Tuition',
      Icons.co_present_outlined,
      (_) => const TuitionPage(),
      caption: 'Tutor & student posts',
    ),
    AdminModule(
      'Jobs',
      Icons.work_outline_rounded,
      (_) => const JobsPage(),
      caption: 'Internships and jobs',
    ),
  ]),
  ModuleGroup('Notifications', Icons.notifications_rounded, Tone.warning, [
    AdminModule(
      'Send push',
      Icons.send_rounded,
      (_) => const PushSendPage(),
      caption: 'Compose a push notification',
    ),
    AdminModule(
      'Push history',
      Icons.notifications_active_outlined,
      (_) => const PushNotificationsPage(),
      caption: 'Delivery reports',
    ),
    AdminModule(
      'KTU notifications',
      Icons.campaign_outlined,
      (_) => const KtuNotificationsPage(),
      caption: 'Scraped announcements & Telegram',
      keywords: 'telegram scrape',
    ),
  ]),
  ModuleGroup('Campaigns', Icons.campaign_rounded, Tone.violet, [
    AdminModule(
      'Home stories',
      Icons.auto_stories_outlined,
      (_) => const HomeStoriesPage(),
      caption: 'Schedule the student story rail',
    ),
    AdminModule(
      'Campaigns',
      Icons.rocket_launch_outlined,
      (_) => const CampaignsPage(),
      caption: 'Business promotions',
      keywords: 'ads',
    ),
    AdminModule(
      'Campaign payments',
      Icons.payments_outlined,
      (_) => const CampaignPaymentsPage(),
    ),
    AdminModule(
      'Campaign packages',
      Icons.inventory_2_outlined,
      (_) => const CampaignPackagesPage(),
    ),
    AdminModule(
      'Home banners',
      Icons.view_carousel_outlined,
      (_) => const HomeBannersPage(),
      caption: 'Student home carousel',
    ),
    AdminModule(
      'Legacy banners',
      Icons.photo_library_outlined,
      (_) => const LegacyBannersPage(),
    ),
  ]),
  ModuleGroup('Users & points', Icons.people_alt_rounded, Tone.info, [
    AdminModule(
      'Account roles',
      Icons.manage_accounts_outlined,
      (_) => const RolesPage(),
      caption: 'Account types and availability',
    ),
    AdminModule(
      'Associative roles',
      Icons.badge_outlined,
      (_) => const RolesPage(associative: true),
      caption: 'Badges and permissions',
    ),
    AdminModule(
      'Point requests',
      Icons.add_card_outlined,
      (_) => const PointRequestsPage(),
      caption: 'Confirm payments and credit',
    ),
    AdminModule(
      'Verification',
      Icons.verified_user_outlined,
      (_) => const VerificationRequestsPage(),
      caption: 'Student ID checks',
      keywords: 'id card',
    ),
    AdminModule(
      'User activities',
      Icons.timeline_rounded,
      (_) => const UserActivitiesPage(),
      caption: 'Activity log',
      keywords: 'audit log',
    ),
    AdminModule(
      'Point transactions',
      Icons.toll_outlined,
      (_) => const PointTransactionsPage(),
      keywords: 'credit debit',
    ),
    AdminModule(
      'Point actions',
      Icons.rule_rounded,
      (_) => const PointActionsPage(),
      caption: 'Earning rules',
    ),
  ]),
  ModuleGroup('System', Icons.settings_rounded, Tone.neutral, [
    AdminModule(
      'Scrapers',
      Icons.sync_rounded,
      (_) => const ScrapersPage(),
      caption: 'Workers, syncs and delivery',
    ),
    AdminModule(
      'Forms',
      Icons.dynamic_form_outlined,
      (_) => const FormsPage(),
      caption: 'Shareable forms & responses',
      keywords: 'survey questionnaire',
    ),
    AdminModule(
      'App feedback',
      Icons.feedback_outlined,
      (_) => const AppFeedbackPage(),
      caption: 'Bugs and suggestions',
    ),
    AdminModule(
      'App version',
      Icons.system_update_alt_rounded,
      (_) => const AppVersionPage(),
      caption: 'Force web reload',
    ),
    AdminModule(
      'Listing expiry',
      Icons.timer_outlined,
      (_) => const ListingExpiryPage(),
      caption: 'Default TTL and user overrides',
      keywords: 'expire relist days tuition books jobs events',
    ),
    AdminModule(
      'Storage',
      Icons.cloud_outlined,
      (_) => const StoragePage(),
      caption: 'Uploaded files',
    ),
    AdminModule(
      'Security',
      Icons.shield_outlined,
      (_) => const SecurityPage(),
      caption: '2FA, password, sessions',
    ),
  ]),
];
