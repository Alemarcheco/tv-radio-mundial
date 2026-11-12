import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'comunes.dart';
import 'modelos.dart';
import 'reproductor.dart';
import 'servicios.dart';

// ═════════════════════════ TV

class TVInicio extends StatelessWidget {
  const TVInicio({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Paises.actual;
    return Scaffold(
      appBar: AppBar(title: const Text('TV del mundo')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.home),
          title: Text('Canales de ${Paises.bandera(p)} ${Paises.nombre(p)}'),
          onTap: () => ir(context, CanalesPagina(FuenteTV.pais(p))),
        ),
        ListTile(leading: const Icon(Icons.flag), title: const Text('Elegir país'), onTap: () => ir(context, const PaisesTV())),
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('Canales internacionales'),
          onTap: () => ir(context, const CanalesPagina(FuenteTV.internacional)),
        ),
        ListTile(
          leading: const Icon(Icons.travel_explore),
          title: const Text('Todos los canales del mundo'),
          onTap: () => ir(context, const CanalesPagina(FuenteTV.todos)),
        ),
        const _Titulo('Por tema'),
        for (final f in FuenteTV.categorias)
          ListTile(leading: Text(f.icono, style: const TextStyle(fontSize: 22)), title: Text(f.titulo), onTap: () => ir(context, CanalesPagina(f))),
        const _Titulo('Por idioma'),
        for (final f in FuenteTV.idiomas)
          ListTile(leading: Text(f.icono, style: const TextStyle(fontSize: 22)), title: Text(f.titulo), onTap: () => ir(context, CanalesPagina(f))),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Canales gratuitos y públicos de la lista abierta iptv-org. Algunos pueden estar caídos o bloqueados fuera de su país.',
              style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;
  const _Titulo(this.texto);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(texto, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );
}

class PaisesTV extends StatefulWidget {
  const PaisesTV({super.key});
  @override
  State<PaisesTV> createState() => _PaisesTVState();
}

class _PaisesTVState extends State<PaisesTV> {
  String _f = '';
  @override
  Widget build(BuildContext context) {
    final lista = Paises.todos.where((c) => _f.isEmpty || contiene(Paises.nombre(c), _f)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Países')),
      body: Column(children: [
        CampoFiltro(pista: 'Buscar país', alCambiar: (t) => setState(() => _f = t)),
        Expanded(
          child: ListView.builder(
            itemCount: lista.length,
            itemBuilder: (_, i) => ListTile(
              title: Text('${Paises.bandera(lista[i])}  ${Paises.nombre(lista[i])}'),
              onTap: () => ir(context, CanalesPagina(FuenteTV.pais(lista[i]))),
            ),
          ),
        ),
      ]),
    );
  }
}

class CanalesPagina extends StatelessWidget {
  final FuenteTV fuente;
  const CanalesPagina(this.fuente, {super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(fuente.titulo)), body: ListaCanales(fuente), bottomNavigationBar: const MiniReproductor());
}

class ListaCanales extends StatefulWidget {
  final FuenteTV fuente;
  const ListaCanales(this.fuente, {super.key});
  @override
  State<ListaCanales> createState() => _ListaCanalesState();
}

class _ListaCanalesState extends State<ListaCanales> {
  List<Canal>? _canales;
  String? _error;
  String _f = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final l = await ServicioTV.canales(widget.fuente);
      if (mounted) setState(() => _canales = l);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo descargar la lista de canales. Revisa tu internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return VistaError(_error!, _cargar);
    final c = _canales;
    if (c == null) return const Center(child: CircularProgressIndicator());
    if (c.isEmpty) return const Vacio('Sin canales', 'No hay canales gratuitos conocidos para esta selección.', Icons.tv_off);
    final lista = c.where((x) => _f.isEmpty || contiene(x.nombre, _f) || contiene(x.grupo ?? '', _f)).toList();
    return Column(children: [
      CampoFiltro(pista: 'Buscar entre ${c.length} canales', alCambiar: (t) => setState(() => _f = t)),
      Expanded(child: ListView.builder(itemCount: lista.length, itemBuilder: (_, i) => FilaCanal(lista[i]))),
    ]);
  }
}

