# Angular admin → Flutter management checklist

Compared against `storeappktu/src/app/admin/admin-routing.module.ts`, its routed components and API service, and the local Laravel routes/controllers. Related web routes are combined into mobile screens and bottom-sheet forms. This is an implementation inventory, not a claim that every endpoint has been exercised against production.

| Angular screen/routes | Flutter entry and supported workflow |
| --- | --- |
| Dashboard | Home: operational counts, review shortcuts, live audience, health; Workspace → Listing insights: events/books/jobs/tuition totals, status, engagement, trends, awaiting review and top listings |
| Review / review detail | Review: combined pending inbox, resource/status/search queues, detailed record navigation, selection/actions/reasons, moderation history and undo |
| Content reports | Workspace → Content reports: open/removed/dismissed reports, reporter/context, required decision notes, dismiss/remove |
| Users / user management / activities | Users tab: search, edit, student profile, account role, permissions, devices, points, associative role assignment/expiry and profile photo upload/removal; Workspace → User activities |
| Roles / associative roles | Workspace: create/edit/status/sort order, system-code protection, permission catalog, badge settings and permitted deletion |
| Verification list/detail | Workspace → Verification: request filters, student profile, private documents, previous requests, approve/reject/reward review |
| Points actions/transactions/requests | Workspace: action configuration, role/user overrides, effective points, transactions, credits/debits, purchase requests with payment confirmation and rejection |
| University/schemes/courses/semesters/material types/colleges/subjects | Workspace → Study: catalog forms, filters and supported import/export; college banner/gallery retained |
| Branch list/detail | Branches → branch: semester/scheme subjects, search/status/deleted filters, add/edit, previewed spreadsheet import, export, bulk edit/activation/deletion/restoration, branch deletion impact preview |
| Creation requests | Create a subject from request metadata; inspect/update/delete requests |
| Materials list/new/detail | Server-paginated search and subject/type/status filters, CSV page export, create/edit/upload/verification/delete; file scan, configurable watermark/branding, PDF preview/download, stamped variant assignment and deletion |
| Material requests/review detail | Request list/detail, contribution material navigation, approve/reject with review notes, payout-mode changes and reward settlement |
| Exam calendar list/detail | Metadata CRUD; editable columns/slots; text-based PDF/CSV/XLSX import; mapping checks and discard guard; grid export; dry-run generation, generation and publish/unpublish |
| Exam calendar schedule/export | Paginated subject search/branch/scheme/semester/reported filters, item CRUD, CSV export, grouped timetable PDF, carousel preview/PNG sharing, design editing and saved template create/update/default/delete |
| Exam reports | Open/resolved/dismissed filtering, report context, exam correction and report resolution |
| Events list/new/detail | Create/edit/approve/reject/delete; event registration status updates, comments, exports; categories and tags; category file import/template |
| Confessions/list/detail/reports/categories | Moderation, comments/reactions/reports and category management |
| Books/list/detail/categories | Listings, status/approval/edit/soft deletion, interested/flagging students, report updates and categories |
| Tuition/list/detail | Create/edit/approval/deletion and listing filters |
| Jobs/list/detail | Create/edit/approval/rejection reason/deletion and listing filters |
| Campaign list/detail/packages/payments | Campaign status/pricing/schedule, payment recording/review, package management and promotional content |
| Home banners/new/edit + legacy banners | Forms/uploads/actions/links, enabled state and ordering |
| Home stories/new/edit | Custom/campaign stories, uploads/content/links/actions/colors, date scheduling, enabled state and ordering |
| KTU notifications/detail | List/detail, scrape trigger, announcement card and Telegram send/test actions |
| Push notifications/new/detail | Compose/target/send, history and delivery detail |
| App feedback/list/detail | Filter, inspect, respond/update status |
| Academic term | Term settings and transition controls |
| App version | Current version and web reload control |
| Files | Storage folders/files/page tokens, usage inspection, original-file opening and confirmed deletion |
| Security | Password, 2FA, session policy and device/session controls |
| Scrapers | Worker/schedule/last sync/delivery counts and refresh |

## Mobile design

Bundled Plus Jakarta Sans, yellow/ink accents, themed surfaces, clear page titles, responsive cards, searchable categories, persistent pinned tools, large touch targets and consistent forms/loading/error states. Page entrances use a short fade/slide; reduced-motion disables these transitions and the dashboard pulse. Inactive shell tabs suspend tickers.

## Verification

- Static analyzer and Flutter tests cover module opening at phone width, light/dark workspace, 320-pixel large-text layout, tablet layout and meaningful mutation contracts.
- Workflow tests cover payment confirmation/integer validation, role-expiry retention, required moderation notes, contribution rejection, catalog-driven queue aggregation, stale-response protection, failed lookup protection, calendar mapping/save payloads and authenticated download headers.
- Calendar parser fixtures are copied from the Angular calendar parser tests. Checks cover metadata, programme ordering, combined semesters, sessions, split course codes and unresolved mapping behavior.
- Generated A4/carousel PDFs include long semester groups; rendered preview files are in `test/previews/`.
- Android debug APK builds locally. No Android device was connected during validation. Production login, live endpoint mutations, native file picker/share sheets and iOS execution still require device smoke testing.

## Backend differences and behavior

- The local Laravel event-category import accepts multipart CSV/XLS/XLSX. Flutter follows that implemented contract; Angular currently submits JSON rows instead.
- The combined pending inbox shows up to 100 entries for each queue target, matching the web inbox approach. Resource-specific queues provide pagination for the rest.
- Materials use the admin-list API for server filtering and pagination; exports from that screen are explicitly the displayed page.
- Google Drive files open their Drive preview because access may require a separate Google session. Direct PDFs/images render inside Flutter.
- Imported PDFs must contain extractable text. Review the draft and unresolved mappings before saving and publishing; scanned-image PDFs require CSV/Excel/manual entry.
