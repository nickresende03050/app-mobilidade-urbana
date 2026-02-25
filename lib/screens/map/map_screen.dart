// lib/screens/map/map_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../corrida/corrida_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();

  latlng.LatLng? _currentPosition;
  bool _isLoadingGps = true;
  Map<String, dynamic>? _notificacaoAtiva;
  bool _isRespondendo = false;

  StreamSubscription<Position>? _gpsStream;
  RealtimeChannel? _corridaChannel;
  bool _canalIniciado = false;

  @override
  void initState() {
    super.initState();
    _iniciarGps();
    final motorista = ref.read(motoristaProvider).asData?.value;
    if (motorista != null) {
      _iniciarCanalRealtime(motorista.id);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ref.listenManual(motoristaProvider, (previous, next) {
      final motorista = next.asData?.value;
      if (motorista != null && !_canalIniciado) {
        _iniciarCanalRealtime(motorista.id);
      }
    });
  }

  // ══════════════════════════════════════════════════════════
  // GPS CONTÍNUO
  // ══════════════════════════════════════════════════════════
  Future<void> _iniciarGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Serviço de localização desativado no dispositivo');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[GPS] Permissão negada permanentemente — abrindo configurações');
        await Geolocator.openAppSettings();
        return;
      }

      if (permission == LocationPermission.denied) {
        throw Exception('Permissão de localização negada');
      }

      final posicaoInicial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _atualizarPosicao(posicaoInicial);

      _gpsStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        _atualizarPosicao,
        onError: (e) => debugPrint('[GPS] Erro no stream: $e'),
        cancelOnError: false,
      );

    } catch (e) {
      debugPrint('[GPS] Erro: $e');
      if (mounted) {
        setState(() {
          _currentPosition = const latlng.LatLng(-21.1356, -44.2617);
          _isLoadingGps = false;
        });
      }
    }
  }

  void _atualizarPosicao(Position position) {
    final novaPos = latlng.LatLng(position.latitude, position.longitude);

    if (mounted) {
      setState(() {
        _currentPosition = novaPos;
        _isLoadingGps = false;
      });
      try {
        _mapController.move(novaPos, _mapController.camera.zoom);
      } catch (_) {}
    }

    ref.read(motoristaProvider.notifier).atualizarLocalizacao(
      position.latitude,
      position.longitude,
      direcao: position.heading,
    );

    debugPrint(
      '[GPS] lat=${position.latitude.toStringAsFixed(5)}, '
      'lng=${position.longitude.toStringAsFixed(5)}, '
      'heading=${position.heading.toStringAsFixed(1)}°',
    );
  }

  // ══════════════════════════════════════════════════════════
  // REALTIME
  // ══════════════════════════════════════════════════════════
  void _iniciarCanalRealtime(String motoristaId) {
    if (_canalIniciado) return;
    _canalIniciado = true;

    _corridaChannel = Supabase.instance.client
        .channel('notificacoes_$motoristaId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificacoes_corrida',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'motorista_id',
            value: motoristaId,
          ),
          callback: (payload) async {
            final notificacao = payload.newRecord;
            debugPrint('[Realtime] Nova notificação: $notificacao');

            final expiraEm = DateTime.tryParse(
              notificacao['expira_em'] as String? ?? '',
            );
            if (expiraEm == null || expiraEm.isBefore(DateTime.now())) {
              debugPrint('[Realtime] Notificação expirada — ignorando');
              return;
            }

            if (notificacao['aceita'] == true ||
                notificacao['recusada'] == true) return;

            if (_notificacaoAtiva != null) return;

            await _carregarDadosCorrida(notificacao);
          },
        )
        .subscribe((status, error) {
          debugPrint('[Realtime] Status: $status ${error ?? ''}');
        });

    debugPrint('[Realtime] Canal iniciado para motorista $motoristaId');
  }

  Future<void> _carregarDadosCorrida(
    Map<String, dynamic> notificacao,
  ) async {
    try {
      final corridaId = notificacao['corrida_id'] as String?;
      if (corridaId == null) return;

      final corrida = await Supabase.instance.client
          .from('corridas')
          .select(
            'id, origem_endereco, destino_endereco, '
            'valor_estimado, distancia_estimada_km, tempo_estimado_min, '
            'passageiro_id, perfis!corridas_passageiro_id_fkey(nome_completo)',
          )
          .eq('id', corridaId)
          .single();

      if (mounted) {
        setState(() {
          _notificacaoAtiva = {
            ...notificacao,
            'corrida': corrida,
          };
        });
        _mostrarCardCorrida();
      }
    } catch (e) {
      debugPrint('[Realtime] Erro ao carregar corrida: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  // ACEITAR CORRIDA
  // ══════════════════════════════════════════════════════════
  Future<void> _aceitarCorrida() async {
    if (_notificacaoAtiva == null || _isRespondendo) return;
    setState(() => _isRespondendo = true);

    try {
      final notificacaoId = _notificacaoAtiva!['id'] as String;
      final corridaId     = _notificacaoAtiva!['corrida_id'] as String;

      final aceito = await Supabase.instance.client
          .rpc('aceitar_corrida', params: {
            'p_corrida_id':     corridaId,
            'p_notificacao_id': notificacaoId,
          });

      if (!context.mounted) return;
      Navigator.pop(context);

      setState(() {
        _notificacaoAtiva = null;
        _isRespondendo    = false;
      });

      if (aceito == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CorridaScreen(corridaId: corridaId),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚡ Corrida já foi aceita por outro motorista.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }

      debugPrint('[Corrida] aceitar_corrida() → $aceito');

    } catch (e) {
      debugPrint('[Corrida] Erro ao aceitar: $e');
      if (mounted) setState(() => _isRespondendo = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao aceitar corrida. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════
  // RECUSAR CORRIDA
  // ══════════════════════════════════════════════════════════
  Future<void> _recusarCorrida() async {
    if (_notificacaoAtiva == null || _isRespondendo) return;
    setState(() => _isRespondendo = true);

    try {
      final notificacaoId = _notificacaoAtiva!['id'] as String;

      await Supabase.instance.client
          .from('notificacoes_corrida')
          .update({'recusada': true})
          .eq('id', notificacaoId);

      if (!context.mounted) return;
      Navigator.pop(context);

      setState(() {
        _notificacaoAtiva = null;
        _isRespondendo    = false;
      });

      debugPrint('[Corrida] Recusada: $notificacaoId');

    } catch (e) {
      debugPrint('[Corrida] Erro ao recusar: $e');
      if (mounted) setState(() => _isRespondendo = false);
    }
  }

  void _mostrarCardCorrida() {
    if (_notificacaoAtiva == null || !mounted) return;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _buildCardCorrida(),
    ).then((_) {
      if (mounted) {
        setState(() {
          _notificacaoAtiva = null;
          _isRespondendo    = false;
        });
      }
    });
  }

  // ══════════════════════════════════════════════════════════
  // BUILD PRINCIPAL
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final pos = _currentPosition;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.yellow,
        title: Row(
          children: [
            const Text('Mapa de Corridas'),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Centralizar',
            onPressed: () {
              if (pos != null) _mapController.move(pos, 16);
            },
          ),
        ],
      ),
      body: _isLoadingGps || pos == null
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Obtendo localização GPS...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: pos,
                initialZoom: 16,
              ),
              children: [
                TileLayer(
                  // ✅ Sem subdomains — URL direta recomendada pelo OSM
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.mototaxi.sjdr.motoristaapp',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pos,
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.yellow, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.motorcycle,
                          color: Colors.yellow,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'centralizar_mapa',
        backgroundColor: Colors.black,
        onPressed: () {
          if (pos != null) _mapController.move(pos, 16);
        },
        child: const Icon(Icons.my_location, color: Colors.yellow),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // CARD DE NOVA CORRIDA
  // ══════════════════════════════════════════════════════════
  Widget _buildCardCorrida() {
    final notificacao = _notificacaoAtiva;
    if (notificacao == null) return const SizedBox.shrink();

    final corrida        = notificacao['corrida']            as Map<String, dynamic>? ?? {};
    final passageiro     = corrida['perfis']                 as Map<String, dynamic>? ?? {};
    final distanciaKm    = (notificacao['distancia_km'] as num?)?.toDouble()           ?? 0.0;
    final valorEstimado  = (corrida['valor_estimado']   as num?)?.toDouble()            ?? 0.0;
    final tempoMin       =  corrida['tempo_estimado_min'] as int?                       ?? 0;
    final origem         =  corrida['origem_endereco']  as String?                      ?? 'Origem não informada';
    final destino        =  corrida['destino_endereco'] as String?                      ?? 'Destino não informado';
    final nomePassageiro =  passageiro['nome_completo'] as String?                      ?? 'Passageiro';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_active,
                    color: Colors.green, size: 32),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '�️ Nova Corrida!',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Responda antes que expire',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          _buildLinhaInfo(icon: Icons.person, texto: nomePassageiro),
          const SizedBox(height: 10),
          _buildLinhaInfo(icon: Icons.trip_origin, texto: origem, cor: Colors.green),
          const SizedBox(height: 10),
          _buildLinhaInfo(icon: Icons.location_on, texto: destino, cor: Colors.red),
          const Divider(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetrica(
                label: 'Distância',
                valor: '${distanciaKm.toStringAsFixed(1)} km',
                icon: Icons.straighten,
              ),
              _buildMetrica(
                label: 'Tempo est.',
                valor: '$tempoMin min',
                icon: Icons.access_time,
              ),
              _buildMetrica(
                label: 'Valor',
                valor: 'R\$ ${valorEstimado.toStringAsFixed(2).replaceAll('.', ',')}',
                icon: Icons.attach_money,
                destaque: true,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isRespondendo ? null : _recusarCorrida,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('RECUSAR',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isRespondendo ? null : _aceitarCorrida,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isRespondendo
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('ACEITAR',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLinhaInfo({
    required IconData icon,
    required String texto,
    Color? cor,
  }) {
    return Row(
      children: [
        Icon(icon, color: cor ?? Colors.grey, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(texto, style: const TextStyle(fontSize: 15))),
      ],
    );
  }

  Widget _buildMetrica({
    required String label,
    required String valor,
    required IconData icon,
    bool destaque = false,
  }) {
    return Column(
      children: [
        Icon(icon, color: destaque ? Colors.green : Colors.grey, size: 22),
        const SizedBox(height: 4),
        Text(
          valor,
          style: TextStyle(
            fontSize: destaque ? 16 : 14,
            fontWeight: destaque ? FontWeight.bold : FontWeight.normal,
            color: destaque ? Colors.green : Colors.black87,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  @override
  void dispose() {
    _gpsStream?.cancel();
    _corridaChannel?.unsubscribe();
    _mapController.dispose();
    super.dispose();
  }
}
