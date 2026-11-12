import 'dart:async';
import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modelos.dart';

const _ua = {'User-Agent': 'TVyRadioMundial/1.0 (Android)'};

// ───────────────────────── Lector de listas M3U

List<Canal> leerM3U(String texto) {
  final canales = <Canal>[];
  final vistos = <String>{};
  String? nombre, logo, grupo, ua, ref;

  String? attr(String clave, String linea) {
    final i = linea.indexOf('$clave="');
    if (i < 0) return null;
    final ini = i + clave.length + 2;
    final fin = linea.indexOf('"', ini);
    if (fin < 0) return null;
    final v = linea.substring(ini, fin);
    return v.isEmpty ? null : v;
  }

  for (final bruta in const LineSplitter().convert(texto)) {
    final linea = bruta.trim();
    if (linea.isEmpty) continue;
    if (linea.startsWith('#EXTINF')) {
      final desde = linea.lastIndexOf('"');
      final coma = linea.indexOf(',', desde < 0 ? 0 : desde);
      nombre = coma >= 0 ? linea.substring(coma + 1).trim() : null;
      logo = attr('tvg-logo', linea);
      grupo = attr('group-title', linea)?.replaceAll(';', ', ');
      ua = attr('user-agent', linea) ?? ua;
      ref = attr('referrer', linea) ?? ref;
    } else if (linea.startsWith('#EXTVLCOPT:')) {
      final op = linea.substring(11);
      if (op.startsWith('http-user-agent=')) ua = op.substring(16);
      if (op.startsWith('http-referrer=')) ref = op.substring(14);
    } else if (linea.startsWith('#')) {
      continue;
    } else {
      if ((linea.startsWith('http://') || linea.startsWith('https://')) && vistos.add(linea)) {
        canales.add(Canal(
          nombre: (nombre == null || nombre.isEmpty) ? 'Canal' : nombre,
          url: linea,
          logo: logo,
          grupo: grupo,
          userAgent: ua,
          referer: ref,
        ));
      }
      nombre = logo = grupo = ua = ref = null;
    }
  }
  return canales;
}

// ───────────────────────── TV (iptv-org)

class ServicioTV {
  static final _cache = <String, List<Canal>>{};
  static final _enCurso = <String, Future<List<Canal>>>{};
  static const _base = 'https://iptv-org.github.io/iptv/';

  static Future<List<Canal>> canales(FuenteTV f) {
    final c = _cache[f.ruta];
    if (c != null) return Future.value(c);
    return _enCurso[f.ruta] ??= _descargar(f.ruta).whenComplete(() => _enCurso.remove(f.ruta));
  }

  static Future<List<Canal>> _descargar(String ruta) async {
    final r = await http.get(Uri.parse(_base + ruta), headers: _ua).timeout(const Duration(seconds: 40));
    if (r.statusCode == 404) return _cache[ruta] = [];
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return _cache[ruta] = leerM3U(utf8.decode(r.bodyBytes, allowMalformed: true));
  }
}

class SubdivisionTV {
  final String codigo, nombre, pais;
  const SubdivisionTV(this.codigo, this.nombre, this.pais);
}

class ServicioRegionesTV {
  static List<SubdivisionTV>? _todas;

  static Future<List<SubdivisionTV>> de(String pais) async {
    if (_todas == null) {
      try {
        final r = await http
            .get(Uri.parse('https://iptv-org.github.io/api/subdivisions.json'), headers: _ua)
            .timeout(const Duration(seconds: 30));
        final lista = jsonDecode(utf8.decode(r.bodyBytes)) as List;
        _todas = lista
            .whereType<Map>()
            .where((d) => d['code'] is String && d['name'] is String && d['country'] is String)
            .map((d) => SubdivisionTV(d['code'], d['name'], (d['country'] as String).toUpperCase()))
            .toList();
      } catch (_) {
        return [];
      }
    }
    final p = pais.toUpperCase();
    final alt = p == 'GB' ? 'UK' : p;
    return _todas!.where((s) => s.pais == p || s.pais == alt).toList();
  }
}

// ───────────────────────── Radio (Radio Browser)

class PaisRadio {
  final String codigo;
  final int cantidad;
  const PaisRadio(this.codigo, this.cantidad);
}

