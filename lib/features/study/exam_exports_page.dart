import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api.dart';
import '../../core/json.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/forms.dart';
import '../../widgets/ui.dart';

const defaultExamDesign = <String, dynamic>{
  'title': 'EXAM TIMETABLE',
  'footer': 'Save & share · app.ktuassist.in',
  'background': '#ffffff',
  'textColor': '#172033',
  'accent': '#fbbf24',
  'timetableBackground': '#ffffff',
  'timetableTextColor': '#172033',
  'timetableAccent': '#fbbf24',
  'coverTextScale': 1.0,
  'tableFontSize': 26,
  'rowsPerSlide': 6,
  'alignment': 'left',
  'showLogo': true,
  'logo': 'ktu',
  'logoBackground': 'white',
  'fitSemester': true,
};

List<List<Json>> examGroups(List<Json> items) {
  final groups = <String, List<Json>>{};
  for (final row in items) {
    groups
        .putIfAbsent(
          '${row['branch_id']}|${row['scheme_id']}|${row['semester_id']}',
          () => [],
        )
        .add(row);
  }
  for (final group in groups.values) {
    group.sort(
      (a, b) => '${a['exam_date']} ${a['session']}'.compareTo(
        '${b['exam_date']} ${b['session']}',
      ),
    );
  }
  return groups.values.toList()..sort(
    (
      a,
      b,
    ) => '${a.first['branch_name']} ${a.first['scheme_name']} ${a.first['semester_code']}'
        .compareTo(
          '${b.first['branch_name']} ${b.first['scheme_name']} ${b.first['semester_code']}',
        ),
  );
}

