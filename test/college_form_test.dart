import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ktu_assist_admin_app/core/json.dart';
import 'package:ktu_assist_admin_app/features/study/academic_pages.dart';
import 'package:ktu_assist_admin_app/theme/app_theme.dart';
import 'package:ktu_assist_admin_app/widgets/forms.dart';

const bannerA = 'https://cdn.example.com/banner-a';
const bannerB = 'https://cdn.example.com/banner-b';
const gallery1 = 'https://cdn.example.com/gallery-1';
const gallery2 = 'https://cdn.example.com/gallery-2';
const gallery3 = 'https://cdn.example.com/gallery-3';

final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    HttpOverrides.global = _ImageOverrides();
  });
  tearDownAll(() => HttpOverrides.global = null);

  test('upload fields keep the books folder unless one is set', () {
    const plain = FieldSpec('banner', 'Banner', type: FieldType.upload);
    expect(plain.folder, 'books');
    expect(plain.uploadTarget, UploadTarget.link);
    expect(plain.imagesOnly, isTrue);
  });

  test('places the banner and gallery after description', () {
    expect(CollegesPage.formFields.map((field) => field.key).toList(), [
      'college_name',
      'code',
      'university',
      'district',
      'description',
      'banner_image',
      'images',
      'address',
      'website',
      'contact',
    ]);
    final banner = CollegesPage.formFields.firstWhere(
      (field) => field.key == 'banner_image',
    );
    expect(banner.label, 'Banner image');
    expect(banner.type, FieldType.upload);
    expect(banner.imagesOnly, isTrue);
    expect(banner.uploadTarget, UploadTarget.link);
    expect(banner.folder, 'colleges');
    expect(banner.required, isFalse);
    final gallery = CollegesPage.formFields.firstWhere(
      (field) => field.key == 'images',
    );
    expect(gallery.label, 'College images');
    expect(gallery.type, FieldType.gallery);
    expect(gallery.folder, 'colleges');
    expect(gallery.required, isFalse);
  });

  test('loads banner and gallery urls back into the form', () {
    final images = [gallery1, gallery2];
    final row = {
      'id': 4,
      'college_name': 'Example College',
      'code': 'EX',
      'banner_image': bannerA,
      'images': images,
      'university': {'id': 2, 'name': 'KTU'},
    };
    final initial = CollegesPage.initialValues(row);
    expect(initial['banner_image'], bannerA);
    expect(initial['images'], images);
    expect(identical(initial['images'], images), isFalse);
    expect(initial['university'], 2);
    expect(CollegesPage.initialValues({'id': 1})['banner_image'], isNull);
    expect(CollegesPage.initialValues({'id': 1})['images'], isNull);
  });

  test('sends a banner and new gallery urls, and omits an empty gallery', () {
    expect(
      collegeFormBody({
        'college_name': 'Example College',
        'banner_image': bannerA,
        'images': [gallery1, gallery2],
      }),
      {
        'college_name': 'Example College',
        'banner_image': bannerA,
        'images': [gallery1, gallery2],
      },
    );
    expect(
      collegeFormBody({
        'college_name': 'Example College',
        'banner_image': bannerB,
        'images': [gallery3],
      }),
      {
        'college_name': 'Example College',
        'banner_image': bannerB,
        'images': [gallery3],
      },
    );

    final untouched = collegeFormBody({
      'college_name': 'Example College',
      'description': 'Updated',
      'banner_image': bannerA,
      'images': <String>[],
    });
    expect(untouched.containsKey('images'), isFalse);
    expect(untouched['banner_image'], bannerA);
    expect(untouched['description'], 'Updated');

    final cleared = collegeFormBody({
      'banner_image': null,
      'images': <String>[],
    });
    expect(cleared.containsKey('banner_image'), isTrue);
    expect(cleared['banner_image'], isNull);
    expect(cleared.containsKey('images'), isFalse);

    expect(
      collegeFormBody({
        'college_name': 'Example College',
        'code': 'EX',
        'university': 1,
        'is_active': true,
      }),
      {
        'college_name': 'Example College',
        'code': 'EX',
        'university': 1,
        'is_active': true,
      },
    );
  });

  testWidgets(
    'create saves a banner and two gallery images, then reloads them',
    (tester) async {
      final harness = _Harness();
      await harness.open(tester);
      await harness.type(tester, 'College name *', 'Example College');
      await harness.paste(tester, 'Add', bannerA);
      await harness.paste(tester, 'Add image', gallery1);
      await harness.paste(tester, 'Add image', gallery2);

      expect(
        find.byKey(const ValueKey('banner:banner_image:$bannerA')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pending:images:$gallery1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pending:images:$gallery2')),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove new image'), findsNWidgets(2));
      expect(find.text('Saved'), findsNothing);

      await harness.save(tester, 'Create');
      final body = collegeFormBody(harness.submitted!);
      expect(body['banner_image'], bannerA);
      expect(body['images'], [gallery1, gallery2]);

      final reloaded = CollegesPage.initialValues({
        'id': 8,
        'college_name': 'Example College',
        'banner_image': body['banner_image'],
        'images': body['images'],
      });
      await harness.open(
        tester,
        initial: reloaded,
        submitLabel: 'Save changes',
      );
      expect(
        find.byKey(const ValueKey('banner:banner_image:$bannerA')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved:images:$gallery1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved:images:$gallery2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pending:images:$gallery1')),
        findsNothing,
      );
      expect(find.byTooltip('Remove new image'), findsNothing);
      expect(find.text('Saved'), findsOneWidget);
    },
  );

  testWidgets(
    'replacing the banner and adding one image sends only the new gallery url',
    (tester) async {
      final harness = _Harness();
      await harness.open(
        tester,
        initial: CollegesPage.initialValues({
          'id': 8,
          'college_name': 'Example College',
          'banner_image': bannerA,
          'images': [gallery1, gallery2],
        }),
        submitLabel: 'Save changes',
      );
      await harness.paste(tester, 'Replace', bannerB);
      await harness.paste(tester, 'Add image', gallery3);
      expect(
        find.byKey(const ValueKey('banner:banner_image:$bannerB')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved:images:$gallery1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved:images:$gallery2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pending:images:$gallery3')),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove new image'), findsOneWidget);

      await harness.save(tester, 'Save changes');
      final body = collegeFormBody(harness.submitted!);
      expect(body['banner_image'], bannerB);
      expect(body['images'], [gallery3]);

      await harness.open(
        tester,
        initial: CollegesPage.initialValues({
          'id': 8,
          'college_name': 'Example College',
          'banner_image': body['banner_image'],
          'images': [gallery1, gallery2, gallery3],
        }),
        submitLabel: 'Save changes',
      );
      expect(
        find.byKey(const ValueKey('banner:banner_image:$bannerB')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved:images:$gallery1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved:images:$gallery2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved:images:$gallery3')),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove new image'), findsNothing);
    },
  );

  testWidgets(
    'an edit that does not add images omits images from the request',
    (tester) async {
      final harness = _Harness();
      await harness.open(
        tester,
        initial: CollegesPage.initialValues({
          'id': 8,
          'college_name': 'Example College',
          'description': 'About',
          'banner_image': bannerA,
          'images': [gallery1, gallery2],
        }),
        submitLabel: 'Save changes',
      );
      await harness.type(tester, 'Description', 'Updated description');
      await harness.save(tester, 'Save changes');

      expect(harness.submitted!['images'], isEmpty);
      expect(harness.submitted!['banner_image'], bannerA);
      final body = collegeFormBody(harness.submitted!);
      expect(body.containsKey('images'), isFalse);
      expect(body['banner_image'], bannerA);
      expect(body['description'], 'Updated description');
      expect(body['college_name'], 'Example College');
    },
  );

  testWidgets(
    'a new gallery image can be dropped before save, and saved images cannot',
    (tester) async {
      final harness = _Harness();
      await harness.open(
        tester,
        initial: CollegesPage.initialValues({
          'id': 8,
          'college_name': 'Example College',
          'banner_image': bannerA,
          'images': [gallery1],
        }),
        submitLabel: 'Save changes',
      );
      expect(find.byTooltip('Remove new image'), findsNothing);
      await harness.paste(tester, 'Add image', gallery1);
      expect(find.text('This image is already in the gallery'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pending:images:$gallery1')),
        findsNothing,
      );

      await harness.paste(tester, 'Add image', gallery3);
      expect(find.byTooltip('Remove new image'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Remove new image'));
      await tester.tap(find.byTooltip('Remove new image'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pending:images:$gallery3')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('saved:images:$gallery1')),
        findsOneWidget,
      );

      await harness.save(tester, 'Save changes');
      expect(
        collegeFormBody(harness.submitted!).containsKey('images'),
        isFalse,
      );
    },
  );

  testWidgets('removing the banner sends null', (tester) async {
    final harness = _Harness();
    await harness.open(
      tester,
      initial: CollegesPage.initialValues({
        'id': 8,
        'college_name': 'Example College',
        'banner_image': bannerA,
        'images': [gallery1],
      }),
      submitLabel: 'Save changes',
    );
    await tester.ensureVisible(find.text('Remove'));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('banner:banner_image:$bannerA')),
      findsNothing,
    );
    expect(find.text('No file selected'), findsOneWidget);

    await harness.save(tester, 'Save changes');
    final body = collegeFormBody(harness.submitted!);
    expect(body.containsKey('banner_image'), isTrue);
    expect(body['banner_image'], isNull);
    expect(body.containsKey('images'), isFalse);
  });
}

class _Harness {
  Json? submitted;

  List<FieldSpec> get fields => [
    for (final key in const [
      'college_name',
      'description',
      'banner_image',
      'images',
    ])
      CollegesPage.formFields.firstWhere((field) => field.key == key),
  ];

  Future<void> open(
    WidgetTester tester, {
    Json initial = const {},
    String submitLabel = 'Create',
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    submitted = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showFormSheet(
                context,
                title: 'College',
                fields: fields,
                initial: initial,
                submitLabel: submitLabel,
                onSubmit: (values) async =>
                    submitted = Map<String, dynamic>.from(values),
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String label, String value) async {
    final field = find.widgetWithText(TextField, label);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> paste(WidgetTester tester, String button, String url) async {
    final opener = find.widgetWithText(OutlinedButton, button);
    await tester.ensureVisible(opener);
    await tester.tap(opener);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste URL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Image or file URL'),
      url,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use this file'));
    await tester.tap(find.text('Use this file'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }
}

class _ImageOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _ImageClient();
}

class _ImageClient extends Fake implements HttpClient {
  @override
  set autoUncompress(bool value) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest();
}

class _ImageRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _ImageResponse();
}

class _ImageResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _png.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_png).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
