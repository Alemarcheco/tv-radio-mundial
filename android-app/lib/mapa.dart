import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';

import 'comunes.dart';
import 'listas.dart';
import 'modelos.dart';
import 'servicios.dart';

enum ModoMapa { radio, tv }

class RegionMapa {
  final String id, nombre, pais;
  final LatLng punto;
  final int cantidad;
  final List<Emisora> emisoras;
  final FuenteTV? fuente;
  final bool nacional;
  const RegionMapa({
    required this.id,
    required this.nombre,
    required this.pais,
    required this.punto,
    required this.cantidad,
    this.emisoras = const [],
    this.fuente,
    this.nacional = false,
  });
}

// ───────────────────────── Datos del mapa

class DatosMapa extends ChangeNotifier {
  final regionesRadio = <String, List<RegionMapa>>{};
  final regionesTV = <String, List<RegionMapa>>{};
  final emisorasPorPais = <String, List<Emisora>>{};
  List<PaisRadio> paisesRadio = [];
  String? cargando;
  final _enCurso = <String>{};

  List<(Emisora, LatLng)> get conPunto => [
        for (final l in emisorasPorPais.values)
          for (final e in l)
            if (e.punto != null) (e, e.punto!)
      ];

  Future<void> cargarPaises() async {
    try {
      paisesRadio = await ServicioRadio.paises();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> cargar(String p, ModoMapa m) => m == ModoMapa.radio ? cargarRadio(p) : cargarTV(p);

  Future<List<Emisora>> cargarRadio(String pais) async {
    final p = pais.toUpperCase();
    final ya = emisorasPorPais[p];
    if (ya != null) return ya;
    if (!_enCurso.add('r$p')) return [];
    cargando = 'Buscando emisoras de ${Paises.nombre(p)}…';
    notifyListeners();
    try {
      final lista = await ServicioRadio.delPais(p);
      emisorasPorPais[p] = lista;

      final grupos = <String, List<Emisora>>{};
      final nombres = <String, String>{};
      for (final e in lista) {
        final original = (e.estado ?? '').trim();
        final k = normalizar(original);
        grupos.putIfAbsent(k, () => []).add(e);
        nombres.putIfAbsent(k, () => original);
      }
      final regiones = <RegionMapa>[];
      final sinUbicar = <MapEntry<String, List<Emisora>>>[];
      for (final g in grupos.entries) {
        if (g.key.isEmpty) {
          final c = Paises.centro(p);
          if (c != null) {
            regiones.add(RegionMapa(id: 'r-$p-nac', nombre: 'Sin región indicada', pais: p, punto: c, cantidad: g.value.length, emisoras: g.value, nacional: true));
          }
          continue;
        }
        final pts = g.value.map((e) => e.punto).whereType<LatLng>().toList();
        if (pts.isNotEmpty) {
          regiones.add(RegionMapa(id: 'r-$p-${g.key}', nombre: nombres[g.key]!, pais: p, punto: _mediana(pts), cantidad: g.value.length, emisoras: g.value));
        } else {
          sinUbicar.add(g);
        }
      }
      regionesRadio[p] = regiones;
      notifyListeners();

      sinUbicar.sort((a, b) => b.value.length.compareTo(a.value.length));
      for (final g in sinUbicar.take(60)) {
        final nombre = nombres[g.key]!;
        final c = await Geocodificador.ubicar('$nombre, ${Paises.nombre(p)}');
        if (c != null) {
          regionesRadio[p]!.add(RegionMapa(id: 'r-$p-${g.key}', nombre: nombre, pais: p, punto: c, cantidad: g.value.length, emisoras: g.value));
          notifyListeners();
        }
      }
      return lista;
    } catch (_) {
      return [];
    } finally {
      _enCurso.remove('r$p');
      cargando = null;
      notifyListeners();
    }
  }

  Future<void> cargarTV(String pais) async {
    final p = pais.toUpperCase();
    if (regionesTV.containsKey(p) || !_enCurso.add('t$p')) return;
    cargando = 'Buscando canales de ${Paises.nombre(p)}…';
    notifyListeners();
    try {
      final fp = FuenteTV.pais(p);
      final total = (await ServicioTV.canales(fp).catchError((_) => <Canal>[])).length;
      final c = Paises.centro(p);
      regionesTV[p] = [
        if (c != null && total > 0)
          RegionMapa(id: 't-$p-nac', nombre: 'Todo ${Paises.nombre(p)}', pais: p, punto: c, cantidad: total, fuente: fp, nacional: true),
      ];
      notifyListeners();

      final subs = await ServicioRegionesTV.de(p);
      final conteos = await Future.wait(subs.map((s) async {
        final f = FuenteTV(s.nombre, 'subdivisions/${s.codigo.toLowerCase()}.m3u', '📍');
        final n = (await ServicioTV.canales(f).catchError((_) => <Canal>[])).length;
        return (s, f, n);
      }));
      final validos = conteos.where((x) => x.$3 > 0).toList()..sort((a, b) => b.$3.compareTo(a.$3));
      for (final (s, f, n) in validos) {
        final punto = await Geocodificador.ubicar('${s.nombre}, ${Paises.nombre(p)}');
        if (punto != null) {
          regionesTV[p]!.add(RegionMapa(id: 't-${s.codigo}', nombre: s.nombre, pais: p, punto: punto, cantidad: n, fuente: f));
          notifyListeners();
        }
      }
    } finally {
      _enCurso.remove('t$p');
      cargando = null;
      notifyListeners();
    }
  }

  static LatLng _mediana(List<LatLng> l) {
    final la = l.map((e) => e.latitude).toList()..sort();
    final lo = l.map((e) => e.longitude).toList()..sort();
    return LatLng(la[la.length ~/ 2], lo[lo.length ~/ 2]);
  }

  String? paisMasCercano(LatLng c) {
    final codigos = paisesRadio.isNotEmpty ? paisesRadio.map((e) => e.codigo) : paisesDatosConCentro;
    String? mejor;
    var d = double.infinity;
    for (final k in codigos) {
      final p = Paises.centro(k);
      if (p == null) continue;
      var dLon = (p.longitude - c.longitude).abs();
      if (dLon > 180) dLon = 360 - dLon;
      final dLat = p.latitude - c.latitude;
      final x = dLat * dLat + pow(dLon * cos(c.latitude * pi / 180), 2);
      if (x < d) {
        d = x;
        mejor = k;
      }
    }
    return mejor;
  }

  static Iterable<String> get paisesDatosConCentro => Paises.todos;

  String? paisAlAzar() {
    final c = paisesRadio.where((p) => Paises.centro(p.codigo) != null).toList();
    if (c.isEmpty) return null;
    final pesos = c.map((p) => sqrt(p.cantidad) + 1).toList();
    var r = Random().nextDouble() * pesos.reduce((a, b) => a + b);
    for (var i = 0; i < c.length; i++) {
      r -= pesos[i];
      if (r < 0) return c[i].codigo;
    }
    return c.last.codigo;
  }
}

// ───────────────────────── Pantalla del mapa

class MapaPagina extends StatefulWidget {
  const MapaPagina({super.key});
  @override
  State<MapaPagina> createState() => _MapaPaginaState();
}

class _MapaPaginaState extends State<MapaPagina> {
  final _mapa = MapController();
  final _datos = DatosMapa();
  ModoMapa _modo = ModoMapa.radio;
  bool _satelite = true;
  double _zoom = 2.5;
  LatLngBounds? _vista;
  String? _paisEnfocado;
  Timer? _espera;

  Color get _color => _modo == ModoMapa.radio ? Colors.green : Colors.orange;

  @override
  void initState() {
    super.initState();
    _datos.cargarPaises();
    _datos.addListener(_refrescar);
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _datos.removeListener(_refrescar);
    _espera?.cancel();
    super.dispose();
  }

  void _alMover(MapCamera cam, bool gesto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _zoom = cam.zoom;
        _vista = cam.visibleBounds;
      });
      if (cam.zoom >= 4) {
        final p = _datos.paisMasCercano(cam.center);
        if (p != null) {
          _paisEnfocado = p;
          _datos.cargar(p, _modo);
        }
      }
    });
  }

  bool _enVista(LatLng p) => _vista == null || _vista!.contains(p);

  void _volar(LatLng p, double zoom) => _mapa.move(p, zoom);

  void _enfocar(String codigo) {
    final c = Paises.centro(codigo);
    if (c == null) return;
    setState(() => _paisEnfocado = codigo);
    _volar(c, 5);
    _datos.cargar(codigo, _modo);
  }

  void _tocarRegion(RegionMapa r) {
    if (_modo == ModoMapa.radio) {
      if (r.emisoras.length == 1) {
        radio.reproducir(r.emisoras.first);
      } else {
        ir(context, EmisorasFijasPagina(r.nombre, r.emisoras));
      }
    } else if (r.fuente != null) {
      ir(context, CanalesPagina(r.fuente!));
    }
  }

  Future<void> _sorprendeme() async {
    final p = _datos.paisAlAzar();
    if (p == null) return;
    final lista = await _datos.cargarRadio(p);
    if (lista.isEmpty) {
      _enfocar(p);
      return;
    }
    final e = lista.take(80).toList()[Random().nextInt(min(80, lista.length))];
    setState(() => _paisEnfocado = p);
    final lugar = e.punto ?? Paises.centro(p);
    if (lugar != null) _volar(lugar, e.punto != null ? 9 : 5);
    radio.reproducir(e);
  }

  // Zonas/ciudades: se agrupan las emisoras en una cuadrícula según el zoom.
  List<RegionMapa> _zonas() {
    final g = 3.0 / pow(2, _zoom - 5);
    final grupos = <String, List<(Emisora, LatLng)>>{};
    for (final x in _datos.conPunto) {
      if (!_enVista(x.$2)) continue;
      final k = '${(x.$2.latitude / g).floor()}_${(x.$2.longitude / g).floor()}';
      grupos.putIfAbsent(k, () => []).add(x);
    }
    return grupos.entries.map((en) {
      final ps = en.value;
      final lat = ps.map((e) => e.$2.latitude).reduce((a, b) => a + b) / ps.length;
      final lon = ps.map((e) => e.$2.longitude).reduce((a, b) => a + b) / ps.length;
      final conteo = <String, int>{};
      for (final p in ps) {
        final s = p.$1.estado ?? '';
        if (s.isNotEmpty) conteo[s] = (conteo[s] ?? 0) + 1;
      }
      final nombre = conteo.isEmpty ? 'Emisoras de esta zona' : (conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      return RegionMapa(id: 'z${en.key}', nombre: nombre, pais: '', punto: LatLng(lat, lon), cantidad: ps.length, emisoras: ps.map((e) => e.$1).toList());
    }).toList();
  }

  List<Marker> _marcadores() {
    final m = <Marker>[];
    if (_zoom < 4) {
      final codigos = _modo == ModoMapa.radio && _datos.paisesRadio.isNotEmpty ? _datos.paisesRadio.map((e) => e.codigo) : Paises.todos;
      for (final c in codigos) {
        final p = Paises.centro(c);
        if (p == null || !_enVista(p)) continue;
        m.add(Marker(
          point: p,
          width: 38,
          height: 38,
          child: GestureDetector(
            onTap: () => _enfocar(c),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), shape: BoxShape.circle, border: Border.all(color: _color, width: 2)),
              child: Text(Paises.bandera(c), style: const TextStyle(fontSize: 18)),
            ),
          ),
        ));
      }
      return m;
    }
    final regiones = _modo == ModoMapa.radio && _zoom >= 7
        ? (_zoom >= 10 ? <RegionMapa>[] : _zonas())
        : (_modo == ModoMapa.radio ? _datos.regionesRadio : _datos.regionesTV).values.expand((e) => e).where((r) => _enVista(r.punto)).toList();
    final nombres = _zoom >= 5 && _zoom < 7;
    for (final r in regiones) {
      m.add(Marker(
        point: r.punto,
        width: nombres ? 120 : 48,
        height: nombres ? 58 : 36,
        child: GestureDetector(onTap: () => _tocarRegion(r), child: _Burbuja(r, _color, nombres)),
      ));
    }
    if (_modo == ModoMapa.radio && _zoom >= 10) {
      var n = 0;
      for (final x in _datos.conPunto) {
        if (!_enVista(x.$2)) continue;
        if (++n > 400) break;
        m.add(Marker(
          point: x.$2,
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: () => radio.reproducir(x.$1),
            child: ListenableBuilder(
              listenable: radio,
              builder: (_, _) => _Punto(radio.emisora?.uuid == x.$1.uuid),
            ),
          ),
        ));
      }
    }
    return m;
  }

  String get _ayuda {
    if (_datos.cargando != null) return _datos.cargando!;
    if (_zoom < 4) return 'Toca una bandera o acerca el mapa a un país';
    if (_modo == ModoMapa.radio && _zoom >= 10) return 'Toca un punto verde para escuchar';
    if (_modo == ModoMapa.radio && _zoom >= 7) return 'Cada número es una ciudad o zona: tócalo';
    return 'Cada número es una región: tócalo para ver sus ${_modo == ModoMapa.radio ? 'emisoras' : 'canales'}';
  }

  @override
  Widget build(BuildContext context) {
    final inicio = Paises.centro(Paises.actual) ?? const LatLng(20, -30);
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _mapa,
          options: MapOptions(
            initialCenter: inicio,
            initialZoom: 2.5,
            minZoom: 1.5,
            maxZoom: 17,
            onPositionChanged: _alMover,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            if (_satelite) ...[
              TileLayer(
                urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.alemarcheco.tv_radio_mundial',
              ),
              TileLayer(
                urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.alemarcheco.tv_radio_mundial',
              ),
            ] else
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.alemarcheco.tv_radio_mundial',
              ),
            MarkerLayer(markers: _marcadores()),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: Colors.white70,
                child: Text(_satelite ? '© Esri' : '© OpenStreetMap', style: const TextStyle(fontSize: 9, color: Colors.black87)),
              ),
            ),
          ],
        ),
        SafeArea(
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(16)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: SegmentedButton<ModoMapa>(
                    segments: const [
                      ButtonSegment(value: ModoMapa.radio, label: Text('📻 Radio')),
                      ButtonSegment(value: ModoMapa.tv, label: Text('📺 TV')),
                    ],
                    selected: {_modo},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      setState(() => _modo = s.first);
                      if (_paisEnfocado != null && _zoom >= 4) _datos.cargar(_paisEnfocado!, _modo);
                    },
                  ),
                ),
                IconButton(tooltip: 'Buscar', icon: const Icon(Icons.search), onPressed: _abrirBusqueda),
                IconButton(
                  tooltip: _satelite ? 'Mapa' : 'Satélite',
                  icon: Icon(_satelite ? Icons.map : Icons.satellite_alt),
                  onPressed: () => setState(() => _satelite = !_satelite),
                ),
                if (_modo == ModoMapa.radio)
                  IconButton.filled(
                    tooltip: 'Radio al azar',
                    style: IconButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.shuffle),
                    onPressed: _sorprendeme,
                  ),
              ]),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (_datos.cargando != null)
                  const Padding(padding: EdgeInsets.only(right: 6), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))),
                Flexible(child: Text(_ayuda, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              ]),
            ]),
          ),
        ),
        if (_paisEnfocado != null && _zoom >= 4)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.list),
                label: Text('Todo ${Paises.bandera(_paisEnfocado!)} ${Paises.nombre(_paisEnfocado!)}'),
                onPressed: () => _modo == ModoMapa.radio
                    ? ir(context, EmisorasPagina(FiltroRadio.delPais(_paisEnfocado!)))
                    : ir(context, CanalesPagina(FuenteTV.pais(_paisEnfocado!))),
              ),
            ),
          ),
      ]),
    );
  }

  Future<void> _abrirBusqueda() async {
    final r = await Navigator.of(context).push<(LatLng, String?, bool)>(MaterialPageRoute(builder: (_) => const BusquedaGlobal()));
    if (r == null || !mounted) return;
    final (punto, pais, ciudad) = r;
    if (pais != null) setState(() => _paisEnfocado = pais);
    _volar(punto, ciudad ? 9 : 5);
    if (pais != null) _datos.cargar(pais, _modo);
  }
}

