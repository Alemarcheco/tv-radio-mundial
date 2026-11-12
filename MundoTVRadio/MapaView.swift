import SwiftUI
import MapKit

enum ModoMapa: String, CaseIterable, Identifiable {
    case radio = "Radio"
    case tv = "TV"
    var id: String { rawValue }
}

struct PinPais: Identifiable {
    let codigo: String
    let coord: CLLocationCoordinate2D
    var id: String { codigo }
}

struct PuntoRadio: Identifiable {
    let emisora: Emisora
    let coord: CLLocationCoordinate2D
    var id: String { emisora.id }
}

/// Un punto del mapa que agrupa las emisoras o canales de un estado / provincia / región.
struct RegionMapa: Identifiable {
    let id: String
    let nombre: String
    let pais: String
    let coord: CLLocationCoordinate2D
    let cantidad: Int
    var emisoras: [Emisora] = []
    var fuente: FuenteTV? = nil
    var esNacional = false
}

enum HojaMapa: Identifiable {
    case regionRadio(RegionMapa)
    case canales(FuenteTV)
    case listaPais(FiltroRadio)

    var id: String {
        switch self {
        case .regionRadio(let r): return "r-" + r.id
        case .canales(let f): return "t-" + f.ruta
        case .listaPais(let f): return "l-" + f.id
        }
    }
}

extension Emisora {
    var coordenada: CLLocationCoordinate2D? {
        guard let la = geo_lat, let lo = geo_long, abs(la) <= 90, abs(lo) <= 180, la != 0 || lo != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }
}

// MARK: - Ubicar regiones por nombre (con caché en el iPhone)

@MainActor
final class Geocodificador {
    static let shared = Geocodificador()
    private let clave = "geo_cache_v1"
    private var cache: [String: [Double]]
    private var fallidos = Set<String>()
    private let geo = CLGeocoder()
    private var ocupado = false

    init() {
        cache = (UserDefaults.standard.dictionary(forKey: clave) as? [String: [Double]]) ?? [:]
    }

    func coordenada(_ consulta: String) async -> CLLocationCoordinate2D? {
        if let c = cache[consulta], c.count == 2 { return CLLocationCoordinate2D(latitude: c[0], longitude: c[1]) }
        if fallidos.contains(consulta) { return nil }
        while ocupado { try? await Task.sleep(nanoseconds: 150_000_000) }
        if let c = cache[consulta], c.count == 2 { return CLLocationCoordinate2D(latitude: c[0], longitude: c[1]) }
        ocupado = true
        defer { ocupado = false }
        do {
            let marcas = try await geo.geocodeAddressString(consulta)
            if let l = marcas.first?.location?.coordinate {
                cache[consulta] = [l.latitude, l.longitude]
                UserDefaults.standard.set(cache, forKey: clave)
                return l
            }
            fallidos.insert(consulta)
        } catch {
            // Apple limita las búsquedas por minuto: se espera un poco antes de la siguiente.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        return nil
    }
}

// MARK: - Datos del mapa

@MainActor
final class ModeloMapa: ObservableObject {
    @Published private(set) var regionesRadio: [String: [RegionMapa]] = [:]
    @Published private(set) var regionesTV: [String: [RegionMapa]] = [:]
    @Published private(set) var emisorasConPunto: [PuntoRadio] = []
    @Published private(set) var cargando: String?
    @Published private(set) var pinesRadio: [PinPais] = []

    let pinesTV: [PinPais] = CentrosPaises.datos.keys.sorted().compactMap { c in
        CentrosPaises.centro(c).map { PinPais(codigo: c, coord: $0) }
    }

    private var paisesConRadio: [PaisRadio] = []
    private var emisorasPorPais: [String: [Emisora]] = [:]
    private var enCurso = Set<String>()

    func cargarPaises() async {
        guard paisesConRadio.isEmpty else { return }
        if let lista = try? await ServicioRadio.shared.paises() {
            paisesConRadio = lista
            pinesRadio = lista.compactMap { p in
                CentrosPaises.centro(p.iso_3166_1).map { PinPais(codigo: p.iso_3166_1.uppercased(), coord: $0) }
            }
        } else {
            pinesRadio = pinesTV
        }
    }

    func cargar(_ pais: String, modo: ModoMapa) async {
        switch modo {
        case .radio: await cargarRadio(pais)
        case .tv: await cargarTV(pais)
        }
    }

