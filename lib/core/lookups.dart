import '../widgets/forms.dart';
import 'api.dart';
import 'json.dart';

/// Session-cached reference lists used by dropdowns and filters.
class Lookups {
  static final _cache = <String, Future<List<Json>>>{};

  static Future<List<Json>> _get(String key, String path, [List<String> keys = const []]) =>
      _cache.putIfAbsent(key, () async {
        try {
          return rowsOf(await api.get(path), keys);
        } catch (e) {
          _cache.remove(key);
          rethrow;
        }
      });

  static void invalidate([String? key]) => key == null ? _cache.clear() : _cache.remove(key);

  static Future<List<Json>> universities() => _get('universities', 'getuniversities', ['universities']);
  static Future<List<Json>> schemes() => _get('schemes', 'getschemes', ['schemes']);
  static Future<List<Json>> courses() => _get('courses', 'getcourses', ['courses']);
  static Future<List<Json>> branches() => _get('branches', 'getbranches', ['branches']);
  static Future<List<Json>> semesters() => _get('semesters', 'getsemesters', ['semesters']);
  static Future<List<Json>> colleges() => _get('colleges', 'colleges', ['colleges']);
  static Future<List<Json>> subjects() => _get('subjects', 'getsubjects', ['subjects']);
  static Future<List<Json>> materialTypes() => _get('material_types', 'getmeterial_types');
  static Future<List<Json>> eventCategories() => _get('event_categories', 'event-categories');
  static Future<List<Json>> tags() => _get('tags', 'tags');
  static Future<List<Json>> bookCategories() => _get('book_categories', 'admin/book-categories');
  static Future<List<Json>> confessionCategories() =>
      _get('confession_categories', 'admin/confession-categories', ['categories']);
  static Future<List<Json>> pointActions() => _get('point_actions', 'point-actions/admin');
  static Future<List<Json>> users() => _get('users', 'getusers', ['users']);

  static Future<List<Opt>> universityOpts() async => optsOf(await universities(), withCode: true);
  static Future<List<Opt>> schemeOpts() async => optsOf(await schemes(), labelKeys: ['name', 'scheme_name'], withCode: true);
  static Future<List<Opt>> courseOpts() async => optsOf(await courses(), withCode: true);
  static Future<List<Opt>> branchOpts() async => optsOf(await branches(), labelKeys: ['name', 'branch_name'], withCode: true);
  static Future<List<Opt>> semesterOpts() async => optsOf(await semesters(), labelKeys: ['name', 'semester_name'], withCode: true);
  static Future<List<Opt>> collegeOpts() async => optsOf(await colleges(), labelKeys: ['college_name', 'name']);
  static Future<List<Opt>> subjectOpts() async => (await subjects())
      .map((s) => Opt(s['id'], pick(s, ['name'], '#${s['id']}'), [str(s['code']), str(s['branch_name']), str(s['semester_name'])].where((e) => e.isNotEmpty).join(' · ')))
      .toList();
  static Future<List<Opt>> materialTypeOpts() async => optsOf(await materialTypes());
  static Future<List<Opt>> eventCategoryOpts() async => optsOf(await eventCategories());
  static Future<List<Opt>> tagOpts() async => optsOf(await tags());
  static Future<List<Opt>> userOpts() async => (await users())
      .map((u) => Opt(u['id'] ?? u['user_id'], '${personName(u)} (ID: ${u['id'] ?? u['user_id']})', str(u['email'])))
      .toList();
}
