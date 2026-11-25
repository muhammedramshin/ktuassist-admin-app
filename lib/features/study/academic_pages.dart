import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../widgets/crud_page.dart';
import '../../widgets/forms.dart';
import '../../widgets/dialogs.dart';
import 'branch_detail_page.dart';
import 'subject_detail_page.dart';

String _yesNo(Json r) => truthy(r['is_active']) ? 'yes' : 'no';
dynamic _ref(Json r, String key) =>
    r['${key}_id'] ?? (r[key] is Map ? r[key]['id'] : r[key]);

class UniversitiesPage extends StatelessWidget {
  const UniversitiesPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Universities',
      singular: 'university',
      icon: Icons.account_balance_outlined,
      lookupKey: 'universities',
      load: () async => rowsOf(await api.get('getuniversities')),
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => [
        str(r['code']),
        str(r['website']),
      ].where((e) => e.isNotEmpty).join(' · '),
      activeFilter: true,
      csvHeader: const ['Name', 'Code', 'Status'],
      csvRow: (r) => [
        r['name'],
        r['code'],
        truthy(r['is_active']) ? 'Active' : 'Inactive',
      ],
      formIntro:
          'The API only supports creating universities. Existing ones cannot be edited from the admin yet.',
      fields: (_) => const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec('code', 'Code'),
        FieldSpec('description', 'Description', type: FieldType.multiline),
        FieldSpec('banner', 'Banner', type: FieldType.upload),
        FieldSpec('image', 'Image', type: FieldType.upload),
        FieldSpec('address', 'Address'),
        FieldSpec('contact', 'Contact', type: FieldType.phone),
        FieldSpec('website', 'Website', type: FieldType.url),
        FieldSpec('is_active', 'Active', type: FieldType.toggle),
      ],
      create: (v) => api.post('create_universities', v),
    ),
  );
}

class SchemesPage extends StatelessWidget {
  const SchemesPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Schemes',
      singular: 'scheme',
      icon: Icons.schedule_outlined,
      lookupKey: 'schemes',
      load: () async => rowsOf(await api.get('getschemes')),
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => [
        str(r['code']),
        str(r['university_name']),
      ].where((e) => e.isNotEmpty).join(' · '),
      searchKeys: const ['name', 'code', 'university_name'],
      activeFilter: true,
      filters: [CrudFilter('University', (r) => str(r['university_name']))],
      csvHeader: const ['Name', 'Code', 'University', 'Status'],
      csvRow: (r) => [
        r['name'],
        r['code'],
        r['university_name'],
        truthy(r['is_active']) ? 'Active' : 'Inactive',
      ],
      fields: (_) => const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec('code', 'Code'),
        FieldSpec(
          'university',
          'University',
          type: FieldType.select,
          loadOptions: Lookups.universityOpts,
        ),
        FieldSpec('is_active', 'Active', type: FieldType.toggle),
      ],
      initialOf: (r) => {...r, 'university': _ref(r, 'university')},
      create: (v) => api.post('create_scheme', v),
      update: (r, v) => api.post('update_scheme', {...v, 'id': r['id']}),
    ),
  );
}

class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Courses',
      singular: 'course',
      icon: Icons.menu_book_outlined,
      lookupKey: 'courses',
      load: () async => rowsOf(await api.get('getcourses')),
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => [
        str(r['code']),
        str(r['university_name']),
      ].where((e) => e.isNotEmpty).join(' · '),
      searchKeys: const ['name', 'code', 'university_name'],
      activeFilter: true,
      csvHeader: const ['Name', 'Code', 'University', 'Status'],
      csvRow: (r) => [
        r['name'],
        r['code'],
        r['university_name'],
        truthy(r['is_active']) ? 'Active' : 'Inactive',
      ],
      fields: (_) => const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec('code', 'Code'),
        FieldSpec(
          'university',
          'University',
          type: FieldType.select,
          loadOptions: Lookups.universityOpts,
        ),
        FieldSpec('is_active', 'Active', type: FieldType.toggle),
      ],
      initialOf: (r) => {...r, 'university': _ref(r, 'university')},
      create: (v) => api.post('create_course', v),
      update: (r, v) => api.post('update_course', {...v, 'id': r['id']}),
    ),
  );
}

