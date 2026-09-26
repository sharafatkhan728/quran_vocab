import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:world_csc_picker/country_state_city_picker.dart';
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

  String _country = '';
  String _city = '';
  String _avatar = kAvatarEmojis.first;
  bool _visGlobal = true, _visCountry = true, _visCity = true;
  bool _loading = true, _saving = false, _pickerReady = false;
  String? _friendCode;
  CountryStateCityData? _cscData;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Bundled local JSON load — one-time, offline, no network involved.
    final data = CountryStateCityData();
    await data.load();

    final doc = await LeaderboardService.getMyProfile();
    if (doc != null && doc.exists) {
      final d = doc.data()!;
      _country = (d['country'] ?? '').toString();
      _city = (d['city'] ?? '').toString();
      _avatar = (d['avatarEmoji'] ?? kAvatarEmojis.first).toString();
      _visGlobal = d['visibleGlobal'] ?? true;
      _visCountry = d['visibleCountry'] ?? true;
      _visCity = d['visibleCity'] ?? true;
      _friendCode = (d['friendCode'] ?? '').toString();
    }
    if (mounted) {
      setState(() {
        _cscData = data;
        _loading = false;
        _pickerReady = true;
      });
    }
  }

  Future<void> _openLocationPicker() async {
    if (_cscData == null) return;
    String? tempCountry;
    String? tempCity;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Select your Country & City',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: CountryStateCityPicker(
                data: _cscData!,
                onSelection: (country, state, city) {
                  tempCountry = country;
                  tempCity = city.name;
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _green),
                onPressed: () {
                  if (tempCountry != null && tempCity != null) {
                    setState(() {
                      _country = tempCountry!;
                      _city = tempCity!;
                    });
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Confirm', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_country.isEmpty || _city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Country aur City select karo pehle')));
      return;
    }
    setState(() => _saving = true);
    try {
      // Naam hamesha Profile (UserProvider) se hi aata hai — alag se nahi
      // pucha jaata, taaki dono jagah same naam dikhe.
      final myName = context.read<UserProvider>().displayName;
      final code = await LeaderboardService.saveProfile(
        displayName: myName,
        avatarEmoji: _avatar,
        country: _country,
        city: _city,
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const Text('Aapka Profile ka naam (leaderboard pe bhi yehi dikhega)',
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

          const Text('Location', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Dropdown se select karo — isse har user ka same city sahi se match hoga',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickerReady ? _openLocationPicker : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: _green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (_country.isEmpty && _city.isEmpty)
                          ? 'Tap to select Country & City'
                          : '$_city, $_country',
                      style: TextStyle(
                          color: (_country.isEmpty) ? Colors.grey : Colors.black87,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
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