// ═════════════════════════ Radio

class RadioInicio extends StatefulWidget {
  const RadioInicio({super.key});
  @override
  State<RadioInicio> createState() => _RadioInicioState();
}

class _RadioInicioState extends State<RadioInicio> {
  String _q = '';
  List<Emisora> _res = [];
  bool _buscando = false;
  Timer? _t;

  void _cambio(String t) {
    _q = t.trim();
    _t?.cancel();
    if (_q.length < 2) {
      setState(() => _res = []);
      return;
    }
    _t = Timer(const Duration(milliseconds: 450), () async {
      final q = _q;
      setState(() => _buscando = true);
      final r = await ServicioRadio.emisoras(FiltroRadio(q, nombre: q), cantidad: 150).catchError((_) => <Emisora>[]);
      if (!mounted || q != _q) return;
      setState(() {
        _res = r;
        _buscando = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Paises.actual;
    return Scaffold(
      appBar: AppBar(title: const Text('Radio del mundo')),
      body: Column(children: [
        CampoFiltro(pista: 'Buscar emisora en todo el mundo', alCambiar: _cambio),
        Expanded(
          child: _q.length >= 2
              ? (_buscando && _res.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(itemCount: _res.length, itemBuilder: (_, i) => FilaEmisora(_res[i])))
              : ListView(children: [
                  ListTile(
                    leading: const Icon(Icons.home),
                    title: Text('Emisoras de ${Paises.bandera(p)} ${Paises.nombre(p)}'),
                    onTap: () => ir(context, EmisorasPagina(FiltroRadio.delPais(p))),
                  ),
                  ListTile(
                    leading: const Icon(Icons.local_fire_department),
                    title: const Text('Más escuchadas del mundo'),
                    onTap: () => ir(context, const EmisorasPagina(FiltroRadio.masEscuchadas)),
                  ),
                  ListTile(leading: const Icon(Icons.flag), title: const Text('Por país'), onTap: () => ir(context, const PaisesRadio())),
                  ListTile(leading: const Icon(Icons.queue_music), title: const Text('Por género'), onTap: () => ir(context, const GenerosRadio())),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Más de 40.000 emisoras del directorio libre Radio Browser. Sigue sonando con la pantalla apagada.',
                        style: TextStyle(fontSize: 12)),
                  ),
                ]),
        ),
      ]),
    );
  }
}

class EmisorasPagina extends StatelessWidget {
  final FiltroRadio filtro;
  const EmisorasPagina(this.filtro, {super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(filtro.titulo)), body: ListaEmisoras(filtro), bottomNavigationBar: const MiniReproductor());
}

class ListaEmisoras extends StatefulWidget {
  final FiltroRadio filtro;
  const ListaEmisoras(this.filtro, {super.key});
  @override
  State<ListaEmisoras> createState() => _ListaEmisorasState();
}

class _ListaEmisorasState extends State<ListaEmisoras> {
  final List<Emisora> _l = [];
  bool _cargando = false, _hayMas = true;
  String? _error;
  String _f = '';

  @override
  void initState() {
    super.initState();
    _mas();
  }

  Future<void> _mas() async {
    if (_cargando || !_hayMas) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final n = await ServicioRadio.emisoras(widget.filtro, desde: _l.length);
      final ya = _l.map((e) => e.uuid).toSet();
      _l.addAll(n.where((e) => !ya.contains(e.uuid)));
      _hayMas = n.length == 100;
    } catch (_) {
      _error = 'No se pudo conectar con el directorio de radios.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_l.isEmpty && _error != null) return VistaError(_error!, _mas);
    if (_l.isEmpty && _cargando) return const Center(child: CircularProgressIndicator());
    if (_l.isEmpty) return const Vacio('Sin emisoras', 'No se encontraron emisoras para esta selección.', Icons.radio);
    final lista = _l.where((e) => _f.isEmpty || contiene(e.nombre, _f) || contiene(e.tags ?? '', _f)).toList();
    return Column(children: [
      CampoFiltro(pista: 'Filtrar', alCambiar: (t) => setState(() => _f = t)),
      Expanded(
        child: ListView.builder(
          itemCount: lista.length + (_cargando ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= lista.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            if (_f.isEmpty && i == lista.length - 1) WidgetsBinding.instance.addPostFrameCallback((_) => _mas());
            return FilaEmisora(lista[i]);
          },
        ),
      ),
    ]);
  }
}

/// Lista de emisoras ya cargadas (las de una región del mapa).
class EmisorasFijasPagina extends StatefulWidget {
  final String titulo;
  final List<Emisora> emisoras;
  const EmisorasFijasPagina(this.titulo, this.emisoras, {super.key});
  @override
  State<EmisorasFijasPagina> createState() => _EmisorasFijasPaginaState();
}

class _EmisorasFijasPaginaState extends State<EmisorasFijasPagina> {
  String _f = '';
  @override
  Widget build(BuildContext context) {
    final lista = widget.emisoras.where((e) => _f.isEmpty || contiene(e.nombre, _f) || contiene(e.tags ?? '', _f)).toList();
    return Scaffold(
      appBar: AppBar(title: Text('${widget.titulo} (${widget.emisoras.length})')),
      bottomNavigationBar: const MiniReproductor(),
      body: Column(children: [
        CampoFiltro(pista: 'Filtrar', alCambiar: (t) => setState(() => _f = t)),
        Expanded(child: ListView.builder(itemCount: lista.length, itemBuilder: (_, i) => FilaEmisora(lista[i]))),
      ]),
    );
  }
}

class PaisesRadio extends StatefulWidget {
  const PaisesRadio({super.key});
  @override
  State<PaisesRadio> createState() => _PaisesRadioState();
}

class _PaisesRadioState extends State<PaisesRadio> {
  List<PaisRadio>? _l;
  String? _error;
  String _f = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final l = [...await ServicioRadio.paises()];
      l.sort((a, b) => normalizar(Paises.nombre(a.codigo)).compareTo(normalizar(Paises.nombre(b.codigo))));
      if (mounted) setState(() => _l = l);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la lista de países.');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget cuerpo;
    if (_error != null && _l == null) {
      cuerpo = VistaError(_error!, _cargar);
    } else if (_l == null) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else {
      final lista = _l!.where((p) => _f.isEmpty || contiene(Paises.nombre(p.codigo), _f)).toList();
      cuerpo = Column(children: [
        CampoFiltro(pista: 'Buscar país', alCambiar: (t) => setState(() => _f = t)),
        Expanded(
          child: ListView.builder(
            itemCount: lista.length,
            itemBuilder: (_, i) => ListTile(
              title: Text('${Paises.bandera(lista[i].codigo)}  ${Paises.nombre(lista[i].codigo)}'),
              trailing: Text('${lista[i].cantidad}'),
              onTap: () => ir(context, EmisorasPagina(FiltroRadio.delPais(lista[i].codigo))),
            ),
          ),
        ),
      ]);
    }
    return Scaffold(appBar: AppBar(title: const Text('Países')), body: cuerpo, bottomNavigationBar: const MiniReproductor());
  }
}

class GenerosRadio extends StatefulWidget {
  const GenerosRadio({super.key});
  @override
  State<GenerosRadio> createState() => _GenerosRadioState();
}

class _GenerosRadioState extends State<GenerosRadio> {
  List<GeneroRadio>? _l;
  String? _error;
  String _f = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final l = await ServicioRadio.generos();
      if (mounted) setState(() => _l = l);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar la lista de géneros.');
    }
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    Widget cuerpo;
    if (_error != null && _l == null) {
      cuerpo = VistaError(_error!, _cargar);
    } else if (_l == null) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else {
      final lista = _l!.where((g) => _f.isEmpty || contiene(g.nombre, _f)).toList();
      cuerpo = Column(children: [
        CampoFiltro(pista: 'Buscar género (rock, salsa, news…)', alCambiar: (t) => setState(() => _f = t)),
        Expanded(
          child: ListView.builder(
            itemCount: lista.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(_cap(lista[i].nombre)),
              trailing: Text('${lista[i].cantidad}'),
              onTap: () => ir(context, EmisorasPagina(FiltroRadio(_cap(lista[i].nombre), genero: lista[i].nombre))),
            ),
          ),
        ),
      ]);
    }
    return Scaffold(appBar: AppBar(title: const Text('Géneros')), body: cuerpo, bottomNavigationBar: const MiniReproductor());
  }
}