class _Burbuja extends StatelessWidget {
  final RegionMapa r;
  final Color color;
  final bool nombre;
  const _Burbuja(this.r, this.color, this.nombre);

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: r.nacional ? color.withValues(alpha: 0.65) : color,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black45)],
        ),
        child: Text('${r.cantidad}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
      if (nombre)
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
          child: Text(r.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}

class _Punto extends StatelessWidget {
  final bool activa;
  const _Punto(this.activa);
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: activa ? 18 : 12,
          height: activa ? 18 : 12,
          decoration: BoxDecoration(
            color: activa ? Colors.white : Colors.green,
            shape: BoxShape.circle,
            border: Border.all(color: activa ? Colors.green : Colors.black38, width: activa ? 3 : 1),
            boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.8), blurRadius: 6)],
          ),
        ),
      );
}

// ───────────────────────── Búsqueda global

class BusquedaGlobal extends StatefulWidget {
  const BusquedaGlobal({super.key});
  @override
  State<BusquedaGlobal> createState() => _BusquedaGlobalState();
}

class _BusquedaGlobalState extends State<BusquedaGlobal> {
  String _q = '';
  Timer? _t;
  bool _buscando = false;
  List<(String, String, LatLng, String?, bool)> _lugares = [];
  List<Emisora> _emisoras = [];
  List<Canal> _canales = [];

