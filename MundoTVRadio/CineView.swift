import SwiftUI

// Películas y series gratis y LEGALES:
// 1) Internet Archive (archive.org): películas y series de dominio público o con permiso de libre difusión.
// 2) Canales de TV gratuitos de películas/series (iptv-org).
// 3) Servicios oficiales gratis con anuncios (Pluto TV, Tubi, Plex, ViX, Canela): se abren en su app/web.

struct Titulo: Identifiable, Hashable, Codable {
    let identifier: String
    let title: String
    let year: String?
    var id: String { identifier }
    var portada: URL? { URL(string: "https://archive.org/services/img/\(identifier)") }
}

struct ArchivoVideo: Identifiable, Hashable {
    let nombre: String
    let url: String
    var id: String { url }
}

struct ColeccionCine: Identifiable, Hashable {
    let titulo: String
    let consulta: String
    let icono: String
    var id: String { consulta }

    static let todas: [ColeccionCine] = [
        ColeccionCine(titulo: "Películas clásicas", consulta: "collection:(feature_films)", icono: "film"),
        ColeccionCine(titulo: "Películas en español", consulta: "collection:(feature_films) AND language:(spa OR Spanish OR español)", icono: "character.bubble"),
        ColeccionCine(titulo: "Recientes (2000 en adelante)", consulta: "collection:(feature_films OR independent_films OR moviesandfilms) AND year:[2000 TO 2030]", icono: "sparkles.tv"),
        ColeccionCine(titulo: "Series clásicas de TV", consulta: "collection:(classic_tv)", icono: "tv"),
        ColeccionCine(titulo: "Caricaturas clásicas", consulta: "collection:(classic_cartoons)", icono: "teddybear"),
        ColeccionCine(titulo: "Cine negro", consulta: "collection:(film_noir)", icono: "moon"),
        ColeccionCine(titulo: "Ciencia ficción y terror", consulta: "collection:(SciFi_Horror)", icono: "sparkles"),
        ColeccionCine(titulo: "Comedia", consulta: "collection:(comedy_films)", icono: "face.smiling"),
        ColeccionCine(titulo: "Cine mudo", consulta: "collection:(silent_films)", icono: "speaker.slash"),
    ]
}

actor ServicioArchive {
    static let shared = ServicioArchive()

    private struct Respuesta: Decodable {
        struct Cuerpo: Decodable { let docs: [Doc] }
        struct Doc: Decodable {
            let identifier: String
            let title: Texto?
            let year: Texto?
        }
        let response: Cuerpo
    }

    /// Algunos campos vienen como texto, número o lista según el título.
    private struct Texto: Decodable {
        let valor: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { valor = s }
            else if let n = try? c.decode(Int.self) { valor = String(n) }
            else if let l = try? c.decode([String].self) { valor = l.first ?? "" }
            else { valor = "" }
        }
    }

    func buscar(_ consulta: String, pagina: Int = 1) async throws -> [Titulo] {
        var comp = URLComponents(string: "https://archive.org/advancedsearch.php")!
        comp.queryItems = [
            URLQueryItem(name: "q", value: "(\(consulta)) AND mediatype:(movies)"),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "year"),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
            URLQueryItem(name: "rows", value: "60"),
            URLQueryItem(name: "page", value: String(pagina)),
            URLQueryItem(name: "output", value: "json"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comp.url!)
        let r = try JSONDecoder().decode(Respuesta.self, from: data)
        return r.response.docs.map {
            Titulo(identifier: $0.identifier, title: $0.title?.valor ?? $0.identifier, year: $0.year?.valor)
        }
    }

    /// Lista los videos que se pueden ver en el iPhone (.mp4) dentro de un título (una película o los episodios de una serie).
    func videos(de id: String) async throws -> (descripcion: String, videos: [ArchivoVideo]) {
        let url = URL(string: "https://archive.org/metadata/\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let meta = json["metadata"] as? [String: Any] ?? [:]
        var desc = (meta["description"] as? String) ?? ((meta["description"] as? [String])?.first ?? "")
        desc = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let archivos = json["files"] as? [[String: Any]] ?? []

        let mp4 = archivos.compactMap { f -> (String, String)? in
            guard let n = f["name"] as? String, n.lowercased().hasSuffix(".mp4") else { return nil }
            return (n, (f["format"] as? String) ?? "")
        }
        // Si hay varias versiones del mismo video, se prefiere h.264 / 512Kb.
        var porBase: [String: (String, Int)] = [:]
        for (n, formato) in mp4 {
            let base = n.replacingOccurrences(of: "_512kb", with: "")
                .replacingOccurrences(of: ".ia", with: "")
                .replacingOccurrences(of: ".mp4", with: "", options: [.caseInsensitive])
            let f = formato.lowercased()
            let prioridad = f.contains("h.264") ? 3 : (f.contains("512kb") ? 2 : 1)
            if (porBase[base]?.1 ?? 0) < prioridad { porBase[base] = (n, prioridad) }
        }
        let videos = porBase.values.map(\.0).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { n in
            let nombre = (n as NSString).deletingPathExtension
                .replacingOccurrences(of: "_512kb", with: "")
                .replacingOccurrences(of: "_", with: " ")
            let ruta = n.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? n
            return ArchivoVideo(nombre: nombre, url: "https://archive.org/download/\(id)/\(ruta)")
        }
        return (desc, videos)
    }
}