    // Radio: se agrupan las emisoras por el estado/provincia que indica Radio Browser.
    @discardableResult
    func cargarRadio(_ pais: String) async -> [Emisora] {
        let p = pais.uppercased()
        if let ya = emisorasPorPais[p] { return ya }
        let clave = "radio-" + p
        guard !enCurso.contains(clave) else { return [] }
        enCurso.insert(clave)
        defer { enCurso.remove(clave) }
        cargando = "Buscando emisoras de \(Pais.nombre(p))…"
        defer { cargando = nil }

        guard let lista = try? await ServicioRadio.shared.emisorasDelPais(p) else { return [] }
        emisorasPorPais[p] = lista
        emisorasConPunto = emisorasPorPais.values.flatMap { $0 }.compactMap { e in
            e.coordenada.map { PuntoRadio(emisora: e, coord: $0) }
        }

        var grupos: [String: [Emisora]] = [:]
        var nombres: [String: String] = [:]
        for e in lista {
            let original = (e.state ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let k = original.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            grupos[k, default: []].append(e)
            if nombres[k] == nil { nombres[k] = original }
        }

        var regiones: [RegionMapa] = []
        var sinUbicar: [(String, [Emisora])] = []
        for (k, es) in grupos {
            if k.isEmpty {
                if let c = CentrosPaises.centro(p) {
                    regiones.append(RegionMapa(id: "radio-\(p)-nacional", nombre: "Sin región indicada", pais: p,
                                               coord: c, cantidad: es.count, emisoras: es, esNacional: true))
                }
                continue
            }
            if let c = Self.centroMediano(es.compactMap(\.coordenada)) {
                regiones.append(RegionMapa(id: "radio-\(p)-\(k)", nombre: nombres[k] ?? k, pais: p,
                                           coord: c, cantidad: es.count, emisoras: es))
            } else {
                sinUbicar.append((k, es))
            }
        }
        regionesRadio[p] = regiones

        // Regiones sin coordenadas: se buscan por nombre (las más grandes primero).
        for (k, es) in sinUbicar.sorted(by: { $0.1.count > $1.1.count }).prefix(60) {
            let nombre = nombres[k] ?? k
            if let c = await Geocodificador.shared.coordenada("\(nombre), \(Pais.nombre(p))") {
                regionesRadio[p, default: []].append(RegionMapa(id: "radio-\(p)-\(k)", nombre: nombre, pais: p,
                                                                coord: c, cantidad: es.count, emisoras: es))
            } else if let i = regionesRadio[p]?.firstIndex(where: { $0.esNacional }), var nac = regionesRadio[p]?[i] {
                nac.emisoras += es
                regionesRadio[p]?[i] = RegionMapa(id: nac.id, nombre: nac.nombre, pais: p, coord: nac.coord,
                                                  cantidad: nac.emisoras.count, emisoras: nac.emisoras, esNacional: true)
            }
        }
        return lista
    }

    // TV: un punto con todos los canales del país + un punto por cada estado/región que tenga canales locales.
    func cargarTV(_ pais: String) async {
        let p = pais.uppercased()
        guard regionesTV[p] == nil else { return }
        let clave = "tv-" + p
        guard !enCurso.contains(clave) else { return }
        enCurso.insert(clave)
        defer { enCurso.remove(clave) }
        cargando = "Buscando canales de \(Pais.nombre(p))…"
        defer { cargando = nil }

        let fuentePais = FuenteTV.pais(p)
        let total = (try? await ServicioTV.shared.canales(fuentePais))?.count ?? 0
        var regiones: [RegionMapa] = []
        if let c = CentrosPaises.centro(p), total > 0 {
            regiones.append(RegionMapa(id: "tv-\(p)-nacional", nombre: "Todo \(Pais.nombre(p))", pais: p,
                                       coord: c, cantidad: total, fuente: fuentePais, esNacional: true))
        }
        regionesTV[p] = regiones

        let subdivisiones = await ServicioRegionesTV.shared.subdivisiones(de: p)
        let conCanales: [(SubdivisionTV, FuenteTV, Int)] = await withTaskGroup(of: (SubdivisionTV, FuenteTV, Int).self) { grupo in
            for s in subdivisiones {
                grupo.addTask {
                    let f = FuenteTV(titulo: s.nombre, ruta: "subdivisions/\(s.codigo.lowercased()).m3u", icono: "mappin")
                    let n = (try? await ServicioTV.shared.canales(f))?.count ?? 0
                    return (s, f, n)
                }
            }
            var r: [(SubdivisionTV, FuenteTV, Int)] = []
            for await x in grupo where x.2 > 0 { r.append(x) }
            return r
        }

        for (s, f, n) in conCanales.sorted(by: { $0.2 > $1.2 }) {
            if let c = await Geocodificador.shared.coordenada("\(s.nombre), \(Pais.nombre(p))") {
                regionesTV[p, default: []].append(RegionMapa(id: "tv-\(s.codigo)", nombre: s.nombre, pais: p,
                                                             coord: c, cantidad: n, fuente: f))
            }
        }
    }

    private static func centroMediano(_ puntos: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !puntos.isEmpty else { return nil }
        let lats = puntos.map(\.latitude).sorted()
        let lons = puntos.map(\.longitude).sorted()
        return CLLocationCoordinate2D(latitude: lats[lats.count / 2], longitude: lons[lons.count / 2])
    }

    func paisMasCercano(a punto: CLLocationCoordinate2D) -> String? {
        let pines = pinesRadio.isEmpty ? pinesTV : pinesRadio
        return pines.min { distancia($0.coord, punto) < distancia($1.coord, punto) }?.codigo
    }

    private func distancia(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        var dLon = abs(a.longitude - b.longitude)
        if dLon > 180 { dLon = 360 - dLon }
        let dLat = a.latitude - b.latitude
        return dLat * dLat + dLon * dLon * pow(cos(b.latitude * .pi / 180), 2)
    }

    /// Elige un país al azar (los que tienen más emisoras salen más seguido).
    func paisAlAzar() -> String? {
        let candidatos = paisesConRadio.filter { CentrosPaises.centro($0.iso_3166_1) != nil }
        guard !candidatos.isEmpty else { return pinesTV.randomElement()?.codigo }
        let total = candidatos.reduce(0) { $0 + Int(sqrt(Double($1.stationcount))) + 1 }
        var r = Int.random(in: 0..<max(total, 1))
        for p in candidatos {
            r -= Int(sqrt(Double(p.stationcount))) + 1
            if r < 0 { return p.iso_3166_1.uppercased() }
        }
        return candidatos.last?.iso_3166_1.uppercased()
    }
}

// MARK: - Pantalla del mapa

struct MapaView: View {
    @EnvironmentObject private var radio: ReproductorRadio
    @StateObject private var modelo = ModeloMapa()

