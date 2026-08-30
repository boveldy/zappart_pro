import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Déclenche le téléchargement d'un fichier texte côté navigateur.
/// Zappart Pro est une application web — `dart:html` est disponible.
void downloadText(String filename, String content, {String mime = 'text/csv'}) {
  final bytes = utf8.encode('﻿$content'); // BOM → Excel lit l'UTF-8
  final blob = html.Blob(<Object>[bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
