import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../data/country_list.dart';
import '../models/leaderboard_models.dart';
import '../providers/user_provider.dart';
import '../services/leaderboard_service.dart';

class LeaderboardProfileScreen extends StatefulWidget {
  const LeaderboardProfileScreen({super.key});
  @override
  State<LeaderboardProfileScreen> createState() =>
      _LeaderboardProfileScreenState();
}

class _LeaderboardProfileScreenState extends State<LeaderboardProfileScreen> {
  static const _green = Color(0xFF1B4332);
  static const _gold = Color(0xFFD4AF37);

  final _countryCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  String _avatar = kAvatarEmojis.first;
  bool _visGlobal = true, _visCountry = true, _visCity = true;
  bool _loading = true, _saving = false;
  String? _friendCode;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _countryCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await LeaderboardService.getMyProfile();
      if (doc != null && doc.exists) {
        final d = doc.data()!;
        _countryCtrl.text = (d['country'] ?? '').toString();
        _cityCtrl.text = (d['city'] ?? '').toString();
        _avatar = (d['avatarEmoji'] ?? kAvatarEmojis.first).toString();
        _visGlobal = d['visibleGlobal'] ?? true;
        _visCountry = d['visibleCountry'] ?? true;
        _visCity = d['visibleCity'] ?? true;
        _friendCode = (d['friendCode'] ?? '').toString();
      }
    } catch (e) {
      _loadError = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_countryCtrl.text.trim().isEmpty || _cityCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Country aur City daalo pehle')));
      return;
    }
    setState(() => _saving = true);
    try {
      final myName = context.read<UserProvider>().displayName;
      final code = await LeaderboardService.saveProfile(
        displayName: myName,
        avatarEmoji: _avatar,
        country: _countryCtrl.text,
        city: _cityCtrl.text,
        visibleGlobal: _visGlobal,
        visibleCountry: _visCountry,
        visibleCity: _visCity,
      );
      if (mounted) {
        setState(() => _friendCode = code);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved ✓')));
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Save failed'),
            content: SelectableText(e.toString()),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myName = context.watch<UserProvider>().displayName;

    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: _gold)));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard Profile'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loadError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                'Load warning (profile still usable): $_loadError',
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ),

          // Naam — Profile se auto-liya, edit yahan se nahi hota
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: _green),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(myName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const Text(
                          'Aapka Profile ka naam (leaderboard pe bhi yehi dikhega)',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text('Avatar', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kAvatarEmojis.map((e) {
              final sel = _avatar == e;
              return GestureDetector(
                onTap: () => setState(() => _avatar = e),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sel
                        ? _gold.withValues(alpha: 0.25)
                        : Colors.grey.shade100,
                    border: Border.all(
                        color: sel ? _gold : Colors.grey.shade300, width: 2),
                  ),
                  child: Center(
                      child: Text(e, style: const TextStyle(fontSize: 22))),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          const Text('Location', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Country list se select karo — spelling hamesha consistent rahegi',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _countryCtrl.text),
            optionsBuilder: (v) {
              if (v.text.isEmpty) return kCountryNames;
              return kCountryNames.where((c) =>
                  c.toLowerCase().contains(v.text.toLowerCase()));
            },
            onSelected: (v) => _countryCtrl.text = v,
            fieldViewBuilder: (context, ctrl, focus, onSubmit) {
              // Keep our own controller in sync with the Autocomplete's
              // internal field controller so free typing also counts.
              ctrl.text = _countryCtrl.text.isEmpty ? ctrl.text : ctrl.text;
              ctrl.addListener(() => _countryCtrl.text = ctrl.text);
              return TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.public),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cityCtrl,
            decoration: const InputDecoration(
              labelText: 'City',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_city),
              helperText: 'e.g. Surat — same spelling as friends for best matching',
            ),
          ),
          const SizedBox(height: 20),

          const Text('Visible on', style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text('🌍 Global leaderboard'),
            value: _visGlobal,
            activeColor: _green,
            onChanged: (v) => setState(() => _visGlobal = v),
          ),
          SwitchListTile(
            title: const Text('🇮🇳 Country leaderboard'),
            value: _visCountry,
            activeColor: _green,
            onChanged: (v) => setState(() => _visCountry = v),
          ),
          SwitchListTile(
            title: const Text('🏙️ City leaderboard'),
            value: _visCity,
            activeColor: _green,
            onChanged: (v) => setState(() => _visCity = v),
          ),
          const SizedBox(height: 20),

          if (_friendCode != null && _friendCode!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gold.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Text('Your Friend Code: ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_friendCode!,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _gold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _friendCode!));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Copied!')));
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}