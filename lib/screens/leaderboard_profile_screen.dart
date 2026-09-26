import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/leaderboard_models.dart';
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

  final _nameCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  String _avatar = kAvatarEmojis.first;
  bool _visGlobal = true, _visCountry = true, _visCity = true;
  bool _loading = true, _saving = false;
  String? _friendCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await LeaderboardService.getMyProfile();
    if (doc != null && doc.exists) {
      final d = doc.data()!;
      _nameCtrl.text = (d['displayName'] ?? '').toString();
      _countryCtrl.text = (d['country'] ?? '').toString();
      _cityCtrl.text = (d['city'] ?? '').toString();
      _avatar = (d['avatarEmoji'] ?? kAvatarEmojis.first).toString();
      _visGlobal = d['visibleGlobal'] ?? true;
      _visCountry = d['visibleCountry'] ?? true;
      _visCity = d['visibleCity'] ?? true;
      _friendCode = (d['friendCode'] ?? '').toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Naam daalo pehle')));
      return;
    }
    setState(() => _saving = true);
    try {
      final code = await LeaderboardService.saveProfile(
        displayName: _nameCtrl.text,
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    color: sel ? _gold.withValues(alpha: 0.25) : Colors.grey.shade100,
                    border: Border.all(
                        color: sel ? _gold : Colors.grey.shade300, width: 2),
                  ),
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Display Name (public)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _countryCtrl,
            decoration: const InputDecoration(
                labelText: 'Country (e.g. India)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cityCtrl,
            decoration: const InputDecoration(
                labelText: 'City (e.g. Surat)', border: OutlineInputBorder()),
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
                          fontSize: 18, fontWeight: FontWeight.bold, color: _gold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _friendCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied!')));
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
                    width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}