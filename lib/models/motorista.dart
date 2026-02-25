// lib/models/motorista.dart

class Motorista {
  // ── Identificação ──────────────────────────────────────────
  final String id;
  final String nome;
  final String email;
  final String? telefone;
  final String? cpf;
  final String? fotoUrl;
  final String? cidadeId;
  final bool ativo;

  // ── Status e localização ───────────────────────────────────
  final bool online;
  final String status;
  final double? latitude;
  final double? longitude;
  final double? direcaoAtual;

  // ── Avaliação e histórico ──────────────────────────────────
  final double avaliacao;
  final int totalCorridas;
  final double saldo;

  // ── Documentos ────────────────────────────────────────────
  final bool documentosVerificados;
  final String? categoriaCnh;
  final String? cnhNumero;
  final String? cnhValidade;
  final String? crlvUrl;

  // ── Dados da moto ──────────────────────────────────────────
  final String? placaMoto;
  final String? modeloMoto;
  final String? corMoto;
  final int? anoMoto;
  final String? fotoMotoUrl;

  const Motorista({
    required this.id,
    required this.nome,
    required this.email,
    this.telefone,
    this.cpf,
    this.fotoUrl,
    this.cidadeId,
    this.ativo = true,
    this.online = false,
    this.status = 'offline',
    this.latitude,
    this.longitude,
    this.direcaoAtual,
    this.avaliacao = 5.0,
    this.totalCorridas = 0,
    this.saldo = 0.0,
    this.documentosVerificados = false,
    this.categoriaCnh,
    this.cnhNumero,
    this.cnhValidade,
    this.crlvUrl,
    this.placaMoto,
    this.modeloMoto,
    this.corMoto,
    this.anoMoto,
    this.fotoMotoUrl,
  });

  // ============================================================
  // HELPERS PRIVADOS — suportam String e num vindos do Supabase
  // O PostgREST retorna colunas NUMERIC/DECIMAL como String
  // em algumas versões — estes helpers normalizam os dois casos.
  // ============================================================
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

  // ============================================================
  // fromJson
  // ============================================================
  factory Motorista.fromJson(Map<String, dynamic> json) {
    final perfil = json['perfis'] as Map<String, dynamic>? ?? {};

    // localizacao_atual pode vir como:
    // 1. GeoJSON Map: { "type": "Point", "coordinates": [lng, lat] }
    // 2. WKB hex String: '0101000020E6100000...' → ignoramos, fica null
    double? latitude;
    double? longitude;
    final loc = json['localizacao_atual'];
    if (loc is Map<String, dynamic>) {
      final coords = loc['coordinates'] as List<dynamic>?;
      if (coords != null && coords.length >= 2) {
        longitude = _toDouble(coords[0]);
        latitude  = _toDouble(coords[1]);
      }
    }

    final statusRaw = json['status'] as String? ?? 'offline';

    return Motorista(
      // ── Identificação ────────────────────────────────────
      id:       json['perfil_id'] as String? ?? perfil['id'] as String? ?? '',
      nome:     perfil['nome_completo'] as String? ?? '',
      email:    perfil['email'] as String? ?? '',
      telefone: perfil['telefone'] as String?,
      cpf:      perfil['cpf'] as String?,
      fotoUrl:  perfil['foto_url'] as String?,
      cidadeId: perfil['cidade_id'] as String?,
      ativo:    perfil['ativo'] as bool? ?? true,

      // ── Status e localização ─────────────────────────────
      status:      statusRaw,
      online:      statusRaw == 'online' || statusRaw == 'em_corrida',
      latitude:    latitude,
      longitude:   longitude,
      // ✅ direcao_atual vem como String '0' do banco
      direcaoAtual: _toDouble(json['direcao_atual']),

      // ── Avaliação e histórico ─────────────────────────────
      // ✅ avaliacao_media vem como String '5.0' do banco
      avaliacao:     _toDouble(json['avaliacao_media']) ?? 5.0,
      // ✅ total_corridas vem como String '0' do banco
      totalCorridas: _toInt(json['total_corridas'])    ?? 0,
      // ✅ saldo vem como String '0.00' do banco
      saldo:         _toDouble(json['saldo'])           ?? 0.0,

      // ── Documentos ───────────────────────────────────────
      documentosVerificados: json['documentos_verificados'] as bool? ?? false,
      categoriaCnh: json['categoria_cnh'] as String?,
      cnhNumero:    json['cnh_numero'] as String?,
      cnhValidade:  json['cnh_validade'] as String?,
      crlvUrl:      json['crlv_url'] as String?,

      // ── Moto ─────────────────────────────────────────────
      placaMoto:   json['placa_moto'] as String?,
      modeloMoto:  json['modelo_moto'] as String?,
      corMoto:     json['cor_moto'] as String?,
      // ✅ ano_moto vem como String '2022' do banco
      anoMoto:     _toInt(json['ano_moto']),
      fotoMotoUrl: json['foto_moto_url'] as String?,
    );
  }

  // ============================================================
  // toJson
  // ============================================================
  Map<String, dynamic> toJson() {
    return {
      'status': status,
      if (latitude != null && longitude != null)
        'localizacao_atual': 'POINT($longitude $latitude)',
      if (direcaoAtual != null)
        'direcao_atual': direcaoAtual,
      'ultima_atualizacao': DateTime.now().toIso8601String(),
    };
  }

  // ============================================================
  // copyWith
  // ============================================================
  Motorista copyWith({
    String? id,
    String? nome,
    String? email,
    String? telefone,
    String? cpf,
    String? fotoUrl,
    String? cidadeId,
    bool? ativo,
    bool? online,
    String? status,
    double? latitude,
    double? longitude,
    double? direcaoAtual,
    double? avaliacao,
    int? totalCorridas,
    double? saldo,
    bool? documentosVerificados,
    String? categoriaCnh,
    String? cnhNumero,
    String? cnhValidade,
    String? crlvUrl,
    String? placaMoto,
    String? modeloMoto,
    String? corMoto,
    int? anoMoto,
    String? fotoMotoUrl,
  }) {
    return Motorista(
      id:            id            ?? this.id,
      nome:          nome          ?? this.nome,
      email:         email         ?? this.email,
      telefone:      telefone      ?? this.telefone,
      cpf:           cpf           ?? this.cpf,
      fotoUrl:       fotoUrl       ?? this.fotoUrl,
      cidadeId:      cidadeId      ?? this.cidadeId,
      ativo:         ativo         ?? this.ativo,
      online:        online        ?? this.online,
      status:        status        ?? this.status,
      latitude:      latitude      ?? this.latitude,
      longitude:     longitude     ?? this.longitude,
      direcaoAtual:  direcaoAtual  ?? this.direcaoAtual,
      avaliacao:     avaliacao     ?? this.avaliacao,
      totalCorridas: totalCorridas ?? this.totalCorridas,
      saldo:         saldo         ?? this.saldo,
      documentosVerificados: documentosVerificados ?? this.documentosVerificados,
      categoriaCnh:  categoriaCnh  ?? this.categoriaCnh,
      cnhNumero:     cnhNumero     ?? this.cnhNumero,
      cnhValidade:   cnhValidade   ?? this.cnhValidade,
      crlvUrl:       crlvUrl       ?? this.crlvUrl,
      placaMoto:     placaMoto     ?? this.placaMoto,
      modeloMoto:    modeloMoto    ?? this.modeloMoto,
      corMoto:       corMoto       ?? this.corMoto,
      anoMoto:       anoMoto       ?? this.anoMoto,
      fotoMotoUrl:   fotoMotoUrl   ?? this.fotoMotoUrl,
    );
  }

  // ============================================================
  // Helpers de exibição
  // ============================================================
  bool get podeReceberCorridas => ativo && documentosVerificados;

  String get descricaoMoto {
    final partes = [modeloMoto, anoMoto?.toString(), corMoto]
        .where((p) => p != null && p.isNotEmpty)
        .toList();
    return partes.isNotEmpty ? partes.join(' - ') : 'Moto não cadastrada';
  }

  @override
  String toString() =>
      'Motorista(id: $id, nome: $nome, status: $status, '
      'docs: $documentosVerificados, saldo: $saldo)';
}
