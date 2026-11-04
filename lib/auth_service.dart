import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_service.dart';

/// PocketBase `users` auth (DharmaCore parity).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  PocketBase get _pb => PocketBaseService().pb;

  bool get isLoggedIn => _pb.authStore.isValid;

  RecordModel? get user => _pb.authStore.record;

  String? get userId => user?.id;

  String? get email => user?.getStringValue('email');

  /// PocketBase `users.name` when set; otherwise null.
  String? get name {
    final n = user?.getStringValue('name').trim();
    if (n == null || n.isEmpty) return null;
    return n;
  }

  /// Prefer [name], fall back to [email].
  String? get displayName => name ?? email;

  /// Personal dashboard scratch pad (`users.quick_notes`).
  String get quickNotes {
    final v = user?.data['quick_notes']?.toString();
    return v ?? '';
  }

  /// Persist [text] on the current user and refresh the auth store record.
  Future<void> saveQuickNotes(String text) async {
    final id = userId;
    final token = _pb.authStore.token;
    if (id == null || token.isEmpty) return;
    final rec = await _pb.collection('users').update(
      id,
      body: {'quick_notes': text},
    );
    _pb.authStore.save(token, rec);
  }

  /// Persist `users.name` for the signed-in user (shown in History, wiki, …).
  Future<void> saveName(String name) async {
    final id = userId;
    final token = _pb.authStore.token;
    if (id == null || token.isEmpty) return;
    final rec = await _pb.collection('users').update(
      id,
      body: {'name': name.trim()},
    );
    _pb.authStore.save(token, rec);
  }

  /// `full`, `jobs_only`, or null/empty (treated as full).
  String get role {
    final r = user?.getStringValue('role').trim();
    if (r == null || r.isEmpty) return 'full';
    return r;
  }

  bool get isJobsOnly => role == 'jobs_only';

  bool _boolFlag(String name) {
    final v = user?.data[name];
    return v == true || v == 1 || v == 'true';
  }

  /// PocketBase `users.wiki_owner` — can see owner-only wiki pages.
  bool get isWikiOwner => _boolFlag('wiki_owner');

  /// PocketBase `users.wiki_readonly` — can read wiki, cannot create/edit/delete.
  bool get isWikiReadonly => _boolFlag('wiki_readonly');

  bool get canEditWiki => isLoggedIn && !isWikiReadonly;

  Future<void> login({required String email, required String password}) async {
    await _pb.collection('users').authWithPassword(email.trim(), password);
  }

  void logout() => _pb.authStore.clear();
}