// MARK: - Pantallas

struct CineInicioView: View {
    private let servicios: [(String, String, String)] = [
        ("Pluto TV", "Cientos de canales y películas gratis, en español", "https://pluto.tv/latam"),
        ("Tubi", "Miles de películas y series gratis", "https://tubitv.com"),
        ("Plex", "Películas y TV en vivo gratis", "https://watch.plex.tv"),
        ("ViX", "Novelas, series y películas en español (versión gratis)", "https://vix.com"),
        ("Canela.TV", "Películas y series gratis en español", "https://www.canela.tv"),
        ("The Roku Channel", "Películas, series y TV en vivo gratis", "https://therokuchannel.roku.com"),
        ("YouTube: películas gratis", "Películas oficiales gratis con anuncios", "https://www.youtube.com/feed/storefront"),
        ("Kanopy", "Cine gratis con credencial de biblioteca", "https://www.kanopy.com"),
        ("Hoopla", "Películas y series con credencial de biblioteca", "https://www.hoopladigital.com"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ColeccionCine.todas) { c in
                        NavigationLink(value: c) { Label(c.titulo, systemImage: c.icono) }
                    }
                } header: {
                    Text("Ver aquí mismo (Internet Archive)")
                } footer: {
                    Text("Películas y series antiguas de dominio público o con permiso para verse gratis.")
                }

                Section("Canales de películas y series 24 horas") {
                    NavigationLink(value: FuenteTV.categorias.first { $0.ruta.contains("movies") }!) {
                        Label("Canales de películas", systemImage: "film.stack")
                    }
                    NavigationLink(value: FuenteTV.categorias.first { $0.ruta.contains("series") }!) {
                        Label("Canales de series", systemImage: "play.rectangle.on.rectangle")
                    }
                }

                Section {
                    ForEach(servicios, id: \.0) { s in
                        Link(destination: URL(string: s.2)!) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(s.0).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(s.1).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Estrenos y más: apps gratis oficiales")
                } footer: {
                    Text("Son gratis con anuncios y legales. Se abren en su app (si la tienes) o en su página.")
                }
            }
            .navigationTitle("Películas y series")
            .navigationDestination(for: ColeccionCine.self) { TitulosView(coleccion: $0) }
            .navigationDestination(for: FuenteTV.self) { CanalesView(fuente: $0) }
            .navigationDestination(for: Titulo.self) { DetalleTituloView(titulo: $0) }
            .conMiniReproductor()
        }
    }
}