// ═════════════════════════ Cine (películas y series gratis y legales)

class CineInicio extends StatelessWidget {
  const CineInicio({super.key});

  static const servicios = [
    ('Pluto TV', 'Cientos de canales y películas gratis, en español', 'https://pluto.tv/latam'),
    ('Tubi', 'Miles de películas y series gratis', 'https://tubitv.com'),
    ('ViX', 'Novelas, series y películas en español (versión gratis)', 'https://vix.com'),
    ('Plex', 'Películas y TV en vivo gratis', 'https://watch.plex.tv'),
    ('Canela.TV', 'Películas y series gratis en español', 'https://www.canela.tv'),
    ('The Roku Channel', 'Películas, series y TV en vivo gratis', 'https://therokuchannel.roku.com'),
    ('YouTube: películas gratis', 'Películas oficiales gratis con anuncios', 'https://www.youtube.com/feed/storefront'),
    ('Kanopy', 'Cine gratis con credencial de biblioteca', 'https://www.kanopy.com'),
    ('Hoopla', 'Películas y series con credencial de biblioteca', 'https://www.hoopladigital.com'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Películas y series')),
      body: ListView(children: [
        const _Titulo('Ver aquí mismo (Internet Archive)'),
        for (final c in ColeccionCine.todas)
          ListTile(leading: Text(c.icono, style: const TextStyle(fontSize: 22)), title: Text(c.titulo), onTap: () => ir(context, TitulosPagina(c))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Películas y series de dominio público o con permiso para verse gratis.', style: TextStyle(fontSize: 12)),
        ),
        const _Titulo('Canales de películas y series 24 horas'),
        ListTile(
          leading: const Text('🎬', style: TextStyle(fontSize: 22)),
          title: const Text('Canales de películas'),
          onTap: () => ir(context, const CanalesPagina(FuenteTV('Canales de películas', 'categories/movies.m3u'))),
        ),
        ListTile(
          leading: const Text('🎞️', style: TextStyle(fontSize: 22)),
          title: const Text('Canales de series'),
          onTap: () => ir(context, const CanalesPagina(FuenteTV('Canales de series', 'categories/series.m3u'))),
        ),
        const _Titulo('Estrenos y series actuales: apps gratis oficiales'),
        for (final s in servicios)
          ListTile(
            title: Text(s.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(s.$2),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse(s.$3), mode: LaunchMode.externalApplication),
          ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Son gratis con anuncios y legales. Se abren en su app (si la tienes) o en su página.', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

class TitulosPagina extends StatefulWidget {
  final ColeccionCine coleccion;
  const TitulosPagina(this.coleccion, {super.key});
  @override
  State<TitulosPagina> createState() => _TitulosPaginaState();
}

class _TitulosPaginaState extends State<TitulosPagina> {
  final List<Titulo> _l = [];
  int _pagina = 1;
  bool _cargando = false, _hayMas = true;
  String? _error;
  String _texto = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool reiniciar = false}) async {
    if (reiniciar) {
      _l.clear();
      _pagina = 1;
      _hayMas = true;
    }
    if (_cargando || !_hayMas) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    var q = widget.coleccion.consulta;
    final t = _texto.trim().replaceAll('"', '');
    if (t.isNotEmpty) q += ' AND title:("$t")';
    try {
      final n = await ServicioArchive.buscar(q, pagina: _pagina);
      final ya = _l.map((e) => e.id).toSet();
      _l.addAll(n.where((e) => !ya.contains(e.id)));
      _hayMas = n.length == 60;
      _pagina++;
    } catch (_) {
      _error = 'No se pudo conectar con Internet Archive.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.coleccion.titulo)),
      bottomNavigationBar: const MiniReproductor(),
      body: Column(children: [
        CampoFiltro(
          pista: 'Buscar en esta colección',
          alCambiar: (t) {
            _texto = t;
            if (t.isEmpty) _cargar(reiniciar: true);
          },
          alEnviar: (_) => _cargar(reiniciar: true),
        ),
        Expanded(
          child: _l.isEmpty && _error != null
              ? VistaError(_error!, () => _cargar(reiniciar: true))
              : _l.isEmpty && _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 140, childAspectRatio: 0.55, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: _l.length,
                      itemBuilder: (_, i) {
                        if (i == _l.length - 1) WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
                        final t = _l[i];
                        return InkWell(
                          onTap: () => ir(context, DetalleTitulo(t)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(t.portada,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (_, _, _) => Container(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Icon(Icons.movie))),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(t.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            if (t.anio != null) Text(t.anio!, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

class DetalleTitulo extends StatefulWidget {
  final Titulo titulo;
  const DetalleTitulo(this.titulo, {super.key});
  @override
  State<DetalleTitulo> createState() => _DetalleTituloState();
}

class _DetalleTituloState extends State<DetalleTitulo> {
  String _desc = '';
  List<ArchivoVideo>? _videos;

  @override
  void initState() {
    super.initState();
    ServicioArchive.videos(widget.titulo.id).then((r) {
      if (mounted) {
        setState(() {
          _desc = r.$1;
          _videos = r.$2;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _videos = []);
    });
  }

  void _ver(ArchivoVideo v, String nombre) => Video.abrir(context, Canal(nombre: nombre, url: v.url), enVivo: false);

  @override
  Widget build(BuildContext context) {
    final t = widget.titulo;
    final v = _videos;
    return Scaffold(
      appBar: AppBar(title: Text(t.titulo, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(t.portada, width: 110, height: 160, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(width: 110, height: 160, child: Icon(Icons.movie))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.titulo, style: Theme.of(context).textTheme.titleMedium),
              if (t.anio != null) Text(t.anio!),
              const SizedBox(height: 10),
              if (v != null && v.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _ver(v.first, t.titulo),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(v.length > 1 ? 'Ver episodio 1' : 'Ver ahora'),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        if (v == null) const Center(child: CircularProgressIndicator()),
        if (v != null && v.isEmpty) const Text('Este título no tiene un video que el teléfono pueda reproducir.'),
        if (v != null && v.length > 1) ...[
          Text('Episodios / partes (${v.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          for (final x in v)
            ListTile(dense: true, leading: const Icon(Icons.play_circle_outline), title: Text(x.nombre), onTap: () => _ver(x, x.nombre)),
        ],
        if (_desc.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Descripción', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(_desc),
        ],
      ]),
    );
  }
}

// ═════════════════════════ Favoritos

class FavoritosPagina extends StatelessWidget {
  const FavoritosPagina({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: ListenableBuilder(
        listenable: favoritos,
        builder: (context, _) {
          if (favoritos.canales.isEmpty && favoritos.emisoras.isEmpty) {
            return const Vacio('Sin favoritos', 'Toca la estrella ☆ de un canal o una emisora para guardarlo aquí.', Icons.star_border);
          }
          return ListView(children: [
            if (favoritos.emisoras.isNotEmpty) const _Titulo('Radio'),
            for (final e in [...favoritos.emisoras]) FilaEmisora(e),
            if (favoritos.canales.isNotEmpty) const _Titulo('TV'),
            for (final c in [...favoritos.canales]) FilaCanal(c),
          ]);
        },
      ),
    );
  }
}
