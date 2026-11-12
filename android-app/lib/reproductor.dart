import 'dart:async';
import 'dart:convert';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'modelos.dart';
import 'servicios.dart';

// ───────────────────────── Radio (sigue sonando con la pantalla apagada, con controles en la notificación)

class RadioMundo extends ChangeNotifier {
  RadioMundo._() {
    _player.playerStateStream.listen((s) {
      reproduciendo = s.playing && s.processingState == ProcessingState.ready;
      cargando = s.playing && (s.processingState == ProcessingState.loading || s.processingState == ProcessingState.buffering);
      notifyListeners();
    });
    _player.icyMetadataStream.listen((m) {
      final t = m?.info?.title?.trim();
      if (t != null && t.isNotEmpty) {
        cancion = t;
        notifyListeners();
      }
    });
  }
  static final RadioMundo instancia = RadioMundo._();

  final AudioPlayer _player = AudioPlayer();
  Emisora? emisora;
  bool reproduciendo = false;
  bool cargando = false;
  String? cancion;
  String? error;

  Future<void> reproducir(Emisora e) async {
    await Video.pausarTodo();
    emisora = e;
    cancion = null;
    error = null;
    cargando = true;
    notifyListeners();
    try {
      await _player.setAudioSource(AudioSource.uri(
        Uri.parse(e.url),
        tag: MediaItem(
          id: e.uuid.isEmpty ? e.url : e.uuid,
          title: e.nombre,
          artist: e.pais ?? 'Radio',
          artUri: e.favicon != null ? Uri.tryParse(e.favicon!) : null,
        ),
      ));
      _player.play();
      ServicioRadio.registrarEscucha(e.uuid);
    } catch (_) {
      cargando = false;
      error = 'No se pudo conectar con ${e.nombre}. Puede que esté fuera del aire; prueba otra.';
      notifyListeners();
    }
  }

  void alternar() {
    if (_player.playing) {
      _player.pause();
    } else if (emisora != null) {
      reproducir(emisora!); // en vivo: se reconecta para no quedar atrasado
    }
  }

  Future<void> pausar() async {
    if (_player.playing) await _player.pause();
  }

  Future<void> detener() async {
    await _player.stop();
    emisora = null;
    cancion = null;
    error = null;
    notifyListeners();
  }
}

// ───────────────────────── Video (TV en vivo y películas)

class Video {
  static VideoPlayerController? _actual;

  static Future<void> pausarTodo() async {
    try {
      await _actual?.pause();
    } catch (_) {}
  }

  static Future<void> abrir(BuildContext context, Canal canal, {bool enVivo = true}) async {
    await RadioMundo.instancia.pausar();
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PantallaVideo(canal: canal, enVivo: enVivo),
    ));
  }
}

class PantallaVideo extends StatefulWidget {
  final Canal canal;
  final bool enVivo;
  const PantallaVideo({super.key, required this.canal, this.enVivo = true});

  @override
  State<PantallaVideo> createState() => _PantallaVideoState();
}

class _PantallaVideoState extends State<PantallaVideo> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final c = widget.canal;
    final cabeceras = <String, String>{
      if (c.userAgent != null) 'User-Agent': c.userAgent!,
      if (c.referer != null) 'Referer': c.referer!,
    };
    final v = VideoPlayerController.networkUrl(Uri.parse(c.url), httpHeaders: cabeceras);
    _video = v;
    Video._actual = v;
    try {
      await v.initialize().timeout(const Duration(seconds: 25));
      if (!mounted) return;
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: v,
          autoPlay: true,
          isLive: widget.enVivo,
          allowFullScreen: true,
          allowMuting: true,
          aspectRatio: v.value.aspectRatio > 0 ? v.value.aspectRatio : 16 / 9,
          errorBuilder: (context, mensaje) => _mensajeError(),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = widget.enVivo
          ? '«${c.nombre}» no está transmitiendo ahora o no está disponible en tu país. Prueba otro canal.'
          : 'No se pudo abrir este video. Prueba otro.');
    }
  }

  Widget _mensajeError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? 'Este canal no está disponible ahora. Prueba otro.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      );

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    if (Video._actual == _video) Video._actual = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.canal.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: _error != null
            ? _mensajeError()
            : _chewie == null
                ? const CircularProgressIndicator(color: Colors.white)
                : Chewie(controller: _chewie!),
      ),
    );
  }
}

// ───────────────────────── Favoritos (se guardan en el teléfono)

class Favoritos extends ChangeNotifier {
  Favoritos._();
  static final Favoritos instancia = Favoritos._();

  List<Canal> canales = [];
  List<Emisora> emisoras = [];

  Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    try {
      canales = (jsonDecode(p.getString('fav_canales') ?? '[]') as List)
          .map((e) => Canal.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      emisoras = (jsonDecode(p.getString('fav_emisoras') ?? '[]') as List)
          .map((e) => Emisora.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {}
    notifyListeners();
  }

  bool esCanal(Canal c) => canales.any((x) => x.url == c.url);
  bool esEmisora(Emisora e) => emisoras.any((x) => x.uuid == e.uuid);

  void alternarCanal(Canal c) {
    esCanal(c) ? canales.removeWhere((x) => x.url == c.url) : canales.add(c);
    _guardar();
  }

  void alternarEmisora(Emisora e) {
    esEmisora(e) ? emisoras.removeWhere((x) => x.uuid == e.uuid) : emisoras.add(e);
    _guardar();
  }

  Future<void> _guardar() async {
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('fav_canales', jsonEncode(canales.map((e) => e.toJson()).toList()));
    await p.setString('fav_emisoras', jsonEncode(emisoras.map((e) => e.toJson()).toList()));
  }
}
