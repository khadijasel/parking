import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Couleurs de base (ton fichier original) ─────────────────────────────
  static const Color background = Colors.white;
  static const Color blue       = Color(0xFF4A90E2);
  static const Color green      = Color(0xFF2ECC71);
  static const Color textDark   = Color(0xFF1F2937);
  static const Color card       = Colors.white;

  // ── Nouvelles couleurs (Home / Profile / Reservation) ───────────────────
  static const Color pageBg     = Color(0xFFEAF1FB); // fond bleu pâle (home)
  static const Color circleBg   = Color(0xFFD6E6F7); // cercle illustration
  static const Color lockedBg   = Color(0xFFDDE8F7); // icônes verrouillées
  static const Color textMid    = Color(0xFF8A9BB5); // texte secondaire
  static const Color textLight  = Color(0xFFD0DDF0); // texte très léger
  static const Color border     = Color(0xFFE2ECF9); // bordures cartes
  static const Color rowBg      = Color(0xFFF4F7FC); // fond lignes profil
  static const Color orange     = Color(0xFFF5A623); // warning réservation
  static const Color orangeBg   = Color(0xFFFFF8EC); // fond warning
  static const Color redLogout  = Color(0xFFE53935); // déconnexion
  static const Color redBg      = Color(0xFFFFF0EE); // fond déconnexion
  static const Color success    = Color(0xFF27AE60); // confirmation verte
  static const Color timerBg    = Color(0xFFF0F2F5); // fond chiffres timer
  static const Color dark       = Color(0xFF1A1A2E); // titres foncés screens
}