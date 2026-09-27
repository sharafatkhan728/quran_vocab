import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../database/database_manager.dart';
import '../services/crashlytics_service.dart';
import '../services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider extends ChangeNotifier {
  // Disk pe persist hone wala marker — yeh batata hai ke is device pe
  // AAKHRI baar kaunsa account active tha. Isse account-switch reliably
  // detect hota hai, chahe app restart hi kyu na ho chuka ho (in-memory
  // previousUid restart ke baad hamesha null hota hai, isliye akela kaafi
  // nahi hai — neeche constructor me dekho).
  static const _lastActiveUidKey = 'last_active_uid';

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
            // previousUid akela reliable nahi hai: normal logout ke waqt
            // yehi listener pehle ek baar user == null ke saath fire hota
            // hai, jo previousUid ko null kar deta hai naye account ke
            // login se PEHLE hi — isliye alag account login hone ke
            // bawajood bhi previousUid null milta hai. Isliye hum disk pe
            // persist hui "last active uid" se compare karte hain, jo us
            // beech wale null event me bhi, aur poore app-restart ke baad
            // bhi, sahi rehti hai. Warna syncDown() ka "is account ka cloud
            // data nahi hai" wala fallback purane account ka bacha hua
            // local data naye account ke sath upload kar deta.
            final prefs = await SharedPreferences.getInstance();
            final lastActiveUid = prefs.getString(_lastActiveUidKey);
            final isDifferentAccount =
                lastActiveUid != null && lastActiveUid != user.uid;
            if (previousUid != null || isDifferentAccount) {
              await DatabaseManager.clearLocalUserProgress();
            }
            await prefs.setString(_lastActiveUidKey, user.uid);
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
    // Push any pending local changes before signing out — capped with a
    // timeout so a slow/unavailable network connection can never leave
    // the user staring at the "Logging out..." dialog forever. If it
    // times out, we still proceed: normal usage already pushes changes
    // to the cloud every few seconds via scheduleSyncUp(), so at worst a
    // few seconds of the very latest activity might not have synced yet.
    try {
      await SyncService.syncUp().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('UserProvider.signOut: final syncUp skipped ($e)');
    }
    await FirebaseAuth.instance.signOut();
    // Wipe local progress now that it's safely pushed to THIS account's
    // cloud doc — otherwise it survives on-device and leaks into
    // whichever account (or fresh signup) uses this device next.
    await DatabaseManager.clearLocalUserProgress();
    _profile = {};
    notifyListeners();
  }

  Future<void> _loadLocalGoal() async {
    final prefs = await SharedPreferences.getInstance();
    _localDailyGoal = prefs.getInt('daily_goal') ?? 5;
    notifyListeners();
  }

  /// A short, shareable ID the user can read out or paste into a support
  /// email. This is their Firebase Auth uid — since setUserIdentifier()
  /// above already tags every crash report with this same uid, it's all
  /// that's needed to cross-reference Crashlytics and the Firestore
  /// diagnostics doc for a specific user.
  String getSupportId() => _user?.uid ?? 'unknown';
}
