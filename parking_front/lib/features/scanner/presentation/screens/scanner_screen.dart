import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../reservation/data/models/reservation_api_model.dart';
import '../../../reservation/data/reservation_repository.dart';
import '../../data/scan_history_store.dart';

// ════════════════════════════════════════════════════════════
//  SCANNER SCREEN — SmartPark
//
//  Principe :
//    1. Scanne ticket QR généré par le script Python
//    2. QR contient JSON :
//       { "ticket_id": "...", "ticket_code": "...",
//         "parking_id": "arduino-sim", "entry_time": "...",
//         "status": "unpaid" }
//
//    Mode ENTRÉE :
//      → Valide le parking_id dans la base de données
//      → Si parking inconnu → "Ticket invalide"
//      → Si session déjà active avec ce ticket → lit juste les données
//      → Sinon → lance la session → home_screen affiche session + même QR
//
//    Mode SORTIE :
//      → Rescanne le même ticket
//      → Vérifie status = "paid" côté backend
//      → PAID + délai < 15 min → barrière ouvre
//      → Sinon → message erreur
//
//    Règle d'unicité ticket :
//      → Chaque ticket a un UUID unique
//      → Une fois la session terminée, ce ticket est marqué "used"
//      → Impossible de rescanner un ticket déjà utilisé (session closed)
//
//  Dépendances pubspec.yaml :
//    mobile_scanner: ^5.x.x
//    image_picker: ^1.x.x
// ════════════════════════════════════════════════════════════

const _kBlue    = Color(0xFF4A90E2);
const _kGreen   = Color(0xFF2ECC71);
const _kRed     = Color(0xFFE53935);
const _kDark    = Color(0xFF1A1A2E);
const _kMid     = Color(0xFF8A9BB5);

// ── Enum mode scan ───────────────────────────────────────────
enum ScanMode { entry, exit }

// ── Modèle payload ticket ────────────────────────────────────
class _TicketPayload {
  final String? ticketId;
  final String? ticketCode;
  final String? parkingId;
  final String? entryTime;
  final String? status;

  const _TicketPayload({
    this.ticketId,
    this.ticketCode,
    this.parkingId,
    this.entryTime,
    this.status,
  });

  bool get isEmpty =>
      (ticketId?.trim().isEmpty ?? true) &&
      (ticketCode?.trim().isEmpty ?? true);

  bool get isPaid => status?.trim().toLowerCase() == 'paid';

  String get display =>
      ticketCode ?? ticketId ?? 'TICKET-INCONNU';
}

// ════════════════════════════════════════════════════════════

class ScannerScreen extends StatefulWidget {
  /// Appelé après un scan validé, avec le mode concerné (entrée/sortie).
  /// Permet à l'appelant de réagir différemment selon entrée vs sortie
  /// (ex. l'onglet principal redirige vers le home après une entrée).
  final void Function(ScanMode mode)? onScanSuccess;
  final ScanMode initialMode;

  /// Si `true`, le scanner se ferme automatiquement (Navigator.pop) après
  /// une sortie validée — utilisé quand il est poussé comme route (guidage).
  /// Si `false` (onglet permanent), le scanner reste ouvert, la caméra reste
  /// active et repasse en mode Entrée pour permettre un nouveau ticket.
  final bool autoCloseOnExit;

  /// Indique si l'écran est actuellement visible (onglet sélectionné).
  /// Quand il passe à `false`, la caméra est arrêtée (pas de gaspillage en
  /// arrière-plan) ; quand il repasse à `true`, elle est redémarrée — ce qui
  /// évite l'aperçu noir au retour sur l'onglet scanner.
  final bool isActive;