class BranchesPage extends StatelessWidget {
  const BranchesPage({super.key});
  @override
  Widget build(BuildContext context) {
    List<Json> courses = [];
    return CrudPage(
      CrudConfig(
        title: 'Branches',
        onOpen: (context, r) async {
          await push(context, BranchDetailPage(id: r['id']));
        },
        singular: 'branch',
        icon: Icons.account_tree_outlined,
        lookupKey: 'branches',
        load: () async => rowsOf(await api.get('getbranches')),
        titleOf: (r) => str(r['name'], '#${r['id']}'),
        subtitleOf: (r) => [
          str(r['code']),
          pick(r, ['course_name', 'course.name']),
        ].where((e) => e.isNotEmpty).join(' · '),
        searchKeys: const ['name', 'code', 'id'],
        activeFilter: true,
        csvHeader: const ['Name', 'Code', 'Course ID', 'Active'],
        csvRow: (r) => [r['name'], r['code'], _ref(r, 'course'), _yesNo(r)],
        fields: (_) => const [
          FieldSpec('name', 'Name', required: true),
          FieldSpec('code', 'Code'),
          FieldSpec(
            'course',
            'Course',
            type: FieldType.select,
            loadOptions: Lookups.courseOpts,
          ),
          FieldSpec('is_active', 'Active', type: FieldType.toggle),
        ],
        initialOf: (r) => {...r, 'course': _ref(r, 'course')},
        create: (v) => api.post('create_branch', v),
        update: (r, v) => api.post('update_branch', {...v, 'id': r['id']}),

        importer: ImportSpec(
          prepare: () async => courses = rowsOf(await api.get('getcourses')),
          aliases: const {
            'name': ['name', 'branch name', 'branch'],
            'code': ['code', 'branch code'],
            'course': ['course', 'course id', 'course_id', 'courseid'],
            'is_active': ['active', 'is active', 'is_active', 'status'],
          },
          templateHeader: const ['Name', 'Code', 'Course ID', 'Active'],
          templateExample: const ['Example Branch', 'EX', '1', 'yes'],
          build: (row) async {
            final course = matchRef(courses, row['course']);
            if ((row['name'] ?? '').isEmpty || course == null) return null;
            return {
              'name': row['name'],
              'code': row['code'] ?? '',
              'course': course,
              'is_active': parseActive(row['is_active']),
            };
          },
        ),
      ),
    );
  }
}

class SemestersPage extends StatelessWidget {
  const SemestersPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Semesters',
      singular: 'semester',
      icon: Icons.calendar_today_outlined,
      lookupKey: 'semesters',
      load: () async => rowsOf(await api.get('getsemesters')),
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => [
        str(r['code']),
        if (r['year'] != null) 'Year ${r['year']}',
      ].where((e) => e.isNotEmpty).join(' · '),
      searchKeys: const ['name', 'code', 'year'],
      activeFilter: true,
      csvHeader: const ['Name', 'Code', 'Year', 'Status'],
      csvRow: (r) => [
        r['name'],
        r['code'],
        r['year'],
        truthy(r['is_active']) ? 'Active' : 'Inactive',
      ],
      fields: (_) => const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec('code', 'Code'),
        FieldSpec('year', 'Year', type: FieldType.number),
        FieldSpec('is_active', 'Active', type: FieldType.toggle),
      ],
      create: (v) => api.post('create_semester', v),
      update: (r, v) => api.post('update_semester', {...v, 'id': r['id']}),
    ),
  );
}

class MaterialTypesPage extends StatelessWidget {
  const MaterialTypesPage({super.key});
  @override
  Widget build(BuildContext context) => CrudPage(
    CrudConfig(
      title: 'Material types',
      singular: 'material type',
      icon: Icons.category_outlined,
      lookupKey: 'material_types',
      load: () async => rowsOf(await api.get('getmeterial_types')),
      titleOf: (r) => str(r['name'], '#${r['id']}'),
      subtitleOf: (r) => str(r['code']),
      activeFilter: true,
      csvHeader: const ['Name', 'Code', 'Status'],
      csvRow: (r) => [
        r['name'],
        r['code'],
        truthy(r['is_active']) ? 'Active' : 'Inactive',
      ],
      fields: (_) => const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec('code', 'Code'),
        FieldSpec('is_active', 'Active', type: FieldType.toggle),
      ],
      create: (v) => api.post('create_meterial_type', v),
      update: (r, v) => api.post('update_meterial_type', {...v, 'id': r['id']}),
    ),
  );
}

