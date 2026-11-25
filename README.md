# ktuassist-admin-app

# KTU Assist Admin

Flutter administrator app connected to the same Laravel API as the Angular `storeappktu` admin. The workspace groups 51 tools. Home, Review, Users and Profile remain navigation tabs; Modules opens a searchable icon-grid popup without changing the current tab. A global toolbar keeps Modules and Spotlight available on detail screens too.

## Management features

- Users, account roles, associative roles/badges, permissions, verification, activities, profile photos and points.
- Combined moderation inbox, resource queues, history/undo, content reports and contribution rewards.
- Academic catalogs, branch subjects, bulk import/edit/delete/restore, materials and PDF scanning/stamping.
- Exam calendars, PDF/CSV/XLSX grid import, generation preview, publishing, schedule correction reports, PDF and carousel exports, saved designs.
- Events, registrations, categories, tags, confessions, books, tuition, jobs and listing insights.
- Campaigns, payments, packages, banners and scheduled home stories.
- Push notifications, KTU announcements/Telegram, app feedback, academic terms, app version, storage, scrapers and security.

See [the screen and workflow checklist](docs/ADMIN_PARITY.md) for the Angular-to-Flutter mapping and validation scope.

## Run

```sh
flutter pub get
flutter run
```

The API base is `https://api.ktuassist.in/api/` in `lib/core/api.dart`. Use an administrator account; endpoint permissions remain enforced by the backend. The existing session implementation persists the token and profile in SharedPreferences and removes them on sign-out or an authenticated API 401. Theme and workspace pins also persist locally.

Plus Jakarta Sans is bundled for offline typography; its license is in `assets/fonts/OFL.txt`. The interface supports light/dark themes, phone/tablet layouts, larger text and reduced-motion preferences.

## Validate and build

```sh
flutter analyze
flutter test
flutter build apk --debug
```

To regenerate widget and exam-export previews:

```sh
CAPTURE_ADMIN_PREVIEWS=1 flutter test
```

Preview files are written under `test/previews/`. API tests use an injected HTTP client and do not mutate production data. The Android debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`; it is a development build, not a store-signed release.

## Module launcher and Spotlight

- Tap **Modules** in the bottom navigation or global toolbar to open the module grid.
- Tap the search icon or press **Ctrl/⌘ K** to focus Spotlight. It searches tools immediately, plus users/materials after two characters.
- **Ctrl/⌘ Shift M** opens the grid. **Enter** opens the first matching destination; **Escape** closes the popup.
- Hold a tool to pin or unpin it. Shortcuts are saved on the device.
- A modal editor/confirmation temporarily disables the global controls, preserving the current editing flow.

The admin app icon is in `assets/icons/ktu-assist-admin.png`. Platform icon assets are generated with `dart run flutter_launcher_icons`; configuration is in `flutter_launcher_icons.yaml`. The image generation prompt and source reference are recorded in `assets/icons/GENERATION.md`.