  const ScannerScreen({
    super.key,
    this.onScanSuccess,
    this.initialMode = ScanMode.entry,
    this.autoCloseOnExit = false,
    this.isActive = true,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

  // ── Contrôleurs ──────────────────────────────────────────
  late final MobileScannerController _cameraCtrl;
  late final AnimationController     _scanCtrl;
  late final Animation<double>       _scanAnim;

  // ── États ────────────────────────────────────────────────
  bool      _torchOn      = false;
  bool      _isScanning   = true;
  bool      _isSubmitting = false;
  bool      _cameraRunning = false;
  ScanMode  _mode         = ScanMode.entry;

  final ReservationRepository _repo = ReservationRepository();
  final ImagePicker           _picker = ImagePicker();
  final ScanHistoryStore      _historyStore = ScanHistoryStore();
  List<ScanHistoryEntry>      _history = <ScanHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mode = widget.initialMode;

    // autoStart: false → on pilote nous-mêmes start()/stop() selon la
    // visibilité de l'onglet et le cycle de vie de l'app. C'est ce qui évite
    // que la caméra reste « activée en arrière-plan » avec un aperçu noir.
    _cameraCtrl = MobileScannerController(
      torchEnabled: false,
      autoStart: false,
      detectionSpeed: DetectionSpeed.normal,
    );

    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scanAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut),
    );