  void _cambio(String t) {
    _q = t.trim();
    _t?.cancel();
    if (_q.length < 2) {
      setState(() {
        _lugares = [];
        _emisoras = [];
        _canales = [];
      });
      return;
    }
    _t = Timer(const Duration(milliseconds: 500), _buscar);
  }

  Future<void> _buscar() async {
    final q = _q;
    setState(() => _buscando = true);

    final lugares = <(String, String, LatLng, String?, bool)>[
      for (final c in Paises.todos.where((c) => contiene(Paises.nombre(c), q)).take(5))
        ('${Paises.bandera(c)} ${Paises.nombre(c)}', 'País', Paises.centro(c)!, c, false),
    ];
    try {
      final r = await Geocoding().locationFromAddress(q).timeout(const Duration(seconds: 8));
      if (r.isNotEmpty) {
        final p = LatLng(r.first.latitude, r.first.longitude);
        String? pais;
        String detalle = 'Lugar';
        try {
          final m = await Geocoding().placemarkFromCoordinates(p.latitude, p.longitude).timeout(const Duration(seconds: 5));
          if (m.isNotEmpty) {
            pais = m.first.isoCountryCode;
            detalle = [m.first.administrativeArea, m.first.country].whereType<String>().where((e) => e.isNotEmpty).join(', ');
          }
        } catch (_) {}
        lugares.add(('📍 $q', detalle, p, pais, true));
      }
    } catch (_) {}
    if (!mounted || q != _q) return;
    setState(() => _lugares = lugares);

    final emisoras = await ServicioRadio.emisoras(FiltroRadio(q, nombre: q), cantidad: 60).catchError((_) => <Emisora>[]);
    if (!mounted || q != _q) return;
    setState(() => _emisoras = emisoras);

    final todos = await ServicioTV.canales(FuenteTV.todos).catchError((_) => <Canal>[]);
    if (!mounted || q != _q) return;
    setState(() {
      _canales = todos.where((c) => contiene(c.nombre, q)).take(80).toList();
      _buscando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vacio = _lugares.isEmpty && _emisoras.isEmpty && _canales.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar en el mundo')),
      bottomNavigationBar: const MiniReproductor(),
      body: Column(children: [
        CampoFiltro(pista: 'Ciudad, país, radio o canal', alCambiar: _cambio, autofocus: true),
        if (_buscando) const LinearProgressIndicator(),
        Expanded(
          child: _q.length < 2
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Escribe una ciudad, un país, una emisora o un canal. Por ejemplo: «Guadalajara», «Japón», «Radio Fórmula», «CNN».'),
                )
              : vacio && !_buscando
                  ? const Vacio('Sin resultados', 'Prueba con otra palabra.', Icons.search_off)
                  : ListView(children: [
                      if (_lugares.isNotEmpty) const _Seccion('Lugares en el mapa'),
                      for (final l in _lugares)
                        ListTile(
                          leading: Icon(l.$5 ? Icons.place : Icons.flag, color: Colors.red),
                          title: Text(l.$1),
                          subtitle: Text(l.$2),
                          onTap: () => Navigator.of(context).pop((l.$3, l.$4, l.$5)),
                        ),
                      if (_emisoras.isNotEmpty) _Seccion('Radios (${_emisoras.length})'),
                      for (final e in _emisoras) FilaEmisora(e),
                      if (_canales.isNotEmpty) _Seccion('Canales de TV (${_canales.length})'),
                      for (final c in _canales) FilaCanal(c),
                    ]),
        ),
      ]),
    );
  }
}

class _Seccion extends StatelessWidget {
  final String t;
  const _Seccion(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );
}
