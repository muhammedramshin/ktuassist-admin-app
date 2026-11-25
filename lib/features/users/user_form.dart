import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/lookups.dart';
import '../../widgets/forms.dart';

const userRoles = [
  'user',
  'admin',
  'student',
  'faculty',
  'business',
  'professional',
];
const userStatuses = ['active', 'inactive', 'banned', 'pending'];
const _business = [
  'business_name',
  'type',
  'description',
  'location',
  'contact',
  'website',
];
const _academic = [
  'college_id',
  'branch_id',
  'semester_id',
  'university_id',
  'scheme_id',
  'course_id',
];
const _optional = [
  'mobile',
  'username',
  'avatar_url',
  'address',
  'city',
  'country',
  'dob',
  'business_name',
  'type',
  'description',
  'location',
  'contact',
  'website',
  'domain',
  'bio',
];

bool Function(Json) _roleIn(List<String> roles) =>
    (v) => roles.contains(v['role']);

/// Create (user == null) or edit a user. Returns true when saved.
Future<bool> showUserForm(BuildContext context, {Json? user}) async {
  final editing = user != null;
  final id = user?['id'] ?? user?['user_id'];
  final initial = <String, dynamic>{};
  if (user != null) {
    for (final k in [
      'name',
      'email',
      'mobile',
      'role',
      'username',
      'avatar_url',
      'address',
      'city',
      'country',
      'dob',
      'is_verified',
      'status',
    ]) {
      initial[k] = user[k];
    }
    void merge(String profile, List<String> keys) {
      final p = asMap(user[profile]);
      for (final k in keys) {
        if (p[k] != null) initial[k] = p[k];
      }
    }

    merge('student_profile', [
      ..._academic,
      'academic_status',
      'admission_year',
    ]);
    merge('faculty_profile', [
      'college_id',
      'branch_id',
      'university_id',
      'course_id',
    ]);
    merge('business_profile', _business);
    merge('professional_profile', [
      'domain',
      'location',
      'bio',
      'college_id',
      'branch_id',
      'course_id',
      'university_id',
      'scheme_id',
    ]);
  }
  final maxYear = DateTime.now().year + 1;
  final academicRoles = _roleIn(['student', 'faculty', 'professional']);

  final result = await showFormSheet(
    context,
    title: editing ? 'Edit user' : 'New user',
    submitLabel: editing ? 'Save changes' : 'Create user',
    initial: {'role': 'user', 'status': 'pending', ...initial},
    fields: [
      const FieldSpec(
        'name',
        'Full name',
        required: true,
        maxLength: 255,
        section: 'Basic information',
      ),
      const FieldSpec(
        'email',
        'Email address',
        type: FieldType.email,
        required: true,
        maxLength: 255,
        section: 'Basic information',
      ),
      const FieldSpec(
        'mobile',
        'Mobile number',
        type: FieldType.phone,
        maxLength: 20,
        section: 'Basic information',
      ),
      if (!editing)
        FieldSpec(
          'password',
          'Password',
          type: FieldType.password,
          required: true,
          section: 'Basic information',
          validator: (v, _) =>
              str(v).length < 8 ? 'At least 8 characters' : null,
        ),
      FieldSpec(
        'role',
        'Role',
        type: FieldType.select,
        required: true,
        allowEmptyOption: false,
        section: 'Role & status',
        loadOptions: () async => optsOf(
          rowsOf(await api.get('admin/account-roles')),
          valueKey: 'code',
        ),
      ),
      FieldSpec(
        'status',
        'Account status',
        type: FieldType.select,
        allowEmptyOption: false,
        section: 'Role & status',
        options: userStatuses.map((r) => Opt(r, pretty(r))).toList(),
      ),
      const FieldSpec(
        'is_verified',
        'Mark as verified',
        type: FieldType.toggle,
        section: 'Role & status',
      ),
      const FieldSpec(
        'username',
        'Username',
        maxLength: 255,
        section: 'Profile',
      ),
      const FieldSpec(
        'avatar_url',
        'Avatar',
        type: FieldType.upload,
        section: 'Profile',
      ),
      FieldSpec(
        'dob',
        'Date of birth',
        type: FieldType.date,
        section: 'Profile',
        validator: (v, _) =>
            v != null && (parseDate(v)?.isAfter(DateTime.now()) ?? false)
            ? 'Must be in the past'
            : null,
      ),
      const FieldSpec('address', 'Address', section: 'Profile'),
      const FieldSpec('city', 'City', maxLength: 100, section: 'Profile'),
      const FieldSpec('country', 'Country', maxLength: 100, section: 'Profile'),
      FieldSpec(
        'college_id',
        'College',
        type: FieldType.select,
        loadOptions: Lookups.collegeOpts,
        visibleWhen: academicRoles,
        section: 'Academic',
      ),
      FieldSpec(
        'university_id',
        'University',
        type: FieldType.select,
        loadOptions: Lookups.universityOpts,
        visibleWhen: academicRoles,
        section: 'Academic',
      ),
      FieldSpec(
        'scheme_id',
        'Scheme',
        type: FieldType.select,
        loadOptions: Lookups.schemeOpts,
        visibleWhen: _roleIn(['student', 'professional']),
        section: 'Academic',
      ),
      FieldSpec(
        'course_id',
        'Course',
        type: FieldType.select,
        loadOptions: Lookups.courseOpts,
        visibleWhen: academicRoles,
        section: 'Academic',
      ),
      FieldSpec(
        'branch_id',
        'Branch',
        type: FieldType.select,
        loadOptions: Lookups.branchOpts,
        visibleWhen: academicRoles,
        section: 'Academic',
      ),
      FieldSpec(
        'semester_id',
        'Semester',
        type: FieldType.select,
        loadOptions: Lookups.semesterOpts,
        visibleWhen: _roleIn(['student']),
        section: 'Academic',
      ),
      FieldSpec(
        'academic_status',
        'Academic status',
        type: FieldType.select,
        visibleWhen: _roleIn(['student']),
        section: 'Academic',
        options: const [
          Opt('studying', 'Studying'),
          Opt('completed', 'Completed the course'),
          Opt('discontinued', 'Left the course'),
        ],
      ),
      FieldSpec(
        'admission_year',
        'Admission year',
        type: FieldType.number,
        min: 1990,
        max: maxYear,
        visibleWhen: _roleIn(['student']),
        section: 'Academic',
      ),
      FieldSpec(
        'business_name',
        'Business name',
        maxLength: 255,
        visibleWhen: _roleIn(['business']),
        section: 'Business',
      ),
      FieldSpec(
        'type',
        'Business type',
        hint: 'e.g. Coaching center',
        maxLength: 255,
        visibleWhen: _roleIn(['business']),
        section: 'Business',
      ),
      FieldSpec(
        'location',
        'Location',
        maxLength: 255,
        visibleWhen: _roleIn(['business', 'professional']),
        section: 'Business / professional',
      ),
      FieldSpec(
        'contact',
        'Contact',
        maxLength: 255,
        visibleWhen: _roleIn(['business']),
        section: 'Business',
      ),
      FieldSpec(
        'website',
        'Website',
        type: FieldType.url,
        maxLength: 500,
        visibleWhen: _roleIn(['business']),
        section: 'Business',
      ),
      FieldSpec(
        'description',
        'Description',
        type: FieldType.multiline,
        visibleWhen: _roleIn(['business']),
        section: 'Business',
      ),
      FieldSpec(
        'domain',
        'Domain',
        maxLength: 255,
        visibleWhen: _roleIn(['professional']),
        section: 'Professional',
      ),
      FieldSpec(
        'bio',
        'Bio',
        type: FieldType.multiline,
        visibleWhen: _roleIn(['professional']),
        section: 'Professional',
      ),
    ],
    onSubmit: (v) async {
      final body = Map<String, dynamic>.from(v);
      final role = str(body['role'], 'user');
      if (!userStatuses.contains(body['status'])) body['status'] = 'pending';
      body['is_verified'] = body['is_verified'] == true;
      void drop(Iterable<String> keys) => keys.forEach(body.remove);
      switch (role) {
        case 'student':
          drop([..._business, 'domain', 'bio']);
        case 'faculty':
          drop([
            'semester_id',
            'scheme_id',
            ..._business,
            'domain',
            'bio',
            'academic_status',
            'admission_year',
          ]);
        case 'business':
          drop([
            ..._academic,
            'domain',
            'bio',
            'academic_status',
            'admission_year',
          ]);
        case 'professional':
          drop([
            'semester_id',
            ..._business.where((k) => k != 'location'),
            'academic_status',
            'admission_year',
          ]);
        default:
          drop([
            ..._academic,
            ..._business,
            'domain',
            'bio',
            'academic_status',
            'admission_year',
          ]);
      }
      if (body['admission_year'] == null) body.remove('admission_year');
      if (body['academic_status'] == null) body.remove('academic_status');
      for (final k in _optional) {
        if (body[k] == null || body[k] == '') body.remove(k);
      }
      if (editing) {
        await api.put('users/$id', body);
      } else {
        await api.post('create_user', body);
      }
    },
  );
  if (result != null) Lookups.invalidate('users');
  return result != null;
}
