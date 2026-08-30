import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Déclenche le téléchargement d'un fichier côté navigateur.
/// Zappart Pro est une application web — `dart:html` est disponible.
void downloadBytes(String filename, List<int> bytes, String mime) {
  final blob = html.Blob(<Object>[Uint8List.fromList(bytes)], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// Fichier texte (CSV…). Ajoute un BOM UTF-8 pour qu'Excel lise les accents.
void downloadText(String filename, String content, {String mime = 'text/csv'}) {
  downloadBytes(filename, utf8.encode('﻿$content'), mime);
}
