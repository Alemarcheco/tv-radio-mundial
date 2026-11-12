import SwiftUI

@main
struct MundoTVRadioApp: App {
    @StateObject private var favoritos = Favoritos()
    @ObservedObject private var radio = ReproductorRadio.shared
    @ObservedObject private var video = ReproductorVideo.shared

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environmentObject(favoritos)
                .environmentObject(radio)
                .environmentObject(video)
        }
    }
}

struct RaizView: View {
    @EnvironmentObject private var video: ReproductorVideo

    var body: some View {
        TabView {
            MapaView()
                .tabItem { Label("Mapa", systemImage: "globe.americas.fill") }
            TVInicioView()
                .tabItem { Label("TV", systemImage: "tv") }
            RadioInicioView()
                .tabItem { Label("Radio", systemImage: "radio") }
            FavoritosView()
                .tabItem { Label("Favoritos", systemImage: "star.fill") }
        }
        .tint(.green)
        .alert("Canal no disponible",
               isPresented: Binding(get: { video.error != nil }, set: { if !$0 { video.error = nil } })) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text(video.error ?? "")
        }
    }
}

// MARK: - Favoritos (se guardan en el iPhone)

@MainActor
final class Favoritos: ObservableObject {
    @Published private(set) var canales: [Canal] = []
    @Published private(set) var emisoras: [Emisora] = []

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "fav_canales"), let l = try? JSONDecoder().decode([Canal].self, from: data) { canales = l }
        if let data = d.data(forKey: "fav_emisoras"), let l = try? JSONDecoder().decode([Emisora].self, from: data) { emisoras = l }
    }

    func es(_ c: Canal) -> Bool { canales.contains { $0.url == c.url } }
    func es(_ e: Emisora) -> Bool { emisoras.contains { $0.id == e.id } }

    func alternar(_ c: Canal) {
        if es(c) { canales.removeAll { $0.url == c.url } } else { canales.append(c) }
        guardar()
    }

    func alternar(_ e: Emisora) {
        if es(e) { emisoras.removeAll { $0.id == e.id } } else { emisoras.append(e) }
        guardar()
    }

    func quitarCanales(_ i: IndexSet) { canales.remove(atOffsets: i); guardar() }
    func quitarEmisoras(_ i: IndexSet) { emisoras.remove(atOffsets: i); guardar() }

    private func guardar() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(canales), forKey: "fav_canales")
        d.set(try? JSONEncoder().encode(emisoras), forKey: "fav_emisoras")
    }
}

// MARK: - Piezas comunes

struct LogoView: View {
    let url: String?
    let icono: String

