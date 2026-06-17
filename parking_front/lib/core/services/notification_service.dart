import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Notifications système locales (Android/iOS).
///
/// - `show()`        : notification immédiate (parking complet pendant le guidage).
/// - `scheduleAt()`  : notification planifiée qui se déclenche **même app fermée**
///                     (ex. réservation bientôt expirée, 2 min avant).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'smartpark_alerts';
  static const String _channelName = 'Alertes SmartPark';
  static const String _channelDesc =
      'Réservations et disponibilité des places';

  /// Identifiant de notification stable (positif) à partir d'une clé texte
  /// (ex. l'id d'une réservation) pour pouvoir replanifier/annuler.
  static int idFor(String key) => key.hashCode & 0x7fffffff;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    // Fuseau horaire (requis par la planification zonedSchedule).
    tzdata.initializeTimeZones();
    try {
      final String tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      // Repli silencieux : tz.local restera UTC.
    }

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Canal Android (obligatoire à partir d'Android 8).
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// Demande l'autorisation d'afficher des notifications (Android 13+ / iOS)
  /// + l'autorisation des alarmes exactes (Android 12+) pour un déclenchement
  /// fiable à l'heure prévue, même app fermée.
  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {
      // Indisponible selon la version → on retombera sur l'alarme inexacte.
    }

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Notification immédiate.
  Future<void> show(int id, String title, String body) async {
    if (!_initialized) {
      await init();
    }
    await _plugin.show(id, title, body, _details());
  }

  /// Notification planifiée à une date précise (déclenchée même app fermée).
  /// Ne fait rien si la date est déjà passée.
  Future<void> scheduleAt(
    int id,
    String title,
    String body,
    DateTime when,
  ) async {
    if (!_initialized) {
      await init();
    }

    final tz.TZDateTime scheduled = tz.TZDateTime.from(when, tz.local);
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) {
      return;
    }

    // On tente d'abord une alarme EXACTE (déclenchement précis même en veille).
    // Si l'autorisation manque, on retombe sur une alarme inexacte (toujours
    // fonctionnelle, mais potentiellement décalée de quelques minutes).
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        _details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancel(int id) async {
    if (!_initialized) {
      return;
    }
    await _plugin.cancel(id);
  }
}