    @State private var modo: ModoMapa = .radio
    @State private var satelite = true
    @State private var posicion: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CentrosPaises.centro(Pais.actual) ?? CLLocationCoordinate2D(latitude: 20, longitude: -30),
        distance: 22_000_000))
    @State private var region: MKCoordinateRegion?
    @State private var paisEnfocado: String?
    @State private var hoja: HojaMapa?
    @State private var buscarAbierto = false

    private var zoomLat: Double { region?.span.latitudeDelta ?? 180 }
    private var colorModo: Color { modo == .radio ? .green : .orange }

    private func enVista(_ c: CLLocationCoordinate2D, margen: Double = 1.2) -> Bool {
        guard let r = region else { return true }
        let dLat = r.span.latitudeDelta / 2 * margen
        let dLon = r.span.longitudeDelta / 2 * margen
        var lon = abs(c.longitude - r.center.longitude)
        if lon > 180 { lon = 360 - lon }
        return abs(c.latitude - r.center.latitude) <= dLat && lon <= dLon
    }

    private var regionesVisibles: [RegionMapa] {
        guard zoomLat <= 40 else { return [] }
        if modo == .radio && zoomLat < 8 { return ciudadesVisibles }
        let todas = (modo == .radio ? modelo.regionesRadio : modelo.regionesTV).values.flatMap { $0 }
        return todas.filter { enVista($0.coord) }
    }

