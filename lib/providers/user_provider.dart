import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../services/crashlytics_service.dart';
import '../services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // Local prefs is the single source of truth for the daily goal.
  int get dailyGoal => _localDailyGoal;

  int _localDailyGoal = 5;
  // true once the user has explicitly chosen a goal on this device
  // (onboarding or profile settings) — this value must never be
  // overwritten by cloud data.
  bool _hasExplicitGoal = false;
  late final Future<void> _localGoalReady;

  UserProvider() {
    _localGoalReady = _loadLocalGoal();
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      final previousUid = _user?.uid;
      _user = user;
      if (user != null) {
        if (previousUid != user.uid) {
          _profile = {};
        }
        // Tags every subsequent crash report with this uid, so a crash you
        // see in Crashlytics can be matched to a specific user's Firestore
        // diagnostics doc (users/{uid}/diagnostics/current) when they
        // report a problem.
        unawaited(FirebaseCrashlytics.instance.setUserIdentifier(user.uid));
        _loadProfile(user.uid);
        // Restore data from cloud on first login or account switch

        if (previousUid != user.uid) {
          _restoring = true;
          notifyListeners();
          try {
            await SyncService.syncDown();
          } finally {
            if (_user?.uid == user.uid) {
              _restoring = false;
              notifyListeners();
            }
          }
        }
      }
      if (user == null) {
        _profile = {};
        _restoring = false;
      }
      notifyListeners();
    });
  }

  Future<void> _loadProfile(String uid) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      await _localGoalReady;
      if (_user?.uid != uid) return;
      _profile = doc.exists ? (doc.data() ?? {}) : {};

      final cloudGoal = _profile['dailyGoal'];
      if (_hasExplicitGoal) {
        // User already chose a goal on this device — it wins.
        if (cloudGoal != _localDailyGoal) {
          _profile['dailyGoal'] = _localDailyGoal;
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set({'dailyGoal': _localDailyGoal}, SetOptions(merge: true));
        }
      } else if (cloudGoal is int) {
        // No local choice yet (e.g. fresh install) — adopt the cloud value.
        _localDailyGoal = cloudGoal;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('daily_goal', cloudGoal);
        _hasExplicitGoal = true;
      }
      notifyListeners();
    } catch (e, stack) {
      debugPrint('UserProvider._loadProfile failed: $e');
      CrashlyticsService.recordError(e, stack,
          context: 'UserProvider._loadProfile');
    }
  }
  Future<void> updateProfile(Map<String, dynamic> data) async {
    await _localGoalReady; // prevents the startup race that overwrote the goal
    _profile.addAll(data);
    // Save daily goal locally so it works offline and without login
    if (data.containsKey('dailyGoal')) {
      _localDailyGoal = data['dailyGoal'] as int;
      _hasExplicitGoal = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('daily_goal', _localDailyGoal);
    }
    notifyListeners();
    if (_user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .set(data, SetOptions(merge: true));
    }
  }

  Future<void> signOut() async {
    // Push any pending local changes before signing out
    await SyncService.syncUp();
    await FirebaseAuth.instance.signOut();
    _profile = {};
    notifyListeners();
  }

  Future<void> _loadLocalGoal() async {
    final prefs = await SharedPreferences.getInstance();
    _localDailyGoal = prefs.getInt('daily_goal') ?? 5;
    notifyListeners();
  }

  /// A short, shareable ID the user can read out or paste into a support
  /// email — lets you look up their Crashlytics install + Firestore
  /// diagnostics without asking for their full email/uid.
  Future<String> getSupportId() async {
    try {
      final crashId =
          await FirebaseCrashlytics.instance.getInstallationId() ?? '';
      return crashId.isEmpty ? (_user?.uid ?? 'unknown') : crashId;
    } catch (_) {
      return _user?.uid ?? 'unknown';
    }
  }
}
