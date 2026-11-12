import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'comunes.dart';
import 'listas.dart';
import 'mapa.dart';
import 'modelos.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.alemarcheco.tv_radio_mundial.radio',
    androidNotificationChannelName: 'Radio',
    androidNotificationOngoing: true,
  );
  final region = PlatformDispatcher.instance.locale.countryCode;
  if (region != null && region.length == 2) Paises.actual = region.toUpperCase();
  favoritos.cargar();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TV y Radio Mundial',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.green, brightness: Brightness.dark, useMaterial3: true),
      home: const Inicio(),
    );
  }
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});
  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  int _i = 0;

  static const _paginas = [MapaPagina(), TVInicio(), RadioInicio(), CineInicio(), FavoritosPagina()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _i, children: _paginas),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniReproductor(),
        NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (i) => setState(() => _i = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.public), label: 'Mapa'),
            NavigationDestination(icon: Icon(Icons.tv), label: 'TV'),
            NavigationDestination(icon: Icon(Icons.radio), label: 'Radio'),
            NavigationDestination(icon: Icon(Icons.movie), label: 'Cine'),
            NavigationDestination(icon: Icon(Icons.star), label: 'Favoritos'),
          ],
        ),
      ]),
    );
  }
}