class GeneroRadio {
  final String nombre;
  final int cantidad;
  const GeneroRadio(this.nombre, this.cantidad);
}

class ServicioRadio {
  static const _servidores = [
    'https://de1.api.radio-browser.info',
    'https://de2.api.radio-browser.info',
    'https://fi1.api.radio-browser.info',
    'https://nl1.api.radio-browser.info',
    'https://at1.api.radio-browser.info',
    'https://all.api.radio-browser.info',
  ];
  static String? _bueno;
  static List<PaisRadio>? _paises;
  static List<GeneroRadio>? _generos;

  static Future<dynamic> _pedir(String ruta, [Map<String, String>? q]) async {
    final lista = [..._servidores];
    if (_bueno != null) {
      lista.remove(_bueno);
      lista.insert(0, _bueno!);
    }
    Object ultimo = Exception('Sin servidor');
    for (final s in lista) {
      try {
        final uri = Uri.parse(s + ruta).replace(queryParameters: q);
        final r = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) {
          _bueno = s;
          return jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
        }
      } catch (e) {
        ultimo = e;
      }
    }
    throw ultimo;
  }

  static Future<List<Emisora>> emisoras(FiltroRadio f, {int desde = 0, int cantidad = 100}) async {
    final q = {
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
      'limit': '$cantidad',
      'offset': '$desde',
      if (f.pais != null) 'countrycode': f.pais!,
      if (f.genero != null) 'tag': f.genero!,
      if (f.genero != null) 'tagExact': 'true',
      if (f.nombre != null) 'name': f.nombre!,
    };
    final d = await _pedir('/json/stations/search', q) as List;
    return d.whereType<Map<String, dynamic>>().map(Emisora.fromApi).toList();
  }

  static Future<List<Emisora>> delPais(String pais) =>
      emisoras(FiltroRadio('', pais: pais.toUpperCase()), cantidad: 3000);

  static Future<List<PaisRadio>> paises() async {
    if (_paises != null) return _paises!;
    final d = await _pedir('/json/countries') as List;
    return _paises = d
        .whereType<Map>()
        .map((m) => PaisRadio((m['iso_3166_1'] ?? '').toString().toUpperCase(), (m['stationcount'] as num?)?.toInt() ?? 0))
        .where((p) => p.codigo.length == 2 && p.cantidad > 0)
        .toList();
  }

  static Future<List<GeneroRadio>> generos() async {
    if (_generos != null) return _generos!;
    final d = await _pedir('/json/tags', {
      'order': 'stationcount',
      'reverse': 'true',
      'hidebroken': 'true',
      'limit': '200',
    }) as List;
    return _generos = d
        .whereType<Map>()
        .map((m) => GeneroRadio((m['name'] ?? '').toString(), (m['stationcount'] as num?)?.toInt() ?? 0))
        .where((g) => g.nombre.trim().isNotEmpty)
        .toList();
  }

  static Future<void> registrarEscucha(String uuid) async {
    try {
      await _pedir('/json/url/$uuid');
    } catch (_) {}
  }
}

// ───────────────────────── Ubicar regiones por nombre (con caché)

class Geocodificador {
  static const _clave = 'geo_cache_v1';
  static Map<String, List<double>>? _cache;
  static final _fallidos = <String>{};
  static Future<void> _cola = Future.value();

  static Future<LatLng?> ubicar(String consulta) {
    final completer = Completer<LatLng?>();
    _cola = _cola.then((_) async {
      completer.complete(await _ubicar(consulta));
    });
    return completer.future;
  }

  static Future<LatLng?> _ubicar(String consulta) async {
    final prefs = await SharedPreferences.getInstance();
    if (_cache == null) {
      _cache = {};
      final s = prefs.getString(_clave);
      if (s != null) {
        (jsonDecode(s) as Map).forEach((k, v) {
          _cache![k] = (v as List).map((e) => (e as num).toDouble()).toList();
        });
      }
    }
    final c = _cache![consulta];
    if (c != null && c.length == 2) return LatLng(c[0], c[1]);
    if (_fallidos.contains(consulta)) return null;
    try {
      final r = await Geocoding().locationFromAddress(consulta).timeout(const Duration(seconds: 10));
      if (r.isNotEmpty) {
        _cache![consulta] = [r.first.latitude, r.first.longitude];
        await prefs.setString(_clave, jsonEncode(_cache));
        return LatLng(r.first.latitude, r.first.longitude);
      }
      _fallidos.add(consulta);
    } catch (_) {
      _fallidos.add(consulta);
    }
    return null;
  }
}

