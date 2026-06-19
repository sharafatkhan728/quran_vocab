import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/sync_service.dart';

class UserProvider extends ChangeNotifier {
  User? _user;
  Map<String, dynamic> _profile = {};
  bool _restoring = false;

  User? get user => _user;
  Map<String, dynamic> get profile => _profile;
  bool get isLoggedIn => _user != null;
  bool get isRestoring => _restoring;

  String get displayName => _profile['name'] ?? _user?.displayName ?? 'Learner';
  String get email => _user?.email ?? '';
  String get photoUrl => _profile['photoUrl'] ?? _user?.photoURL ?? '';
  String get gender => _profile['gender'] ?? '';
  int get dailyGoal => _profile['dailyGoal'] ?? 5;

  UserProvider() {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      final wasLoggedOut = _user == null;
      _user = user;
      if (user != null) {
        _loadProfile();
        // Restore data from cloud on first login or account switch
        if (wasLoggedOut) {
          _restoring = true;
          notifyListeners();
          await SyncService.syncDown();
          _restoring = false;
        }
      }
      notifyListeners();
    });
  }

  Future<void> _loadProfile() async {
    if (_user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();
      if (doc.exists) {
        _profile = doc.data() ?? {};
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    if (_user == null) return;
    _profile.addAll(data);
    notifyListeners();
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .set(data, SetOptions(merge: true));
  }

  Future<void> signOut() async {
    // Push any pending local changes before signing out
    await SyncService.syncUp();
    await FirebaseAuth.instance.signOut();
    _profile = {};
    notifyListeners();
  }
}