String? _bannerImageUrl(dynamic value, Json _) {
  if (value is String && value.length > 2048) {
    return 'Must be 2048 characters or fewer';
  }
  return null;
}

/// Gallery updates are append-only. [images] is included only when new URLs
/// were added, and then only those new URLs.
Json collegeFormBody(Json values) {
  final body = Map<String, dynamic>.from(values);
  final banner = body['banner_image'];
  if (banner is String && banner.trim().isEmpty) body['banner_image'] = null;
  final images = body['images'];
  if (images is List) {
    final urls = [
      for (final url in images)
        if ('$url'.trim().isNotEmpty) '$url'.trim(),
    ];
    if (urls.isEmpty) {
      body.remove('images');
    } else {
      body['images'] = urls;
    }
  } else {
    body.remove('images');
  }
  return body;
}

class CollegesPage extends StatelessWidget {
  const CollegesPage({super.key});

  static const formFields = <FieldSpec>[
    FieldSpec('college_name', 'College name', required: true),
    FieldSpec('code', 'Code'),
    FieldSpec(
      'university',
      'University',
      type: FieldType.select,
      loadOptions: Lookups.universityOpts,
    ),
    FieldSpec('district', 'District'),
    FieldSpec('description', 'Description', type: FieldType.multiline),
    FieldSpec(
      'banner_image',
      'Banner image',
      type: FieldType.upload,
      imagesOnly: true,
      uploadTarget: UploadTarget.link,
      folder: 'colleges',
      validator: _bannerImageUrl,
    ),
    FieldSpec(
      'images',
      'College images',
      type: FieldType.gallery,
      folder: 'colleges',
      helper:
          'Saved images stay on the college. New images are added when you save.',
    ),
    FieldSpec('address', 'Address'),
    FieldSpec('website', 'Website', type: FieldType.url),
    FieldSpec('contact', 'Contact', type: FieldType.phone),
  ];

  static Json initialValues(Json row) => {
    ...row,
    'university': _ref(row, 'university'),
    'banner_image': row['banner_image'],
    'images': row['images'] is List
        ? List.of(row['images'] as List)
        : row['images'],
  };

  @override
  Widget build(BuildContext context) {
    List<Json> universities = [];
    return CrudPage(
      CrudConfig(
        title: 'Colleges',
        singular: 'college',
        icon: Icons.business_outlined,
        lookupKey: 'colleges',
        load: () async => rowsOf(await api.get('colleges'), ['colleges']),
        titleOf: (r) => collegeName(r, '#${r['id']}'),
        subtitleOf: (r) => [
          str(r['code']),
          pick(r, ['university.name', 'university_name']),
          str(r['district']),
        ].where((e) => e.isNotEmpty).join(' · '),
        metaOf: (r) => str(r['website']),
        searchKeys: const [
          'college_name',
          'code',
          'university.name',
          'district',
          'description',
          'address',
          'website',
          'contact',
        ],
        filters: [
          CrudFilter('District', (r) => str(r['district'])),
          CrudFilter(
            'University',
            (r) => pick(r, ['university.name', 'university_name']),
          ),
        ],
        csvHeader: const [
          'College Name',
          'Code',
          'University ID',
          'District',
          'Description',
          'Address',
          'Website',
          'Contact',
          'Active',
        ],
        csvRow: (r) => [
          r['college_name'],
          r['code'],
          _ref(r, 'university'),
          r['district'],
          r['description'],
          r['address'],
          r['website'],
          r['contact'],
          _yesNo(r),
        ],
        fields: (_) => formFields,
        initialOf: initialValues,
        create: (v) => api.post('colleges', collegeFormBody(v)),
        update: (r, v) => api.put('colleges/${r['id']}', collegeFormBody(v)),
        delete: (r) => api.delete('colleges/${r['id']}'),
        importer: ImportSpec(
          prepare: () async => universities = rowsOf(
            await api.get('getuniversities'),
            ['universities'],
          ),
          aliases: const {
            'college_name': ['college name', 'college_name', 'name', 'college'],
            'code': ['code', 'college code'],
            'university': [
              'university',
              'university id',
              'university_id',
              'universityid',
              'uni',
              'uni id',
            ],
            'district': ['district'],
            'description': ['description', 'desc', 'about', 'details', 'info'],
            'address': ['address'],
            'website': ['website', 'url', 'web'],
            'contact': ['contact', 'phone', 'tel', 'mobile'],
            'is_active': ['active', 'is active', 'is_active', 'status'],
          },
          templateHeader: const [
            'College Name',
            'Code',
            'University ID',
            'District',
            'Description',
            'Address',
            'Website',
            'Contact',
            'Active',
          ],
          templateExample: const [
            'Example College',
            'EX',
            '1',
            'Ernakulam',
            'Engineering college example',
            '123 Street',
            'https://example.edu',
            '+91 0000000000',
            'yes',
          ],
          build: (row) async {
            final uni = matchRef(universities, row['university']);
            if ((row['college_name'] ?? '').isEmpty || uni == null) return null;
            return {
              for (final k in [
                'college_name',
                'code',
                'district',
                'description',
                'address',
                'website',
                'contact',
              ])
                k: row[k] ?? '',
              'university': uni,
              'is_active': parseActive(row['is_active']),
            };
          },
        ),
      ),
    );
  }
}

