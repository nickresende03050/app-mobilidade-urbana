// lib/screens/corrida/corrida_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';

class CorridaEmAndamento {
  final String id;
  final String status;
  final String origemEndereco;
  final String destinoEndereco;
  final double origemLat;
  final double origemLng;
  final double destinoLat;
  final double destinoLng;
  final double valorEstimado;
  final double? valorFinal;
  final double distanciaKm;
  final int tempoMin;
  final String? formaPagamento;
  final String nomePassageiro;
  final String? telefonePassageiro;
  final String passageiroId;

  const CorridaEmAndamento({
    required this.id,
    required this.status,
    required this.origemEndereco,
    required this.destinoEndereco,
    required this.origemLat,
    required this.origemLng,
    required this.destinoLat,
    required this.destinoLng,
    required this.valorEstimado,
    this.valorFinal,
    required this.distanciaKm,
    required this.tempoMin,
    this.formaPagamento,
    required this.nomePassageiro,
    this.telefonePassageiro,
    required this.passageiroId,
  });

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  factory CorridaEmAndamento.fromJson(Map<String, dynamic> json) {
    final perfil = json['perfis'] as Map<String, dynamic>? ?? {};
    return CorridaEmAndamento(
      id:                 json['id']                      as String,
      status:             json['status']                  as String?  ?? 'aceita',
      origemEndereco:     json['origem_endereco']         as String?  ?? '',
      destinoEndereco:    json['destino_endereco']        as String?  ?? '',
      origemLat:          _toDouble(json['origem_lat'])               ?? 0.0,
      origemLng:          _toDouble(json['origem_lng'])               ?? 0.0,
      destinoLat:         _toDouble(json['destino_lat'])              ?? 0.0,
      destinoLng:         _toDouble(json['destino_lng'])              ?? 0.0,
      valorEstimado:      _toDouble(json['valor_estimado'])           ?? 0.0,
      valorFinal:         _toDouble(json['valor_final']),
      distanciaKm:        _toDouble(json['distancia_estimada_km'])    ?? 0.0,
      tempoMin:           _toInt(json['tempo_estimado_min'])          ?? 0,
      formaPagamento:     json['forma_pagamento']         as String?,
      nomePassageiro:     perfil['nome_completo']         as String?  ?? 'Passageiro',
      telefonePassageiro: perfil['telefone']              as String?,
      passageiroId:       json['passageiro_id']           as String?  ?? '',
    );
  }
}

class CorridaScreen extends ConsumerStatefulWidget {
  final String corridaId;
  const CorridaScreen({super.key, required this.corridaId});

  @override
  ConsumerState<CorridaScreen> createState() => _CorridaScreenState();
}

class _CorridaScreenState extends ConsumerState<CorridaScreen> {
  final MapController _mapController = MapController();

  CorridaEmAndamento? _corrida;
  bool _isLoading     = true;
  bool _isAtualizando = false;

  RealtimeChannel? _corridaChannel;
  Timer? _timerDecorrido;
  Duration _tempoDecorrido = Duration.zero;

  @override
  void initState() {
    super.initState();
    _carregarCorrida();
    _escutarMudancasRealtime();
    _iniciarTimer();
  }

