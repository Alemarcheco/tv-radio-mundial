import 'package:latlong2/latlong.dart';

import 'paises_data.dart';

// ───────────────────────── Canal de TV (listas públicas de iptv-org)

class Canal {
  final String nombre;
  final String url;
  final String? logo;
  final String? grupo;
  final String? userAgent;
  final String? referer;

  const Canal({
    required this.nombre,
    required this.url,
    this.logo,
    this.grupo,
    this.userAgent,
    this.referer,
  });

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'url': url,
        'logo': logo,
        'grupo': grupo,
        'userAgent': userAgent,
        'referer': referer,
      };

  factory Canal.fromJson(Map<String, dynamic> j) => Canal(
        nombre: j['nombre'] ?? 'Canal',
        url: j['url'] ?? '',
        logo: j['logo'],
        grupo: j['grupo'],
        userAgent: j['userAgent'],
        referer: j['referer'],
      );
}

// ───────────────────────── Emisora (API pública Radio Browser)

class Emisora {
  final String uuid;
  final String nombre;
  final String url;
  final String? favicon;
  final String? tags;
  final String? pais;
  final String? codigoPais;
  final String? estado;
  final int? bitrate;
  final double? lat;
  final double? lon;

  const Emisora({
    required this.uuid,
    required this.nombre,
    required this.url,
    this.favicon,
    this.tags,
    this.pais,
    this.codigoPais,
    this.estado,
    this.bitrate,
    this.lat,
    this.lon,
  });

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory Emisora.fromApi(Map<String, dynamic> j) {
    final resuelta = (j['url_resolved'] ?? '').toString();
    final nombre = (j['name'] ?? '').toString().trim();
    return Emisora(
      uuid: (j['stationuuid'] ?? '').toString(),
      nombre: nombre.isEmpty ? 'Emisora sin nombre' : nombre,
      url: resuelta.isNotEmpty ? resuelta : (j['url'] ?? '').toString(),
      favicon: (j['favicon'] ?? '').toString().isEmpty ? null : j['favicon'].toString(),
      tags: j['tags']?.toString(),
      pais: j['country']?.toString(),
      codigoPais: j['countrycode']?.toString(),
      estado: j['state']?.toString(),
      bitrate: j['bitrate'] is num ? (j['bitrate'] as num).toInt() : null,
      lat: _num(j['geo_lat']),
      lon: _num(j['geo_long']),
    );
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'nombre': nombre,
        'url': url,
        'favicon': favicon,
        'tags': tags,
        'pais': pais,
        'codigoPais': codigoPais,
        'estado': estado,
        'bitrate': bitrate,
        'lat': lat,
        'lon': lon,
      };

  factory Emisora.fromJson(Map<String, dynamic> j) => Emisora(
        uuid: j['uuid'] ?? '',
        nombre: j['nombre'] ?? 'Emisora',
        url: j['url'] ?? '',
        favicon: j['favicon'],
        tags: j['tags'],
        pais: j['pais'],
        codigoPais: j['codigoPais'],
        estado: j['estado'],
        bitrate: j['bitrate'],
        lat: _num(j['lat']),
        lon: _num(j['lon']),
      );

  LatLng? get punto {
    final la = lat, lo = lon;
    if (la == null || lo == null) return null;
    if (la.abs() > 90 || lo.abs() > 180 || (la == 0 && lo == 0)) return null;
    return LatLng(la, lo);
  }

  String get detalle {
    final partes = <String>[];
    final c = codigoPais;
    if (c != null && c.isNotEmpty) partes.add('${Paises.bandera(c)} ${Paises.nombre(c)}');
    final generos = (tags ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
    if (generos.isNotEmpty) partes.add(generos.join(', '));
    if ((bitrate ?? 0) > 0) partes.add('$bitrate kbps');
    return partes.join(' · ');
  }
}

// ───────────────────────── Países

class Paises {
  static String bandera(String codigo) {
    final c = codigo.toUpperCase();
    if (c.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '🌐';
    return String.fromCharCodes(c.codeUnits.map((u) => u + 127397));
  }

  static String nombre(String codigo) => paisesDatos[codigo.toUpperCase()]?.nombre ?? codigo;

  static LatLng? centro(String codigo) {
    final d = paisesDatos[codigo.toUpperCase()];
    if (d == null || d.lat == null || d.lon == null) return null;
    return LatLng(d.lat!, d.lon!);
  }

  static List<String> get todos {
    final l = paisesDatos.keys.where((c) => centro(c) != null).toList();
    l.sort((a, b) => _sinAcentos(nombre(a)).compareTo(_sinAcentos(nombre(b))));
    return l;
  }

  static String actual = 'MX';
}

String _sinAcentos(String s) {
  const de = 'áéíóúüñÁÉÍÓÚÜÑ';
  const a = 'aeiouunAEIOUUN';
  var r = s;
  for (var i = 0; i < de.length; i++) {
    r = r.replaceAll(de[i], a[i]);
  }
  return r.toLowerCase();
}

String normalizar(String s) => _sinAcentos(s.trim());

bool contiene(String texto, String buscado) => normalizar(texto).contains(normalizar(buscado));

// ───────────────────────── Fuentes de TV

class FuenteTV {
  final String titulo;
  final String ruta;
  final String icono;
  const FuenteTV(this.titulo, this.ruta, [this.icono = '📺']);