class SubjectsPage extends StatelessWidget {
  const SubjectsPage({super.key});

  static String schemeOf(Json r) => pick(r, [
    'coursescheme_name',
    'scheme_name',
    'coursescheme.name',
    'scheme.name',
  ]);

  static List<FieldSpec> fields() => const [
    FieldSpec('name', 'Name', required: true, maxLength: 255),
    FieldSpec('code', 'Code', required: true, maxLength: 255),
    FieldSpec('description', 'Description', type: FieldType.multiline),
    FieldSpec(
      'university',
      'University',
      type: FieldType.select,
      required: true,
      loadOptions: Lookups.universityOpts,
      section: 'Placement',
    ),
    FieldSpec(
      'coursescheme',
      'Course scheme',
      type: FieldType.select,
      required: true,
      loadOptions: Lookups.schemeOpts,
      section: 'Placement',
    ),
    FieldSpec(
      'course',
      'Course',
      type: FieldType.select,
      required: true,
      loadOptions: Lookups.courseOpts,
      section: 'Placement',
    ),
    FieldSpec(
      'branch',
      'Branch',
      type: FieldType.select,
      required: true,
      loadOptions: Lookups.branchOpts,
      section: 'Placement',
    ),
    FieldSpec(
      'semester',
      'Semester',
      type: FieldType.select,
      required: true,
      loadOptions: Lookups.semesterOpts,
      section: 'Placement',
    ),
    FieldSpec('credit', 'Credit', type: FieldType.number, section: 'Details'),
    FieldSpec('slot', 'Slot', maxLength: 255, section: 'Details'),
    FieldSpec('year', 'Year', type: FieldType.number, section: 'Details'),
    FieldSpec(
      'is_active',
      'Active',
      type: FieldType.toggle,
      section: 'Details',
    ),
  ];

  static Json payload(Json v) => {
    ...v,
    'is_active': v['is_active'] == true,
    'is_delete': false,
  };

