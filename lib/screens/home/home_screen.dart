// lib/screens/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/motorista.dart';
import '../../providers/auth_provider.dart';
import '../map/map_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isOnline = false;
  bool _isTogglingStatus = false;

  final _formatadorMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final motorista = ref.read(motoristaProvider).asData?.value;
      if (motorista != null && mounted) {
        setState(() => _isOnline = motorista.online);
      }
    });
  }

  Future<void> _toggleStatus(Motorista motorista) async {
    if (!motorista.podeReceberCorridas) {
      _mostrarAvisoDocumentos();
      return;
    }
    if (_isTogglingStatus) return;
    setState(() => _isTogglingStatus = true);

    final novoStatus = !_isOnline;
    setState(() => _isOnline = novoStatus);

    try {
      await ref.read(motoristaProvider.notifier).atualizarStatus(novoStatus);
    } catch (_) {
      if (mounted) setState(() => _isOnline = !novoStatus);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao atualizar status. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isTogglingStatus = false);
    }
  }

  Future<void> _logout() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do app'),
        content: const Text('Você será marcado como offline e desconectado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await ref.read(motoristaProvider.notifier).logout();
  }

  void _mostrarAvisoDocumentos() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text('Documentos pendentes'),
          ],
        ),
        content: const Text(
          'Seus documentos ainda estão em análise.\n\n'
          'Você poderá se colocar online assim que forem aprovados.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.yellow,
            ),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final motoristaAsync = ref.watch(motoristaProvider);

    ref.listen<AsyncValue<Motorista?>>(motoristaProvider, (_, next) {
      final motorista = next.asData?.value;
      if (motorista != null && mounted) {
        setState(() => _isOnline = motorista.online);
      }
    });

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.yellow,
        title: const Text('MotoTaxi Motorista'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: _logout,
          ),
        ],
      ),
      body: motoristaAsync.when(
        data: (motorista) {
          if (motorista == null) return _buildErroAcesso();
          return _buildConteudo(motorista);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildErroGenerico(error),
      ),
    );
  }

  // ── Conteúdo principal ─────────────────────────────────────
  Widget _buildConteudo(Motorista motorista) {
    return RefreshIndicator(
      onRefresh: () => ref.read(motoristaProvider.notifier).recarregar(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!motorista.documentosVerificados) _buildBannerDocumentos(),
            _buildStatusCard(motorista),
            const SizedBox(height: 16),
            _buildSaldoCard(motorista.saldo),
            const SizedBox(height: 16),
            _buildEstatisticasCard(motorista),
            const SizedBox(height: 16),
            _buildMotoCard(motorista),
            const SizedBox(height: 16),
            _buildBotaoMapa(),
          ],
        ),
      ),
    );
  }

  // ── Banner documentos ─────────────────────────────────────
  Widget _buildBannerDocumentos() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: Colors.orange),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Documentos em análise — você não pode receber corridas ainda.',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card status ───────────────────────────────────────────
  Widget _buildStatusCard(Motorista motorista) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Olá, ${motorista.nome.split(' ').first}!',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isOnline ? 'ONLINE' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _isOnline ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
                _isTogglingStatus
                    ? const SizedBox(
                        width: 48,
                        height: 24,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Switch(
                        value: _isOnline,
                        onChanged: motorista.podeReceberCorridas
                            ? (_) => _toggleStatus(motorista)
                            : (_) => _mostrarAvisoDocumentos(),
                        // ✅ activeColor → activeThumbColor (corrigido)
                        activeThumbColor: Colors.green,
                        inactiveThumbColor: Colors.red,
                      ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _isOnline
                  ? 'Você está recebendo chamadas de corrida'
                  : motorista.podeReceberCorridas
                      ? 'Ative para receber chamadas de corrida'
                      : 'Aguarde a aprovação dos seus documentos',
              style: TextStyle(
                color: _isOnline
                    ? Colors.green[700]
                    : motorista.podeReceberCorridas
                        ? Colors.grey[600]
                        : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card saldo ────────────────────────────────────────────
  Widget _buildSaldoCard(double saldo) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_balance_wallet, color: Colors.yellow),
                SizedBox(width: 8),
                Text(
                  'Seu Saldo',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _formatadorMoeda.format(saldo),
              style: const TextStyle(
                color: Colors.yellow,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: saldo > 0 ? () {} : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('SACAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.grey[800],
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card estatísticas ─────────────────────────────────────
  Widget _buildEstatisticasCard(Motorista motorista) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estatísticas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildItemEstatistica(
                  icon: Icons.star,
                  valor: motorista.avaliacao.toStringAsFixed(1),
                  label: 'Avaliação',
                  cor: Colors.amber,
                ),
                _buildItemEstatistica(
                  icon: Icons.motorcycle,
                  valor: motorista.totalCorridas.toString(),
                  label: 'Corridas',
                  cor: Colors.blue,
                ),
                _buildItemEstatistica(
                  icon: Icons.verified_user,
                  valor: motorista.documentosVerificados ? 'OK' : 'Pendente',
                  label: 'Documentos',
                  cor: motorista.documentosVerificados
                      ? Colors.green
                      : Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemEstatistica({
    required IconData icon,
    required String valor,
    required String label,
    required Color cor,
  }) {
    return Column(
      children: [
        Icon(icon, color: cor, size: 32),
        const SizedBox(height: 8),
        Text(
          valor,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  // ── Card moto ─────────────────────────────────────────────
  Widget _buildMotoCard(Motorista motorista) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.yellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.motorcycle, color: Colors.black, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    motorista.descricaoMoto,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (motorista.placaMoto != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Placa: ${motorista.placaMoto}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Botão mapa ────────────────────────────────────────────
  Widget _buildBotaoMapa() {
    return ElevatedButton.icon(
      onPressed: _isOnline
          ? () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              )
          : null,
      icon: const Icon(Icons.map),
      label: const Text('VER MAPA DE CORRIDAS',
          style: TextStyle(fontSize: 16)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _isOnline ? Colors.green : Colors.grey,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey[400],
        disabledForegroundColor: Colors.white60,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // ── Tela erro acesso ──────────────────────────────────────
  Widget _buildErroAcesso() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Acesso não autorizado',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta conta não está cadastrada como motorista.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () =>
                  ref.read(motoristaProvider.notifier).logout(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.yellow,
              ),
              child: const Text('Sair'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tela erro genérico ────────────────────────────────────
  Widget _buildErroGenerico(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Erro ao carregar dados',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(motoristaProvider.notifier).recarregar(),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.yellow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
