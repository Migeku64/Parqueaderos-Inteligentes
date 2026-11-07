import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Guarda, abre y comparte archivos generados por la app (reportes PDF, Excel y CSV).
class AppFiles {
  /// Carpeta donde se guardan los reportes en cada plataforma.
  ///  * Windows / macOS / Linux: la carpeta Descargas del usuario.
  ///  * Android: la carpeta de la app en el almacenamiento del teléfono
  ///    (Android/data/co.edu.umb.parqueadero_app/files/Reportes).
  ///  * iOS: Documentos de la app (visible en la app Archivos).
  static Future<Directory> reportsDir() async {
    Directory? base;
    try {
      if (Platform.isAndroid) {
        base = await getExternalStorageDirectory();
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        base = await getDownloadsDirectory();
      }
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = (Platform.isAndroid || Platform.isIOS) ? Directory('${base.path}${Platform.pathSeparator}Reportes') : base;
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Guarda los bytes con el nombre indicado y devuelve el archivo.
  static Future<File> save(String name, List<int> bytes) async {
    final dir = await reportsDir();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Abre el archivo con la aplicación predeterminada del dispositivo
  /// (visor de PDF, Excel, etc.). Devuelve false si no se pudo abrir.
  static Future<bool> open(File file) async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', file.path], runInShell: false);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [file.path]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [file.path]);
        return true;
      }
      final result = await OpenFilex.open(file.path);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  /// Abre el menú de compartir del sistema (WhatsApp, correo, Drive, etc.).
  static Future<void> share(File file, {String? text}) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: text));
  }

  /// En Linux no está disponible el menú de compartir.
  static bool get canShare => !Platform.isLinux;
}