  Future<void> _carregarCorrida() async {
    try {
      final data = await Supabase.instance.client
          .from('corridas')
          .select(
            'id, status, origem_endereco, destino_endereco, '
            'origem_lat, origem_lng, destino_lat, destino_lng, '
            'valor_estimado, valor_final, distancia_estimada_km, '
            'tempo_estimado_min, forma_pagamento, passageiro_id, '
            'perfis!corridas_passageiro_id_fkey(nome_completo, telefone)',
          )
          .eq('id', widget.corridaId)
          .single();

      if (mounted) {
        setState(() {
          _corrida   = CorridaEmAndamento.fromJson(data);
          _isLoading = false;
        });
        _centralizarMapa();
      }
    } catch (e) {
      debugPrint('[Corrida] Erro ao carregar: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _escutarMudancasRealtime() {
    _corridaChannel = Supabase.instance.client
        .channel('corrida_${widget.corridaId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'corridas',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.corridaId,
          ),
          callback: (payload) {
            final novoStatus = payload.newRecord['status'] as String?;
            debugPrint('[Realtime] Status atualizado: $novoStatus');

            if (novoStatus == 'cancelada' && mounted) {
              _timerDecorrido?.cancel();
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => AlertDialog(
                  title: const Text('Corrida cancelada'),
                  content: const Text('O passageiro cancelou a corrida.'),
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.yellow,
                      ),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }

            if (mounted && _corrida != null && novoStatus != null) {
              setState(() {
                _corrida = CorridaEmAndamento(
                  id:                 _corrida!.id,
                  status:             novoStatus,
                  origemEndereco:     _corrida!.origemEndereco,
                  destinoEndereco:    _corrida!.destinoEndereco,
                  origemLat:          _corrida!.origemLat,
                  origemLng:          _corrida!.origemLng,
                  destinoLat:         _corrida!.destinoLat,
                  destinoLng:         _corrida!.destinoLng,
                  valorEstimado:      _corrida!.valorEstimado,
                  valorFinal:         _corrida!.valorFinal,
                  distanciaKm:        _corrida!.distanciaKm,
                  tempoMin:           _corrida!.tempoMin,
                  formaPagamento:     _corrida!.formaPagamento,
                  nomePassageiro:     _corrida!.nomePassageiro,
                  telefonePassageiro: _corrida!.telefonePassageiro,
                  passageiroId:       _corrida!.passageiroId,
                );
              });
            }
          },
        )
        .subscribe();
  }

  void _iniciarTimer() {
    _timerDecorrido = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _tempoDecorrido += const Duration(seconds: 1));
    });
  }

  void _centralizarMapa() {
    if (_corrida == null) return;
    final centerLat = (_corrida!.origemLat + _corrida!.destinoLat) / 2;
    final centerLng = (_corrida!.origemLng + _corrida!.destinoLng) / 2;
    try {
      _mapController.move(latlng.LatLng(centerLat, centerLng), 14);
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════
  // AÇÕES
  // ══════════════════════════════════════════════════════════
  Future<void> _atualizarStatus(String novoStatus) async {
    if (_isAtualizando) return;
    setState(() => _isAtualizando = true);

    final timestamps = {
      'motorista_chegou': 'motorista_chegou_em',
      'em_andamento':     'iniciada_em',
      'cancelada':        'cancelada_em',
    };

    try {
      final update = <String, dynamic>{'status': novoStatus};
      final tsField = timestamps[novoStatus];
      if (tsField != null) update[tsField] = DateTime.now().toIso8601String();

      await Supabase.instance.client
          .from('corridas')
          .update(update)
          .eq('id', widget.corridaId);

      if (mounted) {
        setState(() {
          _corrida = CorridaEmAndamento(
            id:                 _corrida!.id,
            status:             novoStatus,
            origemEndereco:     _corrida!.origemEndereco,
            destinoEndereco:    _corrida!.destinoEndereco,
            origemLat:          _corrida!.origemLat,
            origemLng:          _corrida!.origemLng,
            destinoLat:         _corrida!.destinoLat,
            destinoLng:         _corrida!.destinoLng,
            valorEstimado:      _corrida!.valorEstimado,
            valorFinal:         _corrida!.valorFinal,
            distanciaKm:        _corrida!.distanciaKm,
            tempoMin:           _corrida!.tempoMin,
            formaPagamento:     _corrida!.formaPagamento,
            nomePassageiro:     _corrida!.nomePassageiro,
            telefonePassageiro: _corrida!.telefonePassageiro,
            passageiroId:       _corrida!.passageiroId,
          );
        });
      }
      debugPrint('[Corrida] Status → $novoStatus');

    } catch (e) {
      debugPrint('[Corrida] Erro ao atualizar status: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao atualizar status. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAtualizando = false);
    }
  }

  Future<void> _cheguei()        => _atualizarStatus('motorista_chegou');
  Future<void> _iniciarCorrida() => _atualizarStatus('em_andamento');

  Future<void> _concluirCorrida() async {
    if (_isAtualizando) return;
    setState(() => _isAtualizando = true);

    try {
      final valorCreditado = await Supabase.instance.client
          .rpc('concluir_corrida', params: {
            'p_corrida_id': widget.corridaId,
            'p_nota':       5,
          });

      _timerDecorrido?.cancel();

      final valorFinal = (valorCreditado as num?)?.toDouble()
          ?? _corrida?.valorEstimado
          ?? 0.0;

      ref.read(motoristaProvider.notifier).atualizarSaldoLocal(
        (ref.read(motoristaProvider).asData?.value?.saldo ?? 0) + valorFinal,
      );

      if (mounted && _corrida != null) {
        setState(() {
          _corrida = CorridaEmAndamento(
            id:                 _corrida!.id,
            status:             'concluida',
            origemEndereco:     _corrida!.origemEndereco,
            destinoEndereco:    _corrida!.destinoEndereco,
            origemLat:          _corrida!.origemLat,
            origemLng:          _corrida!.origemLng,
            destinoLat:         _corrida!.destinoLat,
            destinoLng:         _corrida!.destinoLng,
            valorEstimado:      _corrida!.valorEstimado,
            valorFinal:         valorFinal,
            distanciaKm:        _corrida!.distanciaKm,
            tempoMin:           _corrida!.tempoMin,
            formaPagamento:     _corrida!.formaPagamento,
            nomePassageiro:     _corrida!.nomePassageiro,
            telefonePassageiro: _corrida!.telefonePassageiro,
            passageiroId:       _corrida!.passageiroId,
          );
        });
      }

      if (!mounted) return;
      _mostrarDialogAvaliacao();

    } catch (e) {
      debugPrint('[Corrida] Erro ao concluir: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao concluir corrida. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAtualizando = false);
    }
  }

  Future<void> _cancelarCorrida() async {
    final motivo = await _mostrarDialogMotivo();
    if (motivo == null) return;

    await _atualizarStatus('cancelada');

    if (motivo.isNotEmpty) {
      await Supabase.instance.client
          .from('corridas')
          .update({'motivo_cancelamento': motivo})
          .eq('id', widget.corridaId);
    }

    _timerDecorrido?.cancel();
    await ref.read(motoristaProvider.notifier).atualizarStatus(false);

    if (!mounted) return;
    Navigator.pop(context);
  }

  // ══════════════════════════════════════════════════════════
  // DIÁLOGOS
  // ══════════════════════════════════════════════════════════
  Future<String?> _mostrarDialogMotivo() async {
    String motivo = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar corrida'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Informe o motivo (opcional):'),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => motivo = v,
              decoration: const InputDecoration(
                hintText: 'Ex: Passageiro não apareceu',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, motivo),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar cancelamento'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogAvaliacao() {
    int nota = 5;
    final valorExibir = _corrida?.valorFinal ?? _corrida?.valorEstimado ?? 0.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Corrida concluída! �'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'R\$ ${valorExibir.toStringAsFixed(2).replaceAll('.', ',')}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tempo: ${_formatarTempo(_tempoDecorrido)}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              const Text('Avalie o passageiro:'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    icon: Icon(
                      i < nota ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                    onPressed: () => setDialogState(() => nota = i + 1),
                  );
                }),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                await Supabase.instance.client
                    .from('corridas')
                    .update({'nota_motorista_para_passageiro': nota})
                    .eq('id', widget.corridaId);

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.yellow,
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('FINALIZAR', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_corrida == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.yellow,
          title: const Text('Corrida'),
        ),
        body: const Center(child: Text('Erro ao carregar corrida.')),
      );
    }

    final corrida    = _corrida!;
    final origemPos  = latlng.LatLng(corrida.origemLat,  corrida.origemLng);
    final destinoPos = latlng.LatLng(corrida.destinoLat, corrida.destinoLng);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: latlng.LatLng(
                (corrida.origemLat + corrida.destinoLat) / 2,
                (corrida.origemLng + corrida.destinoLng) / 2,
              ),
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                // ✅ Sem subdomains — URL direta recomendada pelo OSM
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mototaxi.sjdr.motoristaapp',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [origemPos, destinoPos],
                    strokeWidth: 4,
                    color: Colors.blue,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: origemPos,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.trip_origin,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  Marker(
                    point: destinoPos,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.location_on,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ],
          ),

          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.yellow),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _corStatus(corrida.status),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Text(
                        _labelStatus(corrida.status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatarTempo(_tempoDecorrido),
                        style: const TextStyle(
                          color: Colors.yellow,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildCardInferior(corrida),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // CARD INFERIOR
  // ══════════════════════════════════════════════════════════
  Widget _buildCardInferior(CorridaEmAndamento corrida) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 20, spreadRadius: 2),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[200],
                radius: 24,
                child: const Icon(Icons.person, color: Colors.grey, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      corrida.nomePassageiro,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    if (corrida.telefonePassageiro != null)
                      Text(
                        corrida.telefonePassageiro!,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'R\$ ${corrida.valorEstimado.toStringAsFixed(2).replaceAll('.', ',')}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  if (corrida.formaPagamento != null)
                    Text(
                      corrida.formaPagamento!,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          _buildLinhaEndereco(
            icon: Icons.trip_origin,
            cor: Colors.green,
            texto: corrida.origemEndereco,
            label: 'Origem',
          ),
          const SizedBox(height: 10),
          _buildLinhaEndereco(
            icon: Icons.location_on,
            cor: Colors.red,
            texto: corrida.destinoEndereco,
            label: 'Destino',
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetrica(
                icon: Icons.straighten,
                valor: '${corrida.distanciaKm.toStringAsFixed(1)} km',
                label: 'Distância',
              ),
              _buildMetrica(
                icon: Icons.access_time,
                valor: '${corrida.tempoMin} min',
                label: 'Estimado',
              ),
              _buildMetrica(
                icon: Icons.timer,
                valor: _formatarTempo(_tempoDecorrido),
                label: 'Decorrido',
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildBotoesAcao(corrida),
        ],
      ),
    );
  }

  Widget _buildBotoesAcao(CorridaEmAndamento corrida) {
    switch (corrida.status) {
      case 'aceita':
        return Column(
          children: [
            _botaoPrimario(
              label: '� CHEGUEI AO PASSAGEIRO',
              cor: Colors.blue,
              onTap: _isAtualizando ? null : _cheguei,
            ),
            const SizedBox(height: 10),
            _botaoSecundario(
              label: 'Cancelar corrida',
              onTap: _isAtualizando ? null : _cancelarCorrida,
            ),
          ],
        );
      case 'motorista_chegou':
        return Column(
          children: [
            _botaoPrimario(
              label: '� INICIAR CORRIDA',
              cor: Colors.orange,
              onTap: _isAtualizando ? null : _iniciarCorrida,
            ),
            const SizedBox(height: 10),
            _botaoSecundario(
              label: 'Cancelar corrida',
              onTap: _isAtualizando ? null : _cancelarCorrida,
            ),
          ],
        );
      case 'em_andamento':
        return _botaoPrimario(
          label: '✅ CONCLUIR CORRIDA',
          cor: Colors.green,
          onTap: _isAtualizando ? null : _concluirCorrida,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _botaoPrimario({
    required String label,
    required Color cor,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: cor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: _isAtualizando
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _botaoSecundario({
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildLinhaEndereco({
    required IconData icon,
    required Color cor,
    required String texto,
    required String label,
  }) {
    return Row(
      children: [
        Icon(icon, color: cor, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Text(texto,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetrica({
    required IconData icon,
    required String valor,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey, size: 20),
        const SizedBox(height: 4),
        Text(valor,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  String _formatarTempo(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _labelStatus(String status) {
    switch (status) {
      case 'aceita':           return '�️ A caminho';
      case 'motorista_chegou': return '� Aguardando passageiro';
      case 'em_andamento':     return '� Em andamento';
      case 'concluida':        return '✅ Concluída';
      case 'cancelada':        return '❌ Cancelada';
      default:                 return status;
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'aceita':           return Colors.blue;
      case 'motorista_chegou': return Colors.orange;
      case 'em_andamento':     return Colors.green;
      case 'concluida':        return Colors.teal;
      case 'cancelada':        return Colors.red;
      default:                 return Colors.grey;
    }
  }

  @override
  void dispose() {
    _timerDecorrido?.cancel();
    _corridaChannel?.unsubscribe();
    _mapController.dispose();
    super.dispose();
  }
}