    /// Al acercarse, las emisoras se agrupan por ciudad/zona (cuadrícula según el zoom).
    private var ciudadesVisibles: [RegionMapa] {
        guard zoomLat >= 1.5 else { return [] }
        let g = max(zoomLat / 10, 0.05)
        var grupos: [String: [PuntoRadio]] = [:]
        for p in modelo.emisorasConPunto where enVista(p.coord) {
            let k = "\(Int(floor(p.coord.latitude / g)))_\(Int(floor(p.coord.longitude / g)))"
            grupos[k, default: []].append(p)
        }
        return grupos.map { k, ps in
            let lat = ps.map(\.coord.latitude).reduce(0, +) / Double(ps.count)
            let lon = ps.map(\.coord.longitude).reduce(0, +) / Double(ps.count)
            var conteo: [String: Int] = [:]
            for p in ps { if let st = p.emisora.state, !st.isEmpty { conteo[st, default: 0] += 1 } }
            let nombre = conteo.max { $0.value < $1.value }?.key ?? "Emisoras de esta zona"
            return RegionMapa(id: "zona-\(g)-\(k)", nombre: nombre, pais: ps[0].emisora.countrycode ?? "",
                              coord: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                              cantidad: ps.count, emisoras: ps.map(\.emisora))
        }
    }

    private var puntosVisibles: [PuntoRadio] {
        guard modo == .radio, zoomLat < 1.5 else { return [] }
        var r: [PuntoRadio] = []
        for p in modelo.emisorasConPunto where enVista(p.coord, margen: 1) {
            r.append(p)
            if r.count >= 400 { break }
        }
        return r
    }

    private var pines: [PinPais] {
        guard zoomLat > 25 else { return [] }
        return modo == .tv ? modelo.pinesTV : modelo.pinesRadio
    }