  static FuenteTV pais(String codigo) {
    final c = codigo.toUpperCase() == 'GB' ? 'uk' : codigo.toLowerCase();
    return FuenteTV('${Paises.bandera(codigo)} ${Paises.nombre(codigo)}', 'countries/$c.m3u');
  }

  static const internacional = FuenteTV('🌐 Internacionales', 'countries/int.m3u', '🌐');
  static const todos = FuenteTV('Todos los canales', 'index.m3u', '🌎');

  static const categorias = [
    FuenteTV('Noticias', 'categories/news.m3u', '📰'),
    FuenteTV('Deportes', 'categories/sports.m3u', '⚽'),
    FuenteTV('Películas', 'categories/movies.m3u', '🎬'),
    FuenteTV('Series', 'categories/series.m3u', '🎞️'),
    FuenteTV('Infantiles', 'categories/kids.m3u', '🧸'),
    FuenteTV('Animación', 'categories/animation.m3u', '✨'),
    FuenteTV('Música', 'categories/music.m3u', '🎵'),
    FuenteTV('Documentales', 'categories/documentary.m3u', '🔭'),
    FuenteTV('Entretenimiento', 'categories/entertainment.m3u', '🎭'),
    FuenteTV('Comedia', 'categories/comedy.m3u', '😄'),
    FuenteTV('Cocina', 'categories/cooking.m3u', '🍳'),
    FuenteTV('Cultura', 'categories/culture.m3u', '🏛️'),
    FuenteTV('Educación', 'categories/education.m3u', '🎓'),
    FuenteTV('Ciencia', 'categories/science.m3u', '⚛️'),
    FuenteTV('Viajes', 'categories/travel.m3u', '✈️'),
    FuenteTV('Estilo de vida', 'categories/lifestyle.m3u', '💖'),
    FuenteTV('Familia', 'categories/family.m3u', '👨‍👩‍👧'),
    FuenteTV('Clásicos', 'categories/classic.m3u', '⏰'),
    FuenteTV('Clima', 'categories/weather.m3u', '⛅'),
    FuenteTV('Autos', 'categories/auto.m3u', '🚗'),
    FuenteTV('Aire libre', 'categories/outdoor.m3u', '🌿'),
    FuenteTV('Relax', 'categories/relax.m3u', '🌙'),
    FuenteTV('Religiosos', 'categories/religious.m3u', '📖'),
    FuenteTV('Negocios', 'categories/business.m3u', '📈'),
    FuenteTV('Parlamento', 'categories/legislative.m3u', '🏛'),
    FuenteTV('Compras', 'categories/shop.m3u', '🛒'),
    FuenteTV('Generales', 'categories/general.m3u', '📺'),
  ];

  static const idiomas = [
    FuenteTV('Español', 'languages/spa.m3u', '🗣️'),
    FuenteTV('Inglés', 'languages/eng.m3u', '🗣️'),
    FuenteTV('Portugués', 'languages/por.m3u', '🗣️'),
    FuenteTV('Francés', 'languages/fra.m3u', '🗣️'),
    FuenteTV('Italiano', 'languages/ita.m3u', '🗣️'),
    FuenteTV('Alemán', 'languages/deu.m3u', '🗣️'),
    FuenteTV('Árabe', 'languages/ara.m3u', '🗣️'),
    FuenteTV('Ruso', 'languages/rus.m3u', '🗣️'),
    FuenteTV('Chino', 'languages/zho.m3u', '🗣️'),
    FuenteTV('Japonés', 'languages/jpn.m3u', '🗣️'),
    FuenteTV('Coreano', 'languages/kor.m3u', '🗣️'),
    FuenteTV('Hindi', 'languages/hin.m3u', '🗣️'),
    FuenteTV('Turco', 'languages/tur.m3u', '🗣️'),
  ];
}

// ───────────────────────── Filtro de radio

class FiltroRadio {
  final String titulo;
  final String? pais;
  final String? genero;
  final String? nombre;
  const FiltroRadio(this.titulo, {this.pais, this.genero, this.nombre});

  static const masEscuchadas = FiltroRadio('Más escuchadas del mundo');
  static FiltroRadio delPais(String c) =>
      FiltroRadio('${Paises.bandera(c)} ${Paises.nombre(c)}', pais: c.toUpperCase());
}
