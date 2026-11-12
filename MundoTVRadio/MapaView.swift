import SwiftUI
import MapKit

enum ModoMapa: String, CaseIterable, Identifiable {
    case radio = "Radio"
    case tv = "TV"
    var id: String { rawValue }
}

struct PuntoRadio: Identifiable {
    let emisora: Emisora
    let coord: CLLocationCoordinate2D
    var id: String { emisora.id }
}

struct PinPais: Identifiable {
    let codigo: String
    let coord: CLLocationCoordinate2D
    var id: String { codigo }
}

extension Emisora {
    var coordenada: CLLocationCoordinate2D? {
        guard let la = geo_lat, let lo = geo_long, abs(la) <= 90, abs(lo) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }
}

@MainActor
final class ModeloMapa: ObservableObject {
    @Published private(set) var emisoras: [Emisora] = []
    @Published private(set) var cargandoPais: String?
    @Published private(set) var pinesRadio: [PinPais] = []

    let pinesTV: [PinPais] = CentrosPaises.datos.keys.sorted().compactMap { c in
        CentrosPaises.centro(c).map { PinPais(codigo: c, coord: $0) }
    }

    private var paisesConRadio: [PaisRadio] = []
    private var cargados = Set<String>()
    private var porPais: [String: [Emisora]] = [:]

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

    @discardableResult
    func cargarEmisoras(pais: String) async -> [Emisora] {
        let p = pais.uppercased()
        if let ya = porPais[p] { return ya }
        guard !cargados.contains(p) else { return [] }
        cargados.insert(p)
        cargandoPais = p
        defer { if cargandoPais == p { cargandoPais = nil } }
        do {
            let lista = try await ServicioRadio.shared.emisorasConUbicacion(p)
            porPais[p] = lista
            emisoras = porPais.values.flatMap { $0 }
            return lista
        } catch {
            cargados.remove(p)
            return []
        }
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
    @State private var canalesDe: FuenteTV?
    @State private var listaRadio: FiltroRadio?

    private var zoomLat: Double { region?.span.latitudeDelta ?? 180 }

    private var emisorasVisibles: [PuntoRadio] {
        guard modo == .radio, let r = region, r.span.latitudeDelta < 45 else { return [] }
        let minLat = r.center.latitude - r.span.latitudeDelta / 2
        let maxLat = r.center.latitude + r.span.latitudeDelta / 2
        let minLon = r.center.longitude - r.span.longitudeDelta / 2
        let maxLon = r.center.longitude + r.span.longitudeDelta / 2
        var dentro: [PuntoRadio] = []
        for e in modelo.emisoras {
            guard let c = e.coordenada else { continue }
            if c.latitude >= minLat && c.latitude <= maxLat && c.longitude >= minLon && c.longitude <= maxLon {
                dentro.append(PuntoRadio(emisora: e, coord: c))
                if dentro.count >= 400 { break }
            }
        }
        return dentro
    }

    private var pines: [PinPais] {
        if modo == .tv { return modelo.pinesTV }
        guard zoomLat > 7 else { return [] }
        return modelo.pinesRadio
    }

    var body: some View {
        NavigationStack {
            Map(position: $posicion) {
                ForEach(emisorasVisibles) { punto in
                    Annotation(punto.emisora.nombreLimpio, coordinate: punto.coord, anchor: .center) {
                        PuntoEmisora(activa: radio.emisora?.id == punto.id)
                            .onTapGesture { radio.reproducir(punto.emisora) }
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(pines) { p in
                    Annotation(Pais.nombre(p.codigo), coordinate: p.coord, anchor: .center) {
                        Button { tocarPais(p.codigo) } label: {
                            Text(Pais.bandera(p.codigo))
                                .font(modo == .tv ? .title2 : .title3)
                                .padding(5)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(modo == .tv ? Color.orange : Color.green, lineWidth: 1.5))
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
                guard modo == .radio, ctx.region.span.latitudeDelta < 35,
                      let p = modelo.paisMasCercano(a: ctx.region.center) else { return }
                paisEnfocado = p
                Task { await modelo.cargarEmisoras(pais: p) }
            }
            .safeAreaInset(edge: .top) { barraSuperior }
            .overlay(alignment: .bottom) { tarjetaInferior }
            .task { await modelo.cargarPaises() }
            .onChange(of: modo) { _, _ in paisEnfocado = nil }
            .sheet(item: $canalesDe) { fuente in
                NavigationStack {
                    CanalesView(fuente: fuente)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { canalesDe = nil } }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $listaRadio) { filtro in
                NavigationStack {
                    EmisorasView(filtro: filtro)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { listaRadio = nil } }
                        }
                }
                .presentationDetents([.medium, .large])
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

                if modo == .radio {
                    Button { sorprendeme() } label: {
                        Image(systemName: "shuffle").frame(width: 34, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            Text(textoAyuda)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var textoAyuda: String {
        if modo == .tv { return "Toca una bandera para ver los canales de ese país" }
        if let p = modelo.cargandoPais { return "Buscando emisoras de \(Pais.nombre(p))…" }
        if zoomLat > 35 { return "Toca un país o acerca el mapa para ver las emisoras" }
        return "Toca un punto verde para escuchar • \(emisorasVisibles.count) emisoras aquí"
    }

    @ViewBuilder
    private var tarjetaInferior: some View {
        if modo == .radio, let p = paisEnfocado, zoomLat < 35 {
            Button {
                listaRadio = .delPais(p)
            } label: {
                Label("Lista de emisoras de \(Pais.bandera(p)) \(Pais.nombre(p))", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, radio.emisora == nil ? 12 : 4)
        }
    }

    private func tocarPais(_ codigo: String) {
        if modo == .tv {
            canalesDe = .pais(codigo)
            return
        }
        paisEnfocado = codigo
        volar(a: codigo)
        Task { await modelo.cargarEmisoras(pais: codigo) }
    }

    private func volar(a codigo: String, punto: CLLocationCoordinate2D? = nil) {
        guard let c = punto ?? CentrosPaises.centro(codigo) else { return }
        withAnimation(.easeInOut(duration: 1.5)) {
            posicion = .camera(MapCamera(centerCoordinate: c, distance: punto == nil ? 2_500_000 : 600_000))
        }
    }

    private func sorprendeme() {
        guard let p = modelo.paisAlAzar() else { return }
        Task {
            let lista = await modelo.cargarEmisoras(pais: p)
            if let e = lista.prefix(60).randomElement() {
                paisEnfocado = p
                volar(a: p, punto: e.coordenada)
                radio.reproducir(e)
            } else {
                tocarPais(p)
            }
        }
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