struct TitulosView: View {
    let coleccion: ColeccionCine
    @State private var titulos: [Titulo] = []
    @State private var pagina = 1
    @State private var cargando = false
    @State private var hayMas = true
    @State private var error: String?
    @State private var texto = ""

    private let columnas = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        ScrollView {
            if let error, titulos.isEmpty {
                VistaError(mensaje: error) { Task { await cargar(reiniciar: true) } }
            }
            LazyVGrid(columns: columnas, spacing: 16) {
                ForEach(titulos) { t in
                    NavigationLink(value: t) {
                        VStack(alignment: .leading, spacing: 4) {
                            AsyncImage(url: t.portada) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color(.secondarySystemBackground).overlay(Image(systemName: "film").foregroundStyle(.secondary))
                            }
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(t.title).font(.caption.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                            if let y = t.year, !y.isEmpty { Text(y).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                    .onAppear { if t.id == titulos.last?.id { Task { await cargar() } } }
                }
            }
            .padding()
            if cargando { ProgressView().padding() }
        }
        .searchable(text: $texto, prompt: "Buscar en esta colección")
        .onSubmit(of: .search) { Task { await cargar(reiniciar: true) } }
        .onChange(of: texto) { _, nuevo in if nuevo.isEmpty { Task { await cargar(reiniciar: true) } } }
        .navigationTitle(coleccion.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .task { if titulos.isEmpty { await cargar() } }
    }

    private func cargar(reiniciar: Bool = false) async {
        if reiniciar { titulos = []; pagina = 1; hayMas = true }
        guard !cargando, hayMas else { return }
        cargando = true
        error = nil
        var q = coleccion.consulta
        let t = texto.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        if !t.isEmpty { q += " AND title:(\"\(t)\")" }
        do {
            let nuevos = try await ServicioArchive.shared.buscar(q, pagina: pagina)
            let ya = Set(titulos.map(\.id))
            titulos += nuevos.filter { !ya.contains($0.id) }
            hayMas = nuevos.count == 60
            pagina += 1
        } catch {
            self.error = "No se pudo conectar con Internet Archive."
        }
        cargando = false
    }
}

struct DetalleTituloView: View {
    let titulo: Titulo
    @EnvironmentObject private var video: ReproductorVideo
    @State private var descripcion = ""
    @State private var videos: [ArchivoVideo] = []
    @State private var cargando = true

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    AsyncImage(url: titulo.portada) { $0.resizable().scaledToFit() } placeholder: {
                        Color(.secondarySystemBackground)
                    }
                    .frame(width: 110, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(titulo.title).font(.headline)
                        if let y = titulo.year { Text(y).foregroundStyle(.secondary) }
                        if let v = videos.first {
                            Button {
                                video.reproducir(Canal(nombre: titulo.title, url: v.url, logo: nil, grupo: nil, userAgent: nil, referer: nil))
                            } label: {
                                Label(videos.count > 1 ? "Ver episodio 1" : "Ver ahora", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            if cargando {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if videos.isEmpty {
                Section { Text("Este título no tiene un video que el iPhone pueda reproducir.").foregroundStyle(.secondary) }
            }
            if videos.count > 1 {
                Section("Episodios / partes (\(videos.count))") {
                    ForEach(videos) { v in
                        Button {
                            video.reproducir(Canal(nombre: v.nombre, url: v.url, logo: nil, grupo: nil, userAgent: nil, referer: nil))
                        } label: {
                            Label(v.nombre, systemImage: "play.circle").foregroundStyle(.primary)
                        }
                    }
                }
            }
            if !descripcion.isEmpty {
                Section("Descripción") { Text(descripcion).font(.callout) }
            }
        }
        .navigationTitle(titulo.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let r = try? await ServicioArchive.shared.videos(de: titulo.identifier) {
                descripcion = r.descripcion
                videos = r.videos
            }
            cargando = false
        }
    }
}
