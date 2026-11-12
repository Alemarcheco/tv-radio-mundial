import 'package:flutter/material.dart';

import 'modelos.dart';
import 'reproductor.dart';

final radio = RadioMundo.instancia;
final favoritos = Favoritos.instancia;

class Logo extends StatelessWidget {
  final String? url;
  final IconData icono;
  final double tam;
  const Logo({super.key, this.url, required this.icono, this.tam = 46});

  @override
  Widget build(BuildContext context) {
    final fondo = Theme.of(context).colorScheme.surfaceContainerHighest;
    final reserva = Icon(icono, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: tam,
        height: tam,
        color: fondo,
        child: url == null
            ? reserva
            : Image.network(url!, fit: BoxFit.contain, errorBuilder: (_, _, _) => reserva),
      ),
    );
  }
}

class FilaCanal extends StatelessWidget {
  final Canal canal;
  const FilaCanal(this.canal, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: favoritos,
      builder: (context, _) {
        final fav = favoritos.esCanal(canal);
        return ListTile(
          leading: Logo(url: canal.logo, icono: Icons.tv),
          title: Text(canal.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: (canal.grupo ?? '').isEmpty ? null : Text(canal.grupo!, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
            onPressed: () => favoritos.alternarCanal(canal),
          ),
          onTap: () => Video.abrir(context, canal),
        );
      },
    );
  }
}

class FilaEmisora extends StatelessWidget {
  final Emisora emisora;
  const FilaEmisora(this.emisora, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([favoritos, radio]),
      builder: (context, _) {
        final fav = favoritos.esEmisora(emisora);
        final actual = radio.emisora?.uuid == emisora.uuid;
        return ListTile(
          leading: Logo(url: emisora.favicon, icono: Icons.radio),
          title: Text(emisora.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(emisora.detalle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (actual && radio.reproduciendo) const Icon(Icons.graphic_eq, color: Colors.green),
            if (actual && radio.cargando)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            IconButton(
              icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? Colors.amber : null),
              onPressed: () => favoritos.alternarEmisora(emisora),
            ),
          ]),
          onTap: () => actual ? radio.alternar() : radio.reproducir(emisora),
        );
      },
    );
  }
}

class MiniReproductor extends StatelessWidget {
  const MiniReproductor({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: radio,
      builder: (context, _) {
        final e = radio.emisora;
        if (e == null) return const SizedBox.shrink();
        final sub = radio.error ?? (radio.cargando ? 'Conectando…' : (radio.cancion ?? e.detalle));
        return Material(
          elevation: 6,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                Logo(url: e.favicon, icono: Icons.radio, tam: 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(e.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: radio.error != null ? Colors.red : Theme.of(context).hintColor)),
                  ]),
                ),
                IconButton(
                  iconSize: 32,
                  icon: Icon((radio.reproduciendo || radio.cargando) ? Icons.pause_circle_filled : Icons.play_circle_filled),
                  onPressed: radio.alternar,
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: radio.detener),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class VistaError extends StatelessWidget {
  final String mensaje;
  final VoidCallback reintentar;
  const VistaError(this.mensaje, this.reintentar, {super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off, size: 48),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: reintentar, child: const Text('Reintentar')),
          ]),
        ),
      );
}

class Vacio extends StatelessWidget {
  final String titulo, texto;
  final IconData icono;
  const Vacio(this.titulo, this.texto, this.icono, {super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(texto, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
          ]),
        ),
      );
}

/// Campo de búsqueda simple para filtrar listas.
class CampoFiltro extends StatelessWidget {
  final String pista;
  final ValueChanged<String> alCambiar;
  final ValueChanged<String>? alEnviar;
  final bool autofocus;
  const CampoFiltro({super.key, required this.pista, required this.alCambiar, this.alEnviar, this.autofocus = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          autofocus: autofocus,
          decoration: InputDecoration(
            hintText: pista,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          ),
          textInputAction: TextInputAction.search,
          onChanged: alCambiar,
          onSubmitted: alEnviar,
        ),
      );
}

void ir(BuildContext context, Widget pagina) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => pagina));