Future<Uint8List> buildExamPdf(
  List<Json> items,
  String title,
  Json design, {
  bool carousel = false,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'),
  );
  final logo = pw.MemoryImage(
    (await rootBundle.load(
      'assets/branding/carousel-${design['logo']}-${design['logoBackground']}.png',
    )).buffer.asUint8List(),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  PdfColor color(String key) =>
      PdfColor.fromHex(str(design[key], str(defaultExamDesign[key])));
  final groups = examGroups(items);
  final count = toInt(design['rowsPerSlide'], 6).clamp(3, 8);
  final align = design['alignment'] == 'center'
      ? pw.CrossAxisAlignment.center
      : pw.CrossAxisAlignment.start;
  final textAlign = design['alignment'] == 'center'
      ? pw.TextAlign.center
      : pw.TextAlign.left;
  pw.Widget table(List<Json> rows, double font) => pw.TableHelper.fromTextArray(
    headers: ['Date', 'Time', 'Slot', 'Subject'],
    data: rows
        .map(
          (r) => [
            fmtDate(r['exam_date']),
            '${r['session']}\n${str(r['start_time'])}–${str(r['end_time'])}',
            str(r['slot'], '—'),
            '${r['subject_name']}\n${str(r['subject_code'])}${r['status'] == 'scheduled' ? '' : '\n${pretty(r['status'])}'}',
          ],
        )
        .toList(),
    columnWidths: {
      0: const pw.FlexColumnWidth(1.7),
      1: const pw.FlexColumnWidth(1.6),
      2: const pw.FlexColumnWidth(.7),
      3: const pw.FlexColumnWidth(4.5),
    },
    headerStyle: pw.TextStyle(
      fontSize: font,
      fontWeight: pw.FontWeight.bold,
      color: color('timetableTextColor'),
    ),
    cellStyle: pw.TextStyle(fontSize: font, color: color('timetableTextColor')),
    headerDecoration: pw.BoxDecoration(color: color('timetableAccent')),
    cellPadding: pw.EdgeInsets.all(carousel ? 14 : 7),
    border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
    cellAlignments: {for (var i = 0; i < 4; i++) i: pw.Alignment.centerLeft},
  );
  if (carousel) {
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(1080, 1080),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Container(
          color: color('background'),
          padding: const pw.EdgeInsets.all(64),
          child: pw.Column(
            crossAxisAlignment: align,
            children: [
              if (truthy(design['showLogo']))
                pw.Align(
                  alignment: pw.Alignment.topLeft,
                  child: pw.Image(
                    logo,
                    width: 240,
                    height: 90,
                    fit: pw.BoxFit.contain,
                  ),
                ),
              pw.SizedBox(height: 45),
              pw.Text(
                str(design['title']),
                textAlign: textAlign,
                style: pw.TextStyle(
                  fontSize:
                      80 * (toNum(design['coverTextScale']) ?? 1).toDouble(),
                  fontWeight: pw.FontWeight.bold,
                  color: color('textColor'),
                ),
              ),
              pw.SizedBox(height: 35),
              pw.Container(height: 8, color: color('accent')),
              pw.SizedBox(height: 40),
              pw.Text(
                title,
                textAlign: textAlign,
                style: pw.TextStyle(fontSize: 32, color: color('textColor')),
              ),
              pw.SizedBox(height: 28),
              pw.Text(
                items.map((r) => str(r['branch_name'])).toSet().join(' · '),
                textAlign: textAlign,
                maxLines: 5,
                style: pw.TextStyle(
                  fontSize: 36,
                  fontWeight: pw.FontWeight.bold,
                  color: color('textColor'),
                ),
              ),
              pw.Spacer(),
              pw.Text(
                items.map((r) => str(r['semester_code'])).toSet().join(' · '),
                style: pw.TextStyle(fontSize: 30, color: color('textColor')),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                str(design['footer']),
                textAlign: textAlign,
                style: pw.TextStyle(fontSize: 24, color: color('textColor')),
              ),
            ],
          ),
        ),
      ),
    );
  }
  for (final group in groups) {
    final row = group.first;
    final groupTitle =
        '${row['branch_name']} · ${row['scheme_name']} · ${row['semester_code']}';
    if (!carousel) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(groupTitle),
              pw.SizedBox(height: 14),
            ],
          ),
          footer: (context) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'KTU Assist · app.ktuassist.in · Page ${context.pageNumber}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
          build: (_) => [table(group, 9)],
        ),
      );
    } else {
      // Bound each page; no exams are silently dropped when a semester is long.
      final pageSize = truthy(design['fitSemester']) && group.length <= 8
          ? group.length
          : count;
      for (var offset = 0; offset < group.length; offset += pageSize) {
        final rows = group.skip(offset).take(pageSize).toList();
        doc.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(1080, 1080),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Container(
              color: color('timetableBackground'),
              padding: const pw.EdgeInsets.all(48),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (truthy(design['showLogo']))
                    pw.Image(
                      logo,
                      width: 180,
                      height: 70,
                      fit: pw.BoxFit.contain,
                    ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    groupTitle,
                    style: pw.TextStyle(
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold,
                      color: color('timetableTextColor'),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 20,
                      color: color('timetableTextColor'),
                    ),
                  ),
                  pw.SizedBox(height: 28),
                  pw.Expanded(
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.topCenter,
                      child: pw.SizedBox(
                        width: 984,
                        child: table(
                          rows,
                          toInt(design['tableFontSize'], 26).toDouble(),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 18),
                  pw.Text(
                    '${str(design['footer'])} · ${offset ~/ pageSize + 1}/${(group.length / pageSize).ceil()}',
                    style: pw.TextStyle(
                      fontSize: 20,
                      color: color('timetableTextColor'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
  }
  return doc.save();
}

class ExamExportsPage extends StatefulWidget {
  const ExamExportsPage({super.key, required this.calendarId});
  final dynamic calendarId;
  @override
  State<ExamExportsPage> createState() => _ExamExportsPageState();
}

class _ExamExportsPageState extends State<ExamExportsPage> {
  List<Json> items = [], templates = [];
  Json design = {...defaultExamDesign};
  String title = 'Exam timetable';
  dynamic branch;
  String? selectedTemplate, error;
  bool loading = true, busy = false;
  Uint8List? preview;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final calendar = asMap(
        unwrap(await api.get('admin/exam-calendars/${widget.calendarId}')),
      );
      final library = asMap(await api.get('admin/exam-carousel-templates'));
      final all = <Json>[];
      var page = 1, last = 1;
      do {
        final r = await api.get(
          'admin/exam-calendars/${widget.calendarId}/items',
          query: {'page': page, 'per_page': 100},
        );
        all.addAll(rowsOf(r));
        last = PageMeta.of(r).lastPage;
        page++;
      } while (page <= last);
      if (!mounted) return;
      setState(() {
        items = all;
        title = str(calendar['title'], title);
        templates = rowsOf(library['templates']);
        final template = templates
            .where((t) => t['id'] == library['defaultId'])
            .firstOrNull;
        if (template != null) {
          design = {...defaultExamDesign, ...asMap(template['design'])};
          selectedTemplate = str(template['id']);
        }
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = errorText(e);
        });
      }
    }
  }

  List<Json> get filtered => items
      .where((r) => branch == null || '${r['branch_id']}' == '$branch')
      .toList();
  Future<void> _design() async {
    final result = await showFormSheet(
      context,
      title: 'Carousel design',
      initial: design,
      fields: [
        const FieldSpec('title', 'Cover title', required: true, maxLength: 80),
        const FieldSpec('footer', 'Footer', maxLength: 160),
        for (final key in [
          'background',
          'textColor',
          'accent',
          'timetableBackground',
          'timetableTextColor',
          'timetableAccent',
        ])
          FieldSpec(
            key,
            pretty(key.replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]}')),
            required: true,
            validator: (v, _) => RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(str(v))
                ? null
                : 'Use a six-digit hex color, e.g. #ffffff',
          ),
        const FieldSpec(
          'coverTextScale',
          'Cover text scale',
          type: FieldType.decimal,
          min: .75,
          max: 1.15,
          required: true,
        ),
        const FieldSpec(
          'tableFontSize',
          'Table font size',
          type: FieldType.select,
          options: [Opt(22, 'Small'), Opt(26, 'Medium'), Opt(30, 'Large')],
          required: true,
        ),
        const FieldSpec(
          'rowsPerSlide',
          'Exams per slide',
          type: FieldType.number,
          min: 3,
          max: 8,
          required: true,
        ),
        const FieldSpec(
          'alignment',
          'Cover alignment',
          type: FieldType.select,
          options: [Opt('left', 'Left'), Opt('center', 'Center')],
          required: true,
        ),
        const FieldSpec('showLogo', 'Show logo', type: FieldType.toggle),
        const FieldSpec(
          'logo',
          'Logo',
          type: FieldType.select,
          options: [Opt('ktu', 'KTU Assist'), Opt('dude', 'KTU Dude')],
          required: true,
        ),
        const FieldSpec(
          'logoBackground',
          'Logo background',
          type: FieldType.select,
          options: [Opt('white', 'White'), Opt('transparent', 'Transparent')],
          required: true,
        ),
        const FieldSpec(
          'fitSemester',
          'Keep semesters together',
          type: FieldType.toggle,
          helper:
              'Long semesters continue onto another slide; no exams are omitted.',
        ),
      ],
      onSubmit: (_) async {},
    );
    if (result != null && mounted) {
      setState(() {
        design = {
          ...defaultExamDesign,
          ...result,
          'footer': result['footer'] ?? '',
        };
        preview = null;
      });
    }
  }

  Future<void> _saveTemplate() async {
    final result = await showFormSheet(
      context,
      title: 'Save carousel template',
      fields: const [
        FieldSpec('name', 'Template name', required: true, maxLength: 60),
        FieldSpec('is_default', 'Use by default', type: FieldType.toggle),
        FieldSpec(
          'replace',
          'Update selected template',
          type: FieldType.toggle,
        ),
      ],
      onSubmit: (v) async {
        final body = {
          'name': v['name'],
          'is_default': v['is_default'],
          'design': design,
        };
        final r = asMap(
          truthy(v['replace']) && selectedTemplate != null
              ? await api.put(
                  'admin/exam-carousel-templates/$selectedTemplate',
                  body,
                )
              : await api.post('admin/exam-carousel-templates', body),
        );
        if (mounted) {
          setState(() {
            templates = rowsOf(r['templates']);
            selectedTemplate = str(r['savedId']);
          });
        }
      },
    );
    if (result != null && mounted) toast(context, 'Template saved');
  }

  Future<void> _export(String kind) async {
    if (filtered.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      final pdf = await buildExamPdf(
        filtered,
        title,
        design,
        carousel: kind != 'pdf',
      );
      if (!mounted) return;
      if (kind == 'preview') {
        setState(() => preview = pdf);
      } else if (kind == 'pdf') {
        await shareBytes(
          context,
          pdf,
          'exam-${widget.calendarId}.pdf',
          'application/pdf',
        );
      } else {
        await pdfrxFlutterInitialize();
        final doc = await PdfDocument.openData(pdf);
        final files = <XFile>[];
        try {
          for (final page in doc.pages) {
            final rendered = await page.render(
              width: 1080,
              height: 1080,
              fullWidth: 1080,
              fullHeight: 1080,
            );
            if (rendered == null) {
              throw const FormatException('Could not render a slide.');
            }
            final image = await rendered.createImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            rendered.dispose();
            if (bytes == null) {
              throw const FormatException('Could not encode slide.');
            }
            files.add(
              XFile.fromData(
                bytes.buffer.asUint8List(),
                name: 'exam-slide-${page.pageNumber}.png',
                mimeType: 'image/png',
              ),
            );
          }
        } finally {
          await doc.dispose();
        }
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: files,
            fileNameOverrides: [
              for (var i = 0; i < files.length; i++) 'exam-slide-${i + 1}.png',
            ],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Share timetable',
    subtitle: 'PDF handouts and branded carousel slides',
    loading: loading,
    error: error,
    onRetry: _load,
    children: [
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text(
                    branch == null
                        ? 'All branches'
                        : str(filtered.firstOrNull?['branch_name']),
                  ),
                  onPressed: () async {
                    final branches = <String, Json>{
                      for (final r in items) str(r['branch_id']): r,
                    };
                    final p = await pickFromOptions(context, 'Branch', [
                      const Opt(null, 'All branches'),
                      for (final r in branches.values)
                        Opt(r['branch_id'], str(r['branch_name'])),
                    ]);
                    if (p != null && mounted) {
                      setState(() {
                        branch = p.first;
                        preview = null;
                      });
                    }
                  },
                ),
                ActionChip(
                  label: const Text('Choose template'),
                  onPressed: templates.isEmpty
                      ? null
                      : () async {
                          final p = await pickFromOptions(
                            context,
                            'Template',
                            optsOf(templates),
                          );
                          if (p != null && mounted) {
                            final t = templates.firstWhere(
                              (t) => t['id'] == p.first,
                            );
                            setState(() {
                              selectedTemplate = str(t['id']);
                              design = {
                                ...defaultExamDesign,
                                ...asMap(t['design']),
                              };
                              preview = null;
                            });
                          }
                        },
                ),
              ],
            ),
            Text(
              '${filtered.length} exams · ${examGroups(filtered).length} semester groups',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _design,
                  child: const Text('Customize design'),
                ),
                TextButton(
                  onPressed: _saveTemplate,
                  child: const Text('Save template'),
                ),
                if (selectedTemplate != null)
                  TextButton(
                    onPressed: () async {
                      if (!await confirmDialog(
                            context,
                            title: 'Delete selected template?',
                            destructive: true,
                          ) ||
                          !context.mounted) {
                        return;
                      }
                      if (await runAction(
                        context,
                        () => api.delete(
                          'admin/exam-carousel-templates/$selectedTemplate',
                        ),
                        success: 'Template deleted',
                      )) {
                        setState(() => selectedTemplate = null);
                        _load();
                      }
                    },
                    child: const Text('Delete template'),
                  ),
              ],
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: busy || filtered.isEmpty ? null : () => _export('pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export PDF'),
          ),
          OutlinedButton(
            onPressed: busy || filtered.isEmpty
                ? null
                : () => _export('preview'),
            child: const Text('Preview carousel'),
          ),
          OutlinedButton(
            onPressed: busy || filtered.isEmpty ? null : () => _export('png'),
            child: const Text('Share PNG slides'),
          ),
        ],
      ),
      if (busy)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (preview != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: SizedBox(
            height: 550,
            child: PdfViewer.data(preview!, sourceName: 'exam-preview.pdf'),
          ),
        ),
    ],
  );
}