    var body: some View {
        NavigationStack {
            Map(position: $posicion) {
                ForEach(puntosVisibles) { punto in
                    Annotation(punto.emisora.nombreLimpio, coordinate: punto.coord, anchor: .center) {
                        PuntoEmisora(activa: radio.emisora?.id == punto.id)
                            .onTapGesture { radio.reproducir(punto.emisora) }
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(regionesVisibles) { r in
                    Annotation(r.nombre, coordinate: r.coord, anchor: .center) {
                        BurbujaRegion(region: r, color: colorModo, mostrarNombre: zoomLat < 18 && zoomLat >= 8)
                            .onTapGesture { tocarRegion(r) }
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(pines) { p in
                    Annotation(Pais.nombre(p.codigo), coordinate: p.coord, anchor: .center) {
                        Button { enfocar(p.codigo) } label: {
                            Text(Pais.bandera(p.codigo))
                                .font(.title3)
                                .padding(5)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(colorModo, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(satelite ? .imagery(elevation: .realistic) : .standard(elevation: .realistic, emphasis: .muted))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                region = ctx.region
                guard ctx.region.span.latitudeDelta <= 40,
                      let p = modelo.paisMasCercano(a: ctx.region.center) else { return }
                paisEnfocado = p
                let m = modo
                Task { await modelo.cargar(p, modo: m) }
            }
            .safeAreaInset(edge: .top) { barraSuperior }
            .overlay(alignment: .bottom) { tarjetaInferior }
            .task { await modelo.cargarPaises() }
            .onChange(of: modo) { _, nuevo in
                if let p = paisEnfocado, zoomLat <= 40 { Task { await modelo.cargar(p, modo: nuevo) } }
            }
            .sheet(item: $hoja) { h in
                NavigationStack {
                    Group {
                        switch h {
                        case .regionRadio(let r): ListaEmisorasView(titulo: r.nombre, emisoras: r.emisoras)
                        case .canales(let f): CanalesView(fuente: f)
                        case .listaPais(let f): EmisorasView(filtro: f)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { hoja = nil } }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $buscarAbierto) {
                BusquedaGlobalView { lugar, pais, esCiudad in
                    buscarAbierto = false
                    if let pais { paisEnfocado = pais }
                    volar(a: lugar, distancia: esCiudad ? 250_000 : 3_500_000)
                    if let pais { let m = modo; Task { await modelo.cargar(pais, modo: m) } }
                }
                .presentationDetents([.large])
            }
            .toolbar(.hidden, for: .navigationBar)
            .conMiniReproductor()
        }
    }

    private var barraSuperior: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("Modo", selection: $modo) {
                    ForEach(ModoMapa.allCases) { m in
                        Text(m == .radio ? "📻 Radio" : "📺 TV").tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Button { satelite.toggle() } label: {
                    Image(systemName: satelite ? "map" : "globe.americas.fill")
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.bordered)

                Button { buscarAbierto = true } label: {
                    Image(systemName: "magnifyingglass").frame(width: 34, height: 30)
                }
                .buttonStyle(.bordered)

                if modo == .radio {
                    Button { sorprendeme() } label: {
                        Image(systemName: "shuffle").frame(width: 34, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            HStack(spacing: 6) {
                if modelo.cargando != nil { ProgressView().controlSize(.mini) }
                Text(textoAyuda)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var textoAyuda: String {
        if let c = modelo.cargando { return c }
        if zoomLat > 40 { return "Toca una bandera o acerca el mapa a un país" }
        let que = modo == .radio ? "emisoras" : "canales"
        if modo == .radio && zoomLat < 1.5 { return "Toca un punto verde para escuchar" }
        if modo == .radio && zoomLat < 8 { return "Cada número es una ciudad o zona: tócalo para ver sus emisoras" }
        return "Cada número es una región: tócalo para ver sus \(que)"
    }

    @ViewBuilder
    private var tarjetaInferior: some View {
        if let p = paisEnfocado, zoomLat <= 40 {
            Button {
                hoja = modo == .radio ? .listaPais(.delPais(p)) : .canales(.pais(p))
            } label: {
                Label("Todo \(Pais.bandera(p)) \(Pais.nombre(p))", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, radio.emisora == nil ? 12 : 4)
        }
    }

    private func tocarRegion(_ r: RegionMapa) {
        if modo == .radio {
            if r.emisoras.count == 1, let e = r.emisoras.first { radio.reproducir(e); return }
            hoja = .regionRadio(r)
        } else if let f = r.fuente {
            hoja = .canales(f)
        }
    }

    private func enfocar(_ codigo: String) {
        paisEnfocado = codigo
        volar(a: CentrosPaises.centro(codigo), distancia: 3_500_000)
        let m = modo
        Task { await modelo.cargar(codigo, modo: m) }
    }

    private func volar(a punto: CLLocationCoordinate2D?, distancia: Double) {
        guard let c = punto else { return }
        withAnimation(.easeInOut(duration: 1.5)) {
            posicion = .camera(MapCamera(centerCoordinate: c, distance: distancia))
        }
    }

    private func sorprendeme() {
        guard let p = modelo.paisAlAzar() else { return }
        Task {
            let lista = await modelo.cargarRadio(p)
            guard let e = lista.prefix(80).randomElement() else { enfocar(p); return }
            paisEnfocado = p
            let lugar = e.coordenada
                ?? modelo.regionesRadio[p]?.first(where: { $0.emisoras.contains(e) })?.coord
                ?? CentrosPaises.centro(p)
            volar(a: lugar, distancia: e.coordenada == nil ? 1_500_000 : 300_000)
            radio.reproducir(e)
        }
    }
}

struct BurbujaRegion: View {
    let region: RegionMapa
    let color: Color
    let mostrarNombre: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("\(region.cantidad)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(minWidth: 28, minHeight: 28)
                .padding(.horizontal, region.cantidad > 99 ? 4 : 0)
                .background(region.esNacional ? color.opacity(0.65) : color, in: Capsule())
                .overlay(Capsule().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 3)
            if mostrarNombre {
                Text(region.nombre)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .contentShape(Rectangle())
    }
}

struct PuntoEmisora: View {
    let activa: Bool
    @State private var pulso = false

    var body: some View {
        ZStack {
            if activa {
                Circle()
                    .fill(Color.green.opacity(0.35))
                    .frame(width: 34, height: 34)
                    .scaleEffect(pulso ? 1.3 : 0.8)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulso)
                    .onAppear { pulso = true }
            }
            Circle()
                .fill(activa ? Color.white : Color.green)
                .frame(width: activa ? 16 : 11, height: activa ? 16 : 11)
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                .shadow(color: .green.opacity(0.8), radius: 4)
        }
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
    }
}

/// Lista de emisoras ya cargadas (las de una región del mapa).
struct ListaEmisorasView: View {
    let titulo: String
    let emisoras: [Emisora]
    @State private var texto = ""

    private var filtradas: [Emisora] {
        guard !texto.isEmpty else { return emisoras }
        return emisoras.filter { $0.name.localizedCaseInsensitiveContains(texto) || ($0.tags ?? "").localizedCaseInsensitiveContains(texto) }
    }

    var body: some View {
        List {
            Section {
                ForEach(filtradas) { FilaEmisora(emisora: $0) }
            } header: {
                Text("\(filtradas.count) emisoras")
            }
        }
        .searchable(text: $texto, prompt: "Filtrar")
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Búsqueda global (lugares, radios y canales de todo el mundo)

struct ResultadoLugar: Identifiable {
    let id = UUID()
    let nombre: String
    let detalle: String
    let coord: CLLocationCoordinate2D
    let pais: String?
    let esCiudad: Bool
}

struct BusquedaGlobalView: View {
    /// Se llama al tocar un lugar: (coordenada, país, es ciudad)
    let irA: (CLLocationCoordinate2D, String?, Bool) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var texto = ""
    @State private var lugares: [ResultadoLugar] = []
    @State private var emisoras: [Emisora] = []
    @State private var canales: [Canal] = []
    @State private var buscando = false

    var body: some View {
        NavigationStack {
            List {
                if texto.trimmingCharacters(in: .whitespaces).count < 2 {
                    Section {
                        Text("Escribe una ciudad, un país, una emisora o un canal. Por ejemplo: «Guadalajara», «Japón», «Radio Fórmula», «CNN».")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if buscando && lugares.isEmpty && emisoras.isEmpty && canales.isEmpty {
                        HStack { Spacer(); ProgressView("Buscando en todo el mundo…"); Spacer() }
                    }
                    if !lugares.isEmpty {
                        Section("Lugares en el mapa") {
                            ForEach(lugares) { l in
                                Button { irA(l.coord, l.pais, l.esCiudad) } label: {
                                    Label {
                                        VStack(alignment: .leading) {
                                            Text(l.nombre).foregroundStyle(.primary)
                                            Text(l.detalle).font(.caption).foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: l.esCiudad ? "mappin.circle.fill" : "flag.circle.fill").foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                    if !emisoras.isEmpty {
                        Section("Radios (\(emisoras.count))") {
                            ForEach(emisoras) { FilaEmisora(emisora: $0) }
                        }
                    }
                    if !canales.isEmpty {
                        Section("Canales de TV (\(canales.count))") {
                            ForEach(canales) { FilaCanal(canal: $0) }
                        }
                    }
                    if !buscando && lugares.isEmpty && emisoras.isEmpty && canales.isEmpty {
                        Text("Sin resultados.").foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $texto, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ciudad, país, radio o canal")
            .task(id: texto) { await buscar() }
            .navigationTitle("Buscar en el mundo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } }
            }
        }
    }

    private func buscar() async {
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { lugares = []; emisoras = []; canales = []; return }
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        buscando = true
        defer { buscando = false }

        async let radios = ServicioRadio.shared.emisoras(FiltroRadio(titulo: t, nombre: t), cantidad: 60)
        async let tv = ServicioTV.shared.canales(.todos)

        // Países que coinciden por nombre (en español)
        var l: [ResultadoLugar] = Pais.todos
            .filter { $0.nombre.localizedCaseInsensitiveContains(t) }
            .prefix(5)
            .compactMap { p in
                CentrosPaises.centro(p.codigo).map {
                    ResultadoLugar(nombre: "\(p.bandera) \(p.nombre)", detalle: "País", coord: $0, pais: p.codigo, esCiudad: false)
                }
            }
        // Ciudades y regiones (buscador de Apple Maps)
        let pedido = MKLocalSearch.Request()
        pedido.naturalLanguageQuery = t
        pedido.resultTypes = .address
        if let r = try? await MKLocalSearch(request: pedido).start() {
            for item in r.mapItems.prefix(6) {
                let pm = item.placemark
                let nombre = pm.locality ?? pm.administrativeArea ?? pm.name ?? t
                let detalle = [pm.administrativeArea, pm.country].compactMap { $0 }.filter { $0 != nombre }.joined(separator: ", ")
                l.append(ResultadoLugar(nombre: nombre, detalle: detalle, coord: pm.coordinate,
                                        pais: pm.isoCountryCode, esCiudad: pm.locality != nil))
            }
        }
        guard !Task.isCancelled else { return }
        lugares = l

        emisoras = (try? await radios) ?? []
        guard !Task.isCancelled else { return }
        let todos = (try? await tv) ?? []
        guard !Task.isCancelled else { return }
        canales = Array(todos.filter { $0.nombre.localizedCaseInsensitiveContains(t) }.prefix(80))
    }
}