    var body: some View {
        Group {
            if let u = url, let link = URL(string: u) {
                AsyncImage(url: link) { fase in
                    if let img = fase.image {
                        img.resizable().scaledToFit()
                    } else {
                        Image(systemName: icono).foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: icono).foregroundStyle(.secondary)
            }
        }
        .frame(width: 46, height: 46)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MiniReproductor: View {
    @EnvironmentObject private var radio: ReproductorRadio

    var body: some View {
        if let e = radio.emisora {
            HStack(spacing: 12) {
                LogoView(url: e.favicon, icono: "radio")
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.nombreLimpio).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let err = radio.error {
                        Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                    } else if radio.cargando {
                        Text("Conectando…").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(radio.cancion ?? e.detalle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Button { radio.alternar() } label: {
                    Image(systemName: (radio.reproduciendo || radio.cargando) ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 40, height: 40)
                }
                Button { radio.detener() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 32, height: 40)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

extension View {
    func conMiniReproductor() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniReproductor() }
    }
}

struct FilaCanal: View {
    let canal: Canal
    @EnvironmentObject private var video: ReproductorVideo
    @EnvironmentObject private var favoritos: Favoritos

    var body: some View {
        HStack(spacing: 12) {
            Button { video.reproducir(canal) } label: {
                HStack(spacing: 12) {
                    LogoView(url: canal.logo, icono: "tv")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(canal.nombre).font(.body).lineLimit(2).foregroundStyle(.primary)
                        if let g = canal.grupo, !g.isEmpty {
                            Text(g).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { favoritos.alternar(canal) } label: {
                Image(systemName: favoritos.es(canal) ? "star.fill" : "star")
                    .foregroundStyle(favoritos.es(canal) ? .yellow : .secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct FilaEmisora: View {
    let emisora: Emisora
    @EnvironmentObject private var radio: ReproductorRadio
    @EnvironmentObject private var favoritos: Favoritos

    private var esActual: Bool { radio.emisora?.id == emisora.id }

    var body: some View {
        HStack(spacing: 12) {
            Button { esActual ? radio.alternar() : radio.reproducir(emisora) } label: {
                HStack(spacing: 12) {
                    LogoView(url: emisora.favicon, icono: "radio")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(emisora.nombreLimpio).font(.body).lineLimit(1).foregroundStyle(.primary)
                        Text(emisora.detalle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if esActual && radio.reproduciendo {
                        Image(systemName: "waveform").foregroundStyle(.green)
                    } else if esActual && radio.cargando {
                        ProgressView()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { favoritos.alternar(emisora) } label: {
                Image(systemName: favoritos.es(emisora) ? "star.fill" : "star")
                    .foregroundStyle(favoritos.es(emisora) ? .yellow : .secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct VistaError: View {
    let mensaje: String
    let reintentar: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Sin conexión", systemImage: "wifi.exclamationmark")
        } description: {
            Text(mensaje)
        } actions: {
            Button("Reintentar", action: reintentar).buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - TV

enum RutaTV: Hashable {
    case fuente(FuenteTV)
    case paises
}

struct TVInicioView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: RutaTV.fuente(.pais(Pais.actual))) {
                        Label("Canales de \(Pais.bandera(Pais.actual)) \(Pais.nombre(Pais.actual))", systemImage: "house")
                    }
                    NavigationLink(value: RutaTV.paises) {
                        Label("Elegir país", systemImage: "flag")
                    }
                    NavigationLink(value: RutaTV.fuente(.internacional)) {
                        Label("Canales internacionales", systemImage: "globe")
                    }
                    NavigationLink(value: RutaTV.fuente(.todos)) {
                        Label("Todos los canales del mundo", systemImage: "globe.americas.fill")
                    }
                }
                Section("Por tema") {
                    ForEach(FuenteTV.categorias) { f in
                        NavigationLink(value: RutaTV.fuente(f)) { Label(f.titulo, systemImage: f.icono) }
                    }
                }
                Section("Por idioma") {
                    ForEach(FuenteTV.idiomas) { f in
                        NavigationLink(value: RutaTV.fuente(f)) { Label(f.titulo, systemImage: f.icono) }
                    }
                }
                Section {
                    Text("Canales gratuitos y públicos de la lista abierta iptv-org. Algunos pueden estar caídos o bloqueados fuera de su país.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("TV del mundo")
            .navigationDestination(for: RutaTV.self) { ruta in
                switch ruta {
                case .fuente(let f): CanalesView(fuente: f)
                case .paises: PaisesTVView()
                }
            }
            .conMiniReproductor()
        }
    }
}

struct PaisesTVView: View {
    @State private var texto = ""

    private var lista: [Pais] {
        texto.isEmpty ? Pais.todos : Pais.todos.filter { $0.nombre.localizedCaseInsensitiveContains(texto) }
    }

    var body: some View {
        List(lista) { p in
            NavigationLink(value: RutaTV.fuente(.pais(p.codigo))) {
                Text("\(p.bandera)  \(p.nombre)")
            }
        }
        .searchable(text: $texto, prompt: "Buscar país")
        .navigationTitle("Países")
    }
}

struct CanalesView: View {
    let fuente: FuenteTV
    @State private var canales: [Canal] = []
    @State private var cargando = true
    @State private var error: String?
    @State private var texto = ""

    private var filtrados: [Canal] {
        guard !texto.isEmpty else { return canales }
        return canales.filter {
            $0.nombre.localizedCaseInsensitiveContains(texto) || ($0.grupo ?? "").localizedCaseInsensitiveContains(texto)
        }
    }

    var body: some View {
        Group {
            if cargando {
                ProgressView("Cargando canales…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VistaError(mensaje: error) { Task { await cargar() } }
            } else if canales.isEmpty {
                ContentUnavailableView("Sin canales", systemImage: "tv.slash",
                                       description: Text("No hay canales gratuitos conocidos para esta selección."))
            } else {
                List {
                    Section {
                        ForEach(filtrados) { FilaCanal(canal: $0) }
                    } header: {
                        Text("\(filtrados.count) canales")
                    }
                }
                .searchable(text: $texto, prompt: "Buscar canal")
            }
        }
        .navigationTitle(fuente.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .task { if canales.isEmpty { await cargar() } }
    }

    private func cargar() async {
        cargando = true
        error = nil
        do {
            canales = try await ServicioTV.shared.canales(fuente)
        } catch {
            self.error = "No se pudo descargar la lista de canales. Revisa tu internet."
        }
        cargando = false
    }
}

// MARK: - Radio

enum RutaRadio: Hashable {
    case filtro(FiltroRadio)
    case paises
    case generos
}

struct RadioInicioView: View {
    @State private var busqueda = ""
    @State private var resultados: [Emisora] = []
    @State private var buscando = false

    var body: some View {
        NavigationStack {
            List {
                if busqueda.trimmingCharacters(in: .whitespaces).count >= 2 {
                    Section(buscando ? "Buscando…" : "\(resultados.count) resultados") {
                        ForEach(resultados) { FilaEmisora(emisora: $0) }
                    }
                } else {
                    Section {
                        NavigationLink(value: RutaRadio.filtro(.delPais(Pais.actual))) {
                            Label("Emisoras de \(Pais.bandera(Pais.actual)) \(Pais.nombre(Pais.actual))", systemImage: "house")
                        }
                        NavigationLink(value: RutaRadio.filtro(.masEscuchadas)) {
                            Label("Más escuchadas del mundo", systemImage: "flame")
                        }
                    }
                    Section {
                        NavigationLink(value: RutaRadio.paises) { Label("Por país", systemImage: "flag") }
                        NavigationLink(value: RutaRadio.generos) { Label("Por género", systemImage: "music.note.list") }
                    }
                    Section {
                        Text("Más de 40.000 emisoras de todo el mundo, del directorio libre Radio Browser. Sigue sonando con la pantalla bloqueada.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $busqueda, prompt: "Buscar emisora en todo el mundo")
            .task(id: busqueda) { await buscar() }
            .navigationTitle("Radio del mundo")
            .navigationDestination(for: RutaRadio.self) { ruta in
                switch ruta {
                case .filtro(let f): EmisorasView(filtro: f)
                case .paises: PaisesRadioView()
                case .generos: GenerosRadioView()
                }
            }
            .conMiniReproductor()
        }
    }

    private func buscar() async {
        let t = busqueda.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { resultados = []; return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled else { return }
        buscando = true
        let r = (try? await ServicioRadio.shared.emisoras(FiltroRadio(titulo: t, nombre: t), cantidad: 150)) ?? []
        guard !Task.isCancelled else { return }
        resultados = r
        buscando = false
    }
}

struct EmisorasView: View {
    let filtro: FiltroRadio
    @State private var emisoras: [Emisora] = []
    @State private var cargando = false
    @State private var hayMas = true
    @State private var error: String?
    @State private var texto = ""

    private var filtradas: [Emisora] {
        guard !texto.isEmpty else { return emisoras }
        return emisoras.filter { $0.name.localizedCaseInsensitiveContains(texto) || ($0.tags ?? "").localizedCaseInsensitiveContains(texto) }
    }

    var body: some View {
        Group {
            if emisoras.isEmpty && cargando {
                ProgressView("Cargando emisoras…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if emisoras.isEmpty, let error {
                VistaError(mensaje: error) { Task { await cargarMas() } }
            } else if emisoras.isEmpty && !hayMas {
                ContentUnavailableView("Sin emisoras", systemImage: "radio",
                                       description: Text("No se encontraron emisoras para esta selección."))
            } else {
                List {
                    ForEach(filtradas) { e in
                        FilaEmisora(emisora: e)
                            .onAppear { if e.id == emisoras.last?.id { Task { await cargarMas() } } }
                    }
                    if cargando && !emisoras.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                }
                .searchable(text: $texto, prompt: "Filtrar")
            }
        }
        .navigationTitle(filtro.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .task { if emisoras.isEmpty { await cargarMas() } }
    }

    private func cargarMas() async {
        guard !cargando, hayMas else { return }
        cargando = true
        error = nil
        do {
            let nuevas = try await ServicioRadio.shared.emisoras(filtro, desde: emisoras.count, cantidad: 100)
            let ya = Set(emisoras.map(\.id))
            emisoras += nuevas.filter { !ya.contains($0.id) }
            hayMas = nuevas.count == 100
        } catch {
            self.error = "No se pudo conectar con el directorio de radios. Revisa tu internet."
        }
        cargando = false
    }
}

struct PaisesRadioView: View {
    @State private var paises: [PaisRadio] = []
    @State private var error: String?
    @State private var texto = ""

    private var lista: [PaisRadio] {
        let ordenados = paises.sorted { Pais.nombre($0.iso_3166_1).localizedCompare(Pais.nombre($1.iso_3166_1)) == .orderedAscending }
        guard !texto.isEmpty else { return ordenados }
        return ordenados.filter { Pais.nombre($0.iso_3166_1).localizedCaseInsensitiveContains(texto) || $0.name.localizedCaseInsensitiveContains(texto) }
    }

    var body: some View {
        Group {
            if let error, paises.isEmpty {
                VistaError(mensaje: error) { Task { await cargar() } }
            } else if paises.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(lista, id: \.iso_3166_1) { p in
                    NavigationLink(value: RutaRadio.filtro(.delPais(p.iso_3166_1))) {
                        HStack {
                            Text("\(Pais.bandera(p.iso_3166_1))  \(Pais.nombre(p.iso_3166_1))")
                            Spacer()
                            Text("\(p.stationcount)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .searchable(text: $texto, prompt: "Buscar país")
            }
        }
        .navigationTitle("Países")
        .task { if paises.isEmpty { await cargar() } }
    }

    private func cargar() async {
        error = nil
        do { paises = try await ServicioRadio.shared.paises() } catch { self.error = "No se pudo cargar la lista de países." }
    }
}

struct GenerosRadioView: View {
    @State private var generos: [GeneroRadio] = []
    @State private var error: String?
    @State private var texto = ""

    private var lista: [GeneroRadio] {
        texto.isEmpty ? generos : generos.filter { $0.name.localizedCaseInsensitiveContains(texto) }
    }

    var body: some View {
        Group {
            if let error, generos.isEmpty {
                VistaError(mensaje: error) { Task { await cargar() } }
            } else if generos.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(lista, id: \.name) { g in
                    NavigationLink(value: RutaRadio.filtro(FiltroRadio(titulo: g.name.capitalized, genero: g.name))) {
                        HStack {
                            Text(g.name.capitalized)
                            Spacer()
                            Text("\(g.stationcount)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .searchable(text: $texto, prompt: "Buscar género (rock, salsa, news…)")
            }
        }
        .navigationTitle("Géneros")
        .task { if generos.isEmpty { await cargar() } }
    }

    private func cargar() async {
        error = nil
        do { generos = try await ServicioRadio.shared.generos() } catch { self.error = "No se pudo cargar la lista de géneros." }
    }
}

// MARK: - Favoritos

struct FavoritosView: View {
    @EnvironmentObject private var favoritos: Favoritos

    var body: some View {
        NavigationStack {
            Group {
                if favoritos.canales.isEmpty && favoritos.emisoras.isEmpty {
                    ContentUnavailableView("Sin favoritos", systemImage: "star",
                                           description: Text("Toca la estrella ☆ de un canal o una emisora para guardarlo aquí."))
                } else {
                    List {
                        if !favoritos.emisoras.isEmpty {
                            Section("Radio") {
                                ForEach(favoritos.emisoras) { FilaEmisora(emisora: $0) }
                                    .onDelete { favoritos.quitarEmisoras($0) }
                            }
                        }
                        if !favoritos.canales.isEmpty {
                            Section("TV") {
                                ForEach(favoritos.canales) { FilaCanal(canal: $0) }
                                    .onDelete { favoritos.quitarCanales($0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Favoritos")
            .conMiniReproductor()
        }
    }
}
