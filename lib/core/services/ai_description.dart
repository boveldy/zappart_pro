import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:flutter/foundation.dart';

/// Génération des textes d'une annonce via **Firebase Vertex AI (Gemini)** :
/// une **accroche** courte (sous-titre affiché sur les cartes) + une
/// **description** longue (paragraphe de la page annonce), en un seul appel.
///
/// Reprend l'agent « Redacteur Zappart » de l'admin. Aucune clé API : l'accès
/// est authentifié par Firebase. Retourne `null` en cas d'échec (loggé, jamais
/// throw).
class AiDescription {
  /// Dernière erreur rencontrée (diagnostic — affichée temporairement dans l'UI,
  /// car un build release n'expose pas les `debugPrint`). À retirer une fois la
  /// génération IA validée en conditions réelles.
  static String? lastError;

  static const _system =
      "Tu es l'expert rédacteur de l'agence Zappart à Dakar. Ton style est "
      "moderne, épuré et haut de gamme. Pas d'emojis. Pas de listes à puces. "
      "Tu produis une accroche courte et une description en paragraphes fluides. "
      "N'invente AUCUNE caractéristique : base-toi UNIQUEMENT sur les "
      "informations fournies. Adapte naturellement le ton au type de bien et à "
      "ses commodités.";

  /// Génère (ou améliore) l'accroche ET la description.
  /// [accrocheExistante] / [descriptionExistante] : si fournies, l'IA les améliore.
  static Future<({String accroche, String description})?> generer({
    required bool journalier,
    required String type,
    required String quartier,
    required String cite,
    required int nbpiece,
    required int nbchambre,
    required int nbsalon,
    required int nbbain,
    required String emplacement,
    required List<String> comodites,
    String? accrocheExistante,
    String? descriptionExistante,
  }) async {
    lastError = null;
    try {
      final model = FirebaseVertexAI.instanceFor(auth: FirebaseAuth.instance)
          .generativeModel(
        model: 'gemini-2.5-flash',
        systemInstruction: Content.system(_system),
        generationConfig: GenerationConfig(
          temperature: 1,
          topP: 0.95,
          // ⚠️ gemini-2.5-flash RAISONNE avant de répondre, et ces tokens de
          // réflexion sont décomptés de `maxOutputTokens`. Avec 1024, le budget
          // était épuisé pendant la réflexion → la réponse était COUPÉE en plein
          // JSON (`FormatException: Unexpected end of input`). Ne pas redescendre.
          maxOutputTokens: 4096,
          responseMimeType: 'application/json',
          // Sortie structurée : le modèle ne peut pas répondre autre chose.
          responseSchema: Schema.object(
            properties: {
              'accroche': Schema.string(),
              'description': Schema.string(),
            },
          ),
        ),
      );

      final duree =
          journalier ? 'court séjour (à la nuitée)' : 'longue durée (au mois)';

      final buf = StringBuffer()
        ..writeln('DURÉE : $duree')
        ..writeln('Type de logement : $type')
        ..writeln(
            'Quartier : $quartier${cite.trim().isNotEmpty ? ' — ${cite.trim()}' : ''}')
        ..writeln('Nombre de pièces : $nbpiece')
        ..writeln(
            'Chambres : $nbchambre · Salons : $nbsalon · Salles de bain : $nbbain');
      if (emplacement.isNotEmpty) buf.writeln('Emplacement : $emplacement');
      if (comodites.isNotEmpty) {
        buf.writeln('Commodités : ${comodites.join(', ')}');
      }
      if (accrocheExistante != null && accrocheExistante.trim().isNotEmpty) {
        buf.writeln(
            'Accroche existante à améliorer : "${accrocheExistante.trim()}"');
      }
      if (descriptionExistante != null &&
          descriptionExistante.trim().isNotEmpty) {
        buf.writeln(
            'Description existante à améliorer : "${descriptionExistante.trim()}"');
      }
      buf.writeln(
          'Réponds UNIQUEMENT en JSON valide de la forme : '
          '{"accroche": "...", "description": "..."}. '
          '"accroche" = une phrase courte et attractive (12 mots maximum), sans emojis. '
          '"description" = un paragraphe fluide (5 lignes maximum), sans emojis.');

      final response =
          await model.generateContent([Content.text(buf.toString())]);
      final raw = response.text?.trim();
      if (raw == null || raw.isEmpty) {
        lastError = 'réponse vide du modèle';
        return null;
      }

      final parsed = _parse(raw);
      if (parsed == null) {
        lastError = 'réponse illisible du modèle';
        return null;
      }
      return parsed;
    } catch (e) {
      lastError = '${e.runtimeType} — $e';
      debugPrint('AiDescription.generer échec : $e');
      return null;
    }
  }

  /// Lit la réponse du modèle. Si le JSON est valide → décodage normal ; s'il
  /// est TRONQUÉ (réponse coupée), on récupère quand même ce qui a été écrit
  /// plutôt que de tout jeter : le texte reste éditable par l'utilisateur.
  static ({String accroche, String description})? _parse(String raw) {
    final t = _stripFences(raw);
    try {
      final json = jsonDecode(t) as Map<String, dynamic>;
      final a = (json['accroche'] ?? '').toString().trim();
      final d = (json['description'] ?? '').toString().trim();
      if (a.isEmpty && d.isEmpty) return null;
      return (accroche: a, description: d);
    } catch (_) {
      return _recuperer(t);
    }
  }

  /// Extrait « accroche » et « description » d'un JSON incomplet.
  ///
  /// La valeur est lue jusqu'au guillemet fermant… ou jusqu'à la fin du texte
  /// s'il n'y en a pas (réponse coupée) — c'est tout l'intérêt.
  static ({String accroche, String description})? _recuperer(String t) {
    String champ(String nom) {
      final m = RegExp('"$nom"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)').firstMatch(t);
      if (m == null) return '';
      return m
          .group(1)!
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\\', r'\')
          .trim();
    }

    final a = champ('accroche');
    final d = champ('description');
    if (a.isEmpty && d.isEmpty) return null;
    return (accroche: a, description: d);
  }

  /// Retire d'éventuelles clôtures markdown ```json … ``` autour du JSON.
  static String _stripFences(String s) {
    var t = s.trim();
    if (t.startsWith('```')) {
      t = t
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '')
          .replaceFirst(RegExp(r'\n?```$'), '');
    }
    return t.trim();
  }
}
