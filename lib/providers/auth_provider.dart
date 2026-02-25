// lib/providers/auth_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/motorista.dart';

// ============================================================
// 1. STREAM DE AUTENTICAÇÃO
// Escuta login/logout em tempo real e dispara rebuild nos
// providers que o observam via ref.watch()
// ============================================================
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// ============================================================
// 2. NOTIFIER PRINCIPAL
// Gerencia o estado do motorista logado com suporte a:
//  - Busca reativa (reage ao login/logout)
//  - Atualização otimista de status (com rollback em erro)
//  - Atualização de localização via WKT (PostGIS)
//  - Logout seguro (offline antes de sair)
// ============================================================
class MotoristaNotifier extends AsyncNotifier<Motorista?> {

  // ----------------------------------------------------------
  // build() é chamado automaticamente:
  //  - Na inicialização do app
  //  - Toda vez que authStateProvider mudar (login/logout)
  // ----------------------------------------------------------
  @override
  Future<Motorista?> build() async {
    // Observa o auth — qualquer mudança reinvoca este build()
    ref.watch(authStateProvider);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    return _buscarMotorista(user.id);
  }

  // ----------------------------------------------------------
  // Busca motorista fazendo JOIN correto:
  // motoristas (perfil_id) → perfis (id)
  // Retorna null se não for motorista ou estiver bloqueado.
  // ----------------------------------------------------------
  Future<Motorista?> _buscarMotorista(String userId) async {
    try {
      // Query na tabela MOTORISTAS com JOIN em PERFIS
      // Retorna: { perfil_id, saldo, status, ..., perfis: { id, nome_completo, ... } }
      final response = await Supabase.instance.client
          .from('motoristas')
          .select('*, perfis(*)')
          .eq('perfil_id', userId)
          .single();

      final perfil = response['perfis'] as Map<String, dynamic>?;

      // Segurança: bloqueia passageiros de acessarem o app do motorista
      if (perfil == null || perfil['tipo_usuario'] != 'motorista') {
        debugPrint('[Auth] Acesso negado: tipo=${perfil?['tipo_usuario']}');
        await Supabase.instance.client.auth.signOut();
        return null;
      }

      // Segurança: bloqueia contas desativadas pelo admin
      if (perfil['ativo'] == false) {
        debugPrint('[Auth] Conta desativada: ativo=false');
        await Supabase.instance.client.auth.signOut();
        return null;
      }

      return Motorista.fromJson(response);

    } on PostgrestException catch (e) {
      // Código PGRST116 = nenhuma linha encontrada (.single())
      if (e.code == 'PGRST116') {
        debugPrint('[Auth] Motorista não cadastrado no banco: userId=$userId');
      } else {
        debugPrint('[Auth] PostgrestException: ${e.message} (code: ${e.code})');
      }
      return null;
    } catch (e) {
      debugPrint('[Auth] Erro inesperado: $e');
      return null;
    }
  }

  // ----------------------------------------------------------
  // Alterna status ONLINE / OFFLINE
  // Usa atualização otimista: atualiza a UI imediatamente
  // e faz rollback se o Supabase retornar erro.
  // ----------------------------------------------------------
  Future<void> atualizarStatus(bool online) async {
    final motoristaAtual = state.asData?.value;
    if (motoristaAtual == null) return;

    // 1. Atualiza UI imediatamente (otimista)
    state = AsyncData(motoristaAtual.copyWith(online: online));

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client
          .from('motoristas')
          .update({
            'status': online ? 'online' : 'offline',
            'ultima_atualizacao': DateTime.now().toIso8601String(),
          })
          .eq('perfil_id', userId);

      debugPrint('[Status] → ${online ? "ONLINE" : "OFFLINE"}');

    } catch (e) {
      // 2. Rollback: desfaz a mudança na UI
      state = AsyncData(motoristaAtual.copyWith(online: !online));
      debugPrint('[Status] Erro — revertendo: $e');
      rethrow; // HomeScreen vai capturar e exibir o SnackBar
    }
  }

  // ----------------------------------------------------------
  // Atualiza localização no PostGIS usando WKT.
  // WKT ('POINT(lng lat)') é o único formato garantido
  // pelo PostgREST para colunas GEOGRAPHY(POINT, 4326).
  // NÃO propaga erro para UI — falha silenciosa aceitável
  // para GPS (próxima atualização virá em segundos).
  // ----------------------------------------------------------
  Future<void> atualizarLocalizacao(
    double latitude,
    double longitude, {
    double? direcao,
  }) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // IMPORTANTE: PostGIS usa ordem (longitude, latitude) no WKT
      await Supabase.instance.client
          .from('motoristas')
          .update({
            'localizacao_atual': 'POINT($longitude $latitude)',
            if (direcao != null) 'direcao_atual': direcao,
            'ultima_atualizacao': DateTime.now().toIso8601String(),
          })
          .eq('perfil_id', userId);

      // Atualiza estado local sem fazer nova query ao banco
      final motorista = state.asData?.value;
      if (motorista != null) {
        state = AsyncData(
          motorista.copyWith(
            latitude: latitude,
            longitude: longitude,
            direcaoAtual: direcao,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Localização] Falha silenciosa: $e');
    }
  }

  // ----------------------------------------------------------
  // Atualiza saldo localmente após conclusão de corrida.
  // Evita nova query ao banco — usa o valor retornado
  // pela função RPC ou pelo payload do Realtime.
  // ----------------------------------------------------------
  void atualizarSaldoLocal(double novoSaldo) {
    final motorista = state.asData?.value;
    if (motorista == null) return;
    state = AsyncData(motorista.copyWith(saldo: novoSaldo));
    debugPrint('[Saldo] Atualizado localmente → R\$ $novoSaldo');
  }

  // ----------------------------------------------------------
  // Recarrega dados completos do banco.
  // Use após: concluir corrida, atualizar documentos, etc.
  // ----------------------------------------------------------
  Future<void> recarregar() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _buscarMotorista(userId));
    debugPrint('[Auth] Dados recarregados do banco');
  }

  // ----------------------------------------------------------
  // Logout seguro: define status offline ANTES de sair.
  // Evita que o motorista fique visível para passageiros
  // após fechar o app.
  // ----------------------------------------------------------
  Future<void> logout() async {
    try {
      await atualizarStatus(false);
    } catch (_) {
      // Continua com logout mesmo se o update falhar
      debugPrint('[Auth] Falha ao definir offline — prosseguindo com logout');
    } finally {
      await Supabase.instance.client.auth.signOut();
      debugPrint('[Auth] Logout concluído');
    }
  }
}

// ============================================================
// 3. PROVIDER EXPOSTO PARA O APP
// Use ref.watch(motoristaProvider) para dados reativos
// Use ref.read(motoristaProvider.notifier) para chamar métodos
// ============================================================
final motoristaProvider =
    AsyncNotifierProvider<MotoristaNotifier, Motorista?>(
  MotoristaNotifier.new,
);