    _loadHistory();

    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
    }
  }

  Future<void> _loadHistory() async {
    final List<ScanHistoryEntry> entries = await _historyStore.load();
    if (!mounted) return;
    setState(() => _history = entries);
  }

  Future<void> _recordHistory(
    String ticketName,
    String parkingName,
    bool success,
    String message,
  ) async {
    final ScanHistoryEntry entry = ScanHistoryEntry(
      ticketName: ticketName.trim().isEmpty ? 'Ticket' : ticketName.trim(),
      parkingName: parkingName.trim(),
      mode: _mode == ScanMode.entry ? 'entry' : 'exit',
      success: success,
      message: message,
      timestamp: DateTime.now(),
    );
    final List<ScanHistoryEntry> updated = await _historyStore.add(entry);
    if (!mounted) return;
    setState(() => _history = updated);
  }

  String _formatHistoryDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  void _openHistorySheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          'Historique des scans',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _kDark,
                          ),
                        ),
                        if (_history.isNotEmpty)
                          TextButton.icon(
                            onPressed: () async {
                              await _historyStore.clear();
                              if (!mounted) return;
                              setState(() => _history = <ScanHistoryEntry>[]);
                              setSheetState(() {});
                            },
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18, color: _kRed),
                            label: const Text('Vider',
                                style: TextStyle(color: _kRed)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_history.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            'Aucun scan pour le moment.',
                            style: TextStyle(color: _kMid, fontSize: 14),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _history.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (BuildContext _, int index) {
                            final ScanHistoryEntry e = _history[index];
                            final Color tone =
                                e.success ? _kGreen : _kRed;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: tone.withOpacity(0.12),
                                child: Icon(
                                  e.isEntry
                                      ? Icons.login_rounded
                                      : Icons.logout_rounded,
                                  color: tone,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                'Ticket : ${e.parkingName.isEmpty ? 'Parking inconnu' : e.parkingName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _kDark,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                '${e.isEntry ? 'Entrée' : 'Sortie'} · ${e.success ? 'Validé' : 'Échec'}',
                                style: const TextStyle(color: _kMid, fontSize: 12),
                              ),
                              trailing: Text(
                                _formatHistoryDate(e.timestamp),
                                style: TextStyle(
                                    color: _kMid, fontSize: 11),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _startCamera();
      } else {
        _stopCamera();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!widget.isActive) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _startCamera();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanCtrl.dispose();
    _cameraCtrl.dispose();
    super.dispose();
  }

  // ── Cycle de vie caméra ──────────────────────────────────
  Future<void> _startCamera() async {
    if (!mounted || _cameraRunning) return;
    _cameraRunning = true;
    try {
      await _cameraCtrl.start();
    } catch (_) {
      _cameraRunning = false;
    }
  }

  Future<void> _stopCamera() async {
    if (!_cameraRunning) return;
    _cameraRunning = false;
    try {
      await _cameraCtrl.stop();
    } catch (_) {}
  }

  // ── Toggle lampe torche ──────────────────────────────────
  void _toggleTorch() {
    setState(() => _torchOn = !_torchOn);
    _cameraCtrl.toggleTorch();
    HapticFeedback.selectionClick();
  }

  // ── Ouvrir galerie et lire QR ────────────────────────────
  Future<void> _openGallery() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    try {
      final BarcodeCapture? capture =
          await _cameraCtrl.analyzeImage(file.path);
      if (capture == null || capture.barcodes.isEmpty) {
        if (mounted) {
          _showResultSheet(
            '',
            isValid: false,
            message: 'Aucun QR trouvé dans cette image.',
          );
        }
        return;
      }
      final String code = capture.barcodes.first.rawValue ?? '';
      if (code.isNotEmpty) {
        await _onQRDetected(code);
      }
    } catch (_) {
      if (mounted) {
        _showResultSheet(
          '',
          isValid: false,
          message: 'Impossible de lire le QR depuis la galerie.',
        );
      }
    }
  }

  // ── Callback détection QR par caméra ─────────────────────
  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning || _isSubmitting) return;
    final String code = capture.barcodes.first.rawValue ?? '';
    if (code.isNotEmpty) {
      _onQRDetected(code);
    }
  }

  // ════════════════════════════════════════════════════════
  //  LOGIQUE PRINCIPALE — traitement du QR scanné
  // ════════════════════════════════════════════════════════
  Future<void> _onQRDetected(String rawCode) async {
    if (_isSubmitting) return;

    HapticFeedback.heavyImpact();
    setState(() {
      _isScanning   = false;
      _isSubmitting = true;
    });
    _scanCtrl.stop();

    try {
      // 1. Parser le QR
      final _TicketPayload payload = _parsePayload(rawCode);

      // 2. Ticket vide / illisible
      if (payload.isEmpty) {
        _showResultSheet(
          rawCode,
          isValid: false,
          message: 'QR invalide ou illisible. Veuillez réessayer.',
        );
        return;
      }

      // ── MODE ENTRÉE ──────────────────────────────────────
      if (_mode == ScanMode.entry) {
        await _handleEntry(rawCode, payload);
      }
      // ── MODE SORTIE ──────────────────────────────────────
      else {
        await _handleExit(rawCode, payload);
      }
    } on ReservationException catch (e) {
      _showResultSheet(
        rawCode,
        isValid: false,
        message: e.message,
      );
    } catch (_) {
      _showResultSheet(
        rawCode,
        isValid: false,
        message: 'Impossible de valider ce ticket pour le moment.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ── Mode ENTRÉE ──────────────────────────────────────────
  Future<void> _handleEntry(
      String rawCode, _TicketPayload payload) async {

    // Pas de pré-vérification locale : le backend valide tout en un seul
    // appel (session active, ticket déjà utilisé, parking inconnu, etc.).

    try {
      final Map<String, dynamic> result = await _repo.scanParkingTicket(
        ticketId:   payload.ticketId,
        ticketCode: payload.ticketCode,
        parkingId:  payload.parkingId,
      );

      final String? ref = _extractTicketRef(result);

      _showResultSheet(
        rawCode,
        isValid: true,
        message: 'Session démarrée avec succès.\nGuidez-vous vers votre place.',
        ticketReference: ref,
        parkingName: _extractParkingName(result, payload),
        qrImagePath: _extractQrImagePath(result),
        afterClose: () => widget.onScanSuccess?.call(ScanMode.entry),
      );
    } on ReservationException catch (e) {
      // Parking non reconnu → "Ticket invalide"
      if (_isParkingNotFound(e.message)) {
        _showResultSheet(
          rawCode,
          isValid: false,
          message: 'Ticket invalide : ce parking n\'est pas dans notre réseau.',
        );
        return;
      }

      // Session déjà active avec ce ticket → lire seulement
      if (_isAlreadyActive(e.message)) {
        _showResultSheet(
          rawCode,
          isValid: true,
          message: 'Session déjà en cours.\nInformations du ticket lues.',
          ticketReference: payload.ticketCode ?? payload.ticketId,
          afterClose: () => widget.onScanSuccess?.call(ScanMode.entry),
        );
        return;
      }

      // Ticket déjà utilisé (session terminée)
      if (_isAlreadyUsed(e.message)) {
        _showResultSheet(
          rawCode,
          isValid: false,
          message: 'Ce ticket a déjà été utilisé.\nChaque session nécessite un nouveau ticket.',
        );
        return;
      }

      // Fallback ancienne réservation MongoDB ID
      if (_isMongoId(rawCode) && _isTicketNotFound(e.message)) {
        final ReservationApiModel res =
            await _repo.completeReservationByTicket(rawCode);
        _showResultSheet(
          rawCode,
          isValid: true,
          message: 'Ticket scanné avec succès.',
          ticketReference: res.id,
          afterClose: () => widget.onScanSuccess?.call(ScanMode.entry),
        );
        return;
      }

      rethrow;
    }
  }

  // ── Mode SORTIE ──────────────────────────────────────────
  Future<void> _handleExit(
      String rawCode, _TicketPayload payload) async {

    final String ticketId = (payload.ticketId ?? '').trim();
    final String? ticketCode = payload.ticketCode?.trim();

    // Pas de pré-vérification locale : le backend valide la session/ticket
    // dans exitParkingTicket directement.

    if (ticketId.isEmpty) {
      _showResultSheet(
        rawCode,
        isValid: false,
        message: 'Ticket invalide : ticket_id manquant.\nScannez le QR complet.',
      );
      return;
    }

    try {
      final Map<String, dynamic> result = await _repo.exitParkingTicket(
        ticketId: ticketId,
        ticketCode: ticketCode,
      );

      final String? ref = _extractTicketRef(result) ??
          (ticketCode?.isNotEmpty == true ? ticketCode : ticketId);

      _showResultSheet(
        rawCode,
        isValid: true,
        message: 'Sortie autorisée.\nBonne route !',
        ticketReference: ref,
        parkingName: _extractParkingName(result, payload),
        afterClose: () {
          // Call parent callback first
          widget.onScanSuccess?.call(ScanMode.exit);

          if (widget.autoCloseOnExit) {
            // Scanner poussé comme route (guidage) → on le ferme après un
            // court délai pour laisser voir le message de succès.
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) {
                Navigator.pop(context, true);
              }
            });
          } else {
            // Onglet permanent → la caméra reste active. On repasse en mode
            // Entrée pour qu'un nouveau ticket puisse être scanné aussitôt.
            if (mounted) {
              setState(() => _mode = ScanMode.entry);
            }
          }
        },
      );
    } on ReservationException catch (e) {
      if (_isAlreadyUsed(e.message)) {
        _showResultSheet(
          rawCode,
          isValid: false,
          message:
              'Ce ticket a déjà été utilisé.\nChaque session nécessite un nouveau ticket.',
        );
        return;
      }

      rethrow;
    }
  }

  // ════════════════════════════════════════════════════════
  //  PARSING QR
  // ════════════════════════════════════════════════════════
  _TicketPayload _parsePayload(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return const _TicketPayload();

    // JSON QR généré par le script Python
    // { "ticket_id": "...", "ticket_code": "...",
    //   "parking_id": "arduino-sim", "entry_time": "...",
    //   "status": "unpaid" }
    if (t.startsWith('{') && t.endsWith('}')) {
      try {
        final Object? decoded = jsonDecode(t);
        if (decoded is Map) {
          final Map<String, dynamic> map = decoded.map<String, dynamic>(
            (k, v) => MapEntry(k.toString(), v),
          );
          return _TicketPayload(
            ticketId:   _str(map['ticket_id']   ?? map['ticketId']),
            ticketCode: _str(map['ticket_code']  ?? map['ticketCode']),
            parkingId:  _str(map['parking_id']   ?? map['parkingId']),
            entryTime:  _str(map['entry_time']   ?? map['entryTime']),
            status:     _str(map['status']),
          );
        }
      } catch (_) {}
    }

    // MongoDB ObjectId (fallback legacy)
    if (_isMongoId(t)) {
      return _TicketPayload(ticketId: t);
    }

    // Texte brut → considéré comme ticket_code
    return _TicketPayload(ticketCode: t);
  }

  // ════════════════════════════════════════════════════════
  //  HELPERS
  // ════════════════════════════════════════════════════════
  String? _str(Object? v) {
    if (v == null) return null;
    final String s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  bool _isMongoId(String v) =>
      RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(v.trim());

  bool _isParkingNotFound(String msg) =>
      msg.toLowerCase().contains('parking') &&
      (msg.toLowerCase().contains('introuvable') ||
       msg.toLowerCase().contains('not found') ||
       msg.toLowerCase().contains('invalide'));

  bool _isAlreadyActive(String msg) =>
      msg.toLowerCase().contains('session') &&
      (msg.toLowerCase().contains('active') ||
       msg.toLowerCase().contains('en cours'));

  bool _isAlreadyUsed(String msg) =>
      msg.toLowerCase().contains('déjà utilisé') ||
      msg.toLowerCase().contains('already used') ||
      msg.toLowerCase().contains('terminée');

  bool _isTicketNotFound(String msg) =>
      msg.toLowerCase().contains('introuvable') ||
      msg.toLowerCase().contains('not found');

  String? _extractTicketRef(Map<String, dynamic> data) {
    final Object? ticket = data['ticket'];
    if (ticket is Map) {
      final Object? id = ticket['id'] ?? ticket['ticket_code'];
      if (id != null) {
        final String s = id.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    final Object? ref = data['ticket_code'] ?? data['ticketCode'];
    if (ref != null) {
      final String s = ref.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  String? _extractQrImagePath(Map<String, dynamic> data) {
    final Object? path = data['qr_image_path'] ?? data['qrImagePath'];
    if (path != null) {
      final String s = path.toString().trim();
      return s.isNotEmpty ? s : null;
    }
    return null;
  }

  /// Nom du parking pour l'historique : on le prend dans la session/ticket
  /// renvoyé par le backend, avec repli sur le parking_id du QR.
  String _extractParkingName(Map<String, dynamic> data, _TicketPayload payload) {
    final Object? session = data['parking_session'];
    if (session is Map) {
      final String s = (session['parking_name'] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    final Object? ticket = data['ticket'];
    if (ticket is Map) {
      final String s = (ticket['parking_name'] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    final Object? topLevel = data['parking_name'] ?? data['parkingName'];
    if (topLevel != null) {
      final String s = topLevel.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return (payload.parkingId ?? '').trim();
  }

  // ════════════════════════════════════════════════════════
  //  BOTTOM SHEET résultat
  // ════════════════════════════════════════════════════════
  void _showResultSheet(
    String code, {
    required bool isValid,
    required String message,
    String? ticketReference,
    String? parkingName,
    String? qrImagePath,
    VoidCallback? afterClose,
  }) {
    // Journalise chaque scan (nom du ticket + nom du parking) dans l'historique.
    _recordHistory(
      ticketReference ?? code,
      parkingName ?? '',
      isValid,
      message,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      isScrollControlled: true,
      builder: (_) => _ScanResultSheet(
        code:            code,
        isValid:         isValid,
        message:         message,
        ticketReference: ticketReference,
        qrImagePath:     qrImagePath,
        onRetry: () {
          Navigator.pop(context);
          setState(() => _isScanning = true);
          _scanCtrl.repeat(reverse: true);
          _startCamera();
        },
        onClose: () {
          Navigator.pop(context);
          if (mounted) {
            setState(() {
              _isSubmitting = false;
              _isScanning = true;
            });
          }
          _scanCtrl.repeat(reverse: true);
          _startCamera();
          afterClose?.call();
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final Size   sz     = MediaQuery.of(context).size;
    final double frameW = sz.width * 0.73;
    final double frameH = frameW * 1.22;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [

        // ── VRAIE CAMÉRA ───────────────────────────────────
        MobileScanner(
          controller: _cameraCtrl,
          onDetect: _onDetect,
          errorBuilder: (_, error) => Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt_outlined,
                    color: Colors.white54, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Erreur caméra : ${error.errorDetails?.message ?? "inconnue"}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),

        // ── OVERLAY FONCÉ ──────────────────────────────────
        _buildOverlay(sz, frameW, frameH),

        // ── CADRE QR ───────────────────────────────────────
        Center(
          child: SizedBox(
            width: frameW,
            height: frameH,
            child: Stack(children: [
              // Fond semi-transparent
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              // Coins bleus
              _buildCorners(frameW, frameH),
              // Ligne scan animée
              if (_isScanning)
                AnimatedBuilder(
                  animation: _scanAnim,
                  builder: (_, __) => Positioned(
                    top:  _scanAnim.value * (frameH - 4),
                    left: 14,
                    right: 14,
                    child: Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          _kBlue.withOpacity(0),
                          _kBlue,
                          _kBlue.withOpacity(0),
                        ]),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: _kBlue.withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Spinner pendant traitement
              if (_isSubmitting)
                const Center(
                  child: CircularProgressIndicator(
                    color: _kBlue,
                    strokeWidth: 2.5,
                  ),
                ),
            ]),
          ),
        ),

        // ── INSTRUCTION + MODE TOGGLE ──────────────────────
        Positioned(
          top:   sz.height / 2 - frameH / 2 - 82,
          left:  0,
          right: 0,
          child: Column(children: [
            Text(
              _mode == ScanMode.entry
                  ? 'Placez le ticket d\'entrée dans le cadre'
                  : 'Placez le ticket de sortie dans le cadre',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            _buildModeToggle(),
          ]),
        ),

        // ── BARRE HAUT : Torche ────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _circleBtn(
                  icon: _torchOn
                      ? Icons.flashlight_on_rounded
                      : Icons.flashlight_off_rounded,
                  onTap: _toggleTorch,
                  active: _torchOn,
                ),
              ],
            ),
          ),
        ),

        // ── BARRE BAS : Galerie · Scan ─────────────────────
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 24,
          left:   0,
          right:  0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Galerie
              _bottomBtn(
                icon: Icons.photo_library_outlined,
                onTap: _openGallery,
                label: 'Galerie',
              ),
              // Bouton scan central
              GestureDetector(
                onTap: _isSubmitting ? null : () {
                  setState(() => _isScanning = true);
                  _scanCtrl.repeat(reverse: true);
                  HapticFeedback.mediumImpact();
                },
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: _isSubmitting
                        ? Colors.white30
                        : _kBlue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _kBlue.withOpacity(0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: _isSubmitting
                      ? const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      : const Icon(Icons.qr_code_scanner_rounded,
                          color: Colors.white, size: 30),
                ),
              ),
              // Historique des scans (à côté du bouton de scan)
              _bottomBtn(
                icon: Icons.history_rounded,
                onTap: _openHistorySheet,
                label: 'Historique',
              ),
            ],
          ),
        ),

      ]),
    );
  }

  // ════════════════════════════════════════════════════════
  //  WIDGETS INTERNES
  // ════════════════════════════════════════════════════════

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeChip('Entrée', ScanMode.entry),
          const SizedBox(width: 4),
          _modeChip('Sortie', ScanMode.exit),
        ],
      ),
    );
  }

  Widget _modeChip(String label, ScanMode mode) {
    final bool active = _mode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _mode = mode);
        HapticFeedback.selectionClick();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _kBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white54,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(Size sz, double fw, double fh) {
    final double cx = (sz.width - fw) / 2;
    final double cy = (sz.height - fh) / 2;
    final double opacity = 0.72;
    final Color c = Colors.black.withOpacity(opacity);

    return Stack(children: [
      // Top
      Positioned(top: 0, left: 0, right: 0, height: cy,
          child: Container(color: c)),
      // Bottom
      Positioned(top: cy + fh, left: 0, right: 0, bottom: 0,
          child: Container(color: c)),
      // Left
      Positioned(top: cy, left: 0, width: cx, height: fh,
          child: Container(color: c)),
      // Right
      Positioned(top: cy, right: 0, width: cx, height: fh,
          child: Container(color: c)),
    ]);
  }

  Widget _buildCorners(double w, double h) {
    const double len = 28;
    const double thick = 3.5;
    const double r = 12;
    final Color col = _kBlue;

    Widget corner(bool top, bool left) => Positioned(
      top:    top ? 0 : null,
      bottom: top ? null : 0,
      left:   left ? 0 : null,
      right:  left ? null : 0,
      child: SizedBox(
        width: len + r,
        height: len + r,
        child: CustomPaint(
          painter: _CornerPainter(
              top: top, left: left, thickness: thick,
              radius: r, color: col),
        ),
      ),
    );

    return Stack(children: [
      corner(true, true),
      corner(true, false),
      corner(false, true),
      corner(false, false),
    ]);
  }

  Widget _circleBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active
              ? _kBlue.withOpacity(0.8)
              : Colors.black.withOpacity(0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _bottomBtn({
    required IconData icon,
    required VoidCallback onTap,
    required String label,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: active
                  ? _kBlue.withOpacity(0.85)
                  : Colors.black.withOpacity(0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  CORNER PAINTER
// ════════════════════════════════════════════════════════════
class _CornerPainter extends CustomPainter {
  final bool  top, left;
  final double thickness, radius;
  final Color color;

  _CornerPainter({
    required this.top,
    required this.left,
    required this.thickness,
    required this.radius,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final Path path = Path();
    final double w = size.width;
    final double h = size.height;

    if (top && left) {
      path.moveTo(0, h);
      path.lineTo(0, radius);
      path.arcToPoint(Offset(radius, 0),
          radius: Radius.circular(radius), clockwise: true);
      path.lineTo(w, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(w - radius, 0);
      path.arcToPoint(Offset(w, radius),
          radius: Radius.circular(radius), clockwise: true);
      path.lineTo(w, h);
    } else if (!top && left) {
      path.moveTo(w, h);
      path.lineTo(radius, h);
      path.arcToPoint(Offset(0, h - radius),
          radius: Radius.circular(radius), clockwise: true);
      path.lineTo(0, 0);
    } else {
      path.moveTo(0, h);
      path.lineTo(w - radius, h);
      path.arcToPoint(Offset(w, h - radius),
          radius: Radius.circular(radius), clockwise: false);
      path.lineTo(w, 0);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

// ════════════════════════════════════════════════════════════
//  SCAN RESULT BOTTOM SHEET
// ════════════════════════════════════════════════════════════
class _ScanResultSheet extends StatelessWidget {
  final String     code;
  final bool       isValid;
  final String     message;
  final String?    ticketReference;
  final String?    qrImagePath;     // chemin vers .png du ticket généré Python
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _ScanResultSheet({
    required this.code,
    required this.isValid,
    required this.message,
    this.ticketReference,
    this.qrImagePath,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Poignée
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Icône résultat
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: isValid
                ? _kGreen.withOpacity(0.12)
                : _kRed.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isValid
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 40,
            color: isValid ? _kGreen : _kRed,
          ),
        ),
        const SizedBox(height: 14),

        Text(
          isValid ? 'Ticket validé !' : 'Ticket invalide',
          style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: _kDark),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 14, color: _kMid, height: 1.5),
        ),


        const SizedBox(height: 22),

        // Boutons
        if (isValid)
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Continuer',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          )
        else
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onClose,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE2ECF9)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Fermer',
                    style: TextStyle(color: _kDark, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Réessayer',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
      ]),
    );
  }
}
