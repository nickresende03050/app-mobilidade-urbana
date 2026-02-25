// lib/services/permissao_service.dart

import 'package:permission_handler/permission_handler.dart';

class PermissaoService {

  /// Solicita localização em foreground.
  /// Deve ser chamado antes de iniciar o GPS.
  static Future<bool> solicitarLocalizacao() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  /// Solicita localização em background.
  /// DEVE ser chamado APÓS solicitarLocalizacao() já ter sido concedido.
  /// Android 11+ exige requisições separadas — nunca peça as duas juntas.
  static Future<bool> solicitarLocalizacaoBackground() async {
    // Só pede se foreground já foi concedido
    final foreground = await Permission.location.isGranted;
    if (!foreground) return false;

    final status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  /// Solicita permissão de notificações (Android 13+).
  /// Necessário para exibir a notificação do foreground service de GPS.
  static Future<void> solicitarNotificacoes() async {
    await Permission.notification.request();
  }

  /// Verifica e solicita tudo em sequência correta.
  /// Chame no initState da MapScreen antes de _iniciarGps().
  static Future<void> solicitarTodas() async {
    await solicitarNotificacoes();
    final locOk = await solicitarLocalizacao();
    if (locOk) await solicitarLocalizacaoBackground();
  }
}