  @override
  Widget build(BuildContext context) {
    late List<Json> unis, schemes, courses, branches, semesters;
    return CrudPage(
      CrudConfig(
        title: 'Subjects',
        singular: 'subject',
        icon: Icons.book_outlined,
        lookupKey: 'subjects',
        load: () async => rowsOf(await api.get('getsubjects')),
        titleOf: (r) => str(r['name'], '#${r['id']}'),
        subtitleOf: (r) => [
          str(r['code']),
          str(r['branch_name']),
          str(r['semester_name']),
        ].where((e) => e.isNotEmpty).join(' · '),
        metaOf: (r) => [
          str(r['university_name']),
          schemeOf(r),
          str(r['course_name']),
          if (r['credit'] != null) '${r['credit']} credits',
        ].where((e) => e.isNotEmpty).join(' · '),
        onOpen: (context, r) async {
          await push(context, SubjectDetailPage(id: r['id'], initial: r));
        },
        searchKeys: const [
          'name',
          'code',
          'description',
          'university_name',
          'course_name',
          'branch_name',
          'semester_name',
          'credit',
          'slot',
          'year',
        ],
        activeFilter: true,
        filters: [
          CrudFilter('University', (r) => str(r['university_name'])),
          CrudFilter('Scheme', schemeOf),
          CrudFilter('Course', (r) => str(r['course_name'])),
          CrudFilter('Branch', (r) => str(r['branch_name'])),
          CrudFilter('Semester', (r) => str(r['semester_name'])),
          CrudFilter('Credit', (r) => str(r['credit'])),
        ],
        csvHeader: const [
          'Name',
          'Code',
          'Description',
          'University',
          'Course Scheme',
          'Course',
          'Branch',
          'Semester',
          'Credit',
          'Slot',
          'Year',
          'Status',
        ],
        csvRow: (r) => [
          r['name'],
          r['code'],
          r['description'],
          r['university_name'],
          schemeOf(r),
          r['course_name'],
          r['branch_name'],
          r['semester_name'],
          r['credit'],
          r['slot'],
          r['year'],
          truthy(r['is_active']) ? 'Active' : 'Inactive',
        ],
        fields: (_) => fields(),
        initialOf: (r) => {
          ...r,
          'university': _ref(r, 'university'),
          'coursescheme':
              r['coursescheme_id'] ?? r['scheme_id'] ?? _ref(r, 'coursescheme'),
          'course': _ref(r, 'course'),
          'branch': _ref(r, 'branch'),
          'semester': _ref(r, 'semester'),
        },
        create: (v) => api.post('create_subject', payload(v)),
        update: (r, v) =>
            api.post('update_subject', {...payload(v), 'id': r['id']}),
        importer: ImportSpec(
          prepare: () async {
            final all = await Future.wait([
              Lookups.universities(),
              Lookups.schemes(),
              Lookups.courses(),
              Lookups.branches(),
              Lookups.semesters(),
            ]);
            unis = all[0];
            schemes = all[1];
            courses = all[2];
            branches = all[3];
            semesters = all[4];
          },
          aliases: const {
            'name': ['name', 'subject name', 'subject'],
            'code': ['code', 'subject code'],
            'description': ['description', 'desc', 'about', 'details', 'info'],
            'university': [
              'university',
              'university name',
              'university_id',
              'university id',
            ],
            'coursescheme': [
              'course scheme',
              'coursescheme',
              'scheme',
              'scheme name',
            ],
            'course': ['course'],
            'branch': ['branch'],
            'semester': ['semester'],
            'credit': ['credit', 'credits'],
            'slot': ['slot'],
            'year': ['year'],
            'status': [
              'status',
              'active',
              'is active',
              'is_active',
              'isactive',
            ],
          },
          templateHeader: const [
            'Name',
            'Code',
            'Description',
            'University',
            'Course Scheme',
            'Course',
            'Branch',
            'Semester',
            'Credit',
            'Slot',
            'Year',
            'Status',
          ],
          templateExample: const [
            'Example Subject',
            'EX',
            'Example description',
            'Example University',
            'Example Course Scheme',
            'Example Course',
            'Example Branch',
            'Example Semester',
            '3',
            'Example Slot',
            '2026',
            'Active',
          ],
          build: (row) async {
            final refs = [
              matchRef(unis, row['university']),
              matchRef(schemes, row['coursescheme']),
              matchRef(courses, row['course']),
              matchRef(branches, row['branch']),
              matchRef(semesters, row['semester']),
            ];
            if ((row['name'] ?? '').isEmpty ||
                (row['code'] ?? '').isEmpty ||
                refs.contains(null)) {
              return null;
            }
            return {
              'name': row['name'],
              'code': row['code'],
              'description': row['description'] ?? '',
              'university': refs[0],
              'coursescheme': refs[1],
              'course': refs[2],
              'branch': refs[3],
              'semester': refs[4],
              'credit': toNum(row['credit']),
              'slot': row['slot'] ?? '',
              'year': toNum(row['year']),
              'is_active': parseActive(row['status']),
              'is_delete': false,
            };
          },
        ),
      ),
    );
  }
}