// ───────────────────────── Internet Archive (películas y series de dominio público)

class Titulo {
  final String id, titulo;
  final String? anio;
  const Titulo(this.id, this.titulo, this.anio);
  String get portada => 'https://archive.org/services/img/$id';
}

class ArchivoVideo {
  final String nombre, url;
  const ArchivoVideo(this.nombre, this.url);
}

class ColeccionCine {
  final String titulo, consulta, icono;
  const ColeccionCine(this.titulo, this.consulta, this.icono);

  static const todas = [
    ColeccionCine('Películas clásicas', 'collection:(feature_films)', '🎬'),
    ColeccionCine('Películas en español', 'collection:(feature_films) AND language:(spa OR Spanish OR español)', '🗣️'),
    ColeccionCine('Recientes (2000 en adelante)', 'collection:(feature_films OR independent_films OR moviesandfilms) AND year:[2000 TO 2030]', '🆕'),
    ColeccionCine('Series clásicas de TV', 'collection:(classic_tv)', '📺'),
    ColeccionCine('Caricaturas clásicas', 'collection:(classic_cartoons)', '🧸'),
    ColeccionCine('Cine negro', 'collection:(film_noir)', '🌙'),
    ColeccionCine('Ciencia ficción y terror', 'collection:(SciFi_Horror)', '👽'),
    ColeccionCine('Comedia', 'collection:(comedy_films)', '😄'),
    ColeccionCine('Cine mudo', 'collection:(silent_films)', '🎩'),
  ];
}

class ServicioArchive {
  static String _texto(dynamic v) {
    if (v == null) return '';
    if (v is List) return v.isEmpty ? '' : v.first.toString();
    return v.toString();
  }

  static Future<List<Titulo>> buscar(String consulta, {int pagina = 1}) async {
    final uri = Uri.parse('https://archive.org/advancedsearch.php').replace(queryParameters: {
      'q': '($consulta) AND mediatype:(movies)',
      'fl[]': ['identifier', 'title', 'year'],
      'sort[]': 'downloads desc',
      'rows': '60',
      'page': '$pagina',
      'output': 'json',
    });
    final r = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 30));
    final docs = (jsonDecode(utf8.decode(r.bodyBytes))['response']['docs'] as List).whereType<Map>();
    return docs.map((d) {
      final id = _texto(d['identifier']);
      final t = _texto(d['title']);
      final y = _texto(d['year']);
      return Titulo(id, t.isEmpty ? id : t, y.isEmpty ? null : y);
    }).toList();
  }

  static Future<(String, List<ArchivoVideo>)> videos(String id) async {
    final r = await http.get(Uri.parse('https://archive.org/metadata/$id'), headers: _ua).timeout(const Duration(seconds: 30));
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final meta = (j['metadata'] as Map?) ?? {};
    final desc = _texto(meta['description']).replaceAll(RegExp(r'<[^>]+>'), '');
    final archivos = (j['files'] as List? ?? []).whereType<Map>();
    final porBase = <String, (String, int)>{};
    for (final f in archivos) {
      final n = _texto(f['name']);
      if (!n.toLowerCase().endsWith('.mp4')) continue;
      final formato = _texto(f['format']).toLowerCase();
      final base = n.replaceAll('_512kb', '').replaceAll(RegExp(r'\.mp4$', caseSensitive: false), '');
      final prioridad = formato.contains('h.264') ? 3 : (formato.contains('512kb') ? 2 : 1);
      if ((porBase[base]?.$2 ?? 0) < prioridad) porBase[base] = (n, prioridad);
    }
    final nombres = porBase.values.map((e) => e.$1).toList()..sort();
    final videos = nombres.map((n) {
      final limpio = n.replaceAll(RegExp(r'\.mp4$', caseSensitive: false), '').replaceAll('_512kb', '').replaceAll('_', ' ');
      return ArchivoVideo(limpio, 'https://archive.org/download/$id/${Uri.encodeComponent(n).replaceAll('%2F', '/')}');
    }).toList();
    return (desc, videos);
  }
}
