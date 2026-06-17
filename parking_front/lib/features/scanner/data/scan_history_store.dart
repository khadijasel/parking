import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Une entrée de l'historique des scans (entrée ou sortie).
class ScanHistoryEntry {
  final String ticketName; // nom/code du ticket
  final String parkingName; // nom du parking
  final String mode; // 'entry' | 'exit'
  final bool success;
  final String message;
  final DateTime timestamp;

  const ScanHistoryEntry({
    required this.ticketName,
    required this.parkingName,
    required this.mode,
    required this.success,
    required this.message,
    required this.timestamp,
  });

  bool get isEntry => mode == 'entry';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ticket_name': ticketName,
        'parking_name': parkingName,
        'mode': mode,
        'success': success,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ScanHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ScanHistoryEntry(
      // 'reference' : ancienne clé, conservée pour compat des données déjà stockées.
      ticketName:
          (json['ticket_name'] ?? json['reference'] ?? '').toString(),
      parkingName: (json['parking_name'] ?? '').toString(),
      mode: (json['mode'] ?? 'entry').toString(),
      success: json['success'] == true,
      message: (json['message'] ?? '').toString(),
      timestamp:
          DateTime.tryParse((json['timestamp'] ?? '').toString()) ??
              DateTime.now(),
    );
  }
}

/// Persiste l'historique des scans localement (SharedPreferences).
///
/// Conserve au maximum [_maxEntries] entrées, les plus récentes en premier.
class ScanHistoryStore {
  static const String _key = 'scan_history_v1';
  static const int _maxEntries = 50;

  Future<List<ScanHistoryEntry>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) {
      return <ScanHistoryEntry>[];
    }

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <ScanHistoryEntry>[];
      }

      return decoded
          .whereType<Map>()
          .map((Map<dynamic, dynamic> item) => ScanHistoryEntry.fromJson(
                item.map<String, dynamic>(
                  (dynamic k, dynamic v) => MapEntry<String, dynamic>(
                    k.toString(),
                    v,
                  ),
                ),
              ))
          .toList(growable: false);
    } catch (_) {
      return <ScanHistoryEntry>[];
    }
  }

  Future<List<ScanHistoryEntry>> add(ScanHistoryEntry entry) async {
    final List<ScanHistoryEntry> current = await load();
    final List<ScanHistoryEntry> updated = <ScanHistoryEntry>[
      entry,
      ...current,
    ];
    final List<ScanHistoryEntry> capped = updated.length > _maxEntries
        ? updated.sublist(0, _maxEntries)
        : updated;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(capped.map((ScanHistoryEntry e) => e.toJson()).toList()),
    );

    return capped;
  }

  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
