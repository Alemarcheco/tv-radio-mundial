import Foundation

// MARK: - Lector de listas M3U

enum ParserM3U {
    static func parse(_ texto: String) -> [Canal] {
        var canales: [Canal] = []
        var vistos = Set<String>()
        var nombre: String?
        var logo: String?
        var grupo: String?
        var userAgent: String?
        var referer: String?

        for bruta in texto.components(separatedBy: .newlines) {
            let linea = bruta.trimmingCharacters(in: .whitespaces)
            if linea.isEmpty { continue }

            if linea.hasPrefix("#EXTINF") {
                nombre = nombreDe(linea)
                logo = atributo("tvg-logo", en: linea)
                grupo = atributo("group-title", en: linea)
                if let ua = atributo("user-agent", en: linea) { userAgent = ua }
                if let rf = atributo("referrer", en: linea) { referer = rf }
            } else if linea.hasPrefix("#EXTVLCOPT:") {
                let opcion = String(linea.dropFirst("#EXTVLCOPT:".count))
                if opcion.hasPrefix("http-user-agent=") {
                    userAgent = String(opcion.dropFirst("http-user-agent=".count))
                } else if opcion.hasPrefix("http-referrer=") {
                    referer = String(opcion.dropFirst("http-referrer=".count))
                }
            } else if linea.hasPrefix("#") {
                continue
            } else {
                if (linea.hasPrefix("http://") || linea.hasPrefix("https://")) && !vistos.contains(linea) {
                    vistos.insert(linea)
                    canales.append(Canal(
                        nombre: (nombre?.isEmpty == false ? nombre! : "Canal"),
                        url: linea,
                        logo: (logo?.isEmpty == false ? logo : nil),
                        grupo: grupo.map { $0.replacingOccurrences(of: ";", with: ", ") },
                        userAgent: userAgent,
                        referer: referer))
                }
                nombre = nil; logo = nil; grupo = nil; userAgent = nil; referer = nil
            }
        }
        return canales
    }

    private static func atributo(_ clave: String, en linea: String) -> String? {
        guard let r = linea.range(of: clave + "=\"") else { return nil }
        let resto = linea[r.upperBound...]
        guard let fin = resto.firstIndex(of: "\"") else { return nil }
        let valor = String(resto[..<fin])
        return valor.isEmpty ? nil : valor
    }

    private static func nombreDe(_ linea: String) -> String {
        // El nombre va después de la primera coma que sigue a la última comilla de los atributos.
        let desde = linea.lastIndex(of: "\"") ?? linea.startIndex
        guard let coma = linea[desde...].firstIndex(of: ",") else { return "" }
        return String(linea[linea.index(after: coma)...]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - TV (listas públicas de canales gratuitos de iptv-org)

actor ServicioTV {
    static let shared = ServicioTV()
    private var cache: [String: [Canal]] = [:]
    private let base = "https://iptv-org.github.io/iptv/"

    func canales(_ fuente: FuenteTV) async throws -> [Canal] {
        if let c = cache[fuente.ruta] { return c }
        guard let url = URL(string: base + fuente.ruta) else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.cachePolicy = .useProtocolCachePolicy
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse {
            if h.statusCode == 404 { cache[fuente.ruta] = []; return [] }
            if h.statusCode != 200 { throw URLError(.badServerResponse) }
        }
        let lista = ParserM3U.parse(String(decoding: data, as: UTF8.self))
        cache[fuente.ruta] = lista
        return lista
    }
}

// MARK: - Regiones de TV (estados/provincias, listas "subdivisions" de iptv-org)

struct SubdivisionTV: Hashable {
    let codigo: String   // p. ej. "MX-JAL"
    let nombre: String
    let pais: String
}

actor ServicioRegionesTV {
    static let shared = ServicioRegionesTV()
    private var todas: [SubdivisionTV]?

    func subdivisiones(de pais: String) async -> [SubdivisionTV] {
        if todas == nil {
            guard let url = URL(string: "https://iptv-org.github.io/api/subdivisions.json"),
                  let respuesta = try? await URLSession.shared.data(from: url),
                  let lista = (try? JSONSerialization.jsonObject(with: respuesta.0)) as? [[String: Any]] else { return [] }
            todas = lista.compactMap { d in
                guard let c = d["code"] as? String, let n = d["name"] as? String, let p = d["country"] as? String else { return nil }
                return SubdivisionTV(codigo: c, nombre: n, pais: p.uppercased())
            }
        }
        let p = pais.uppercased() == "GB" ? "UK" : pais.uppercased()
        return (todas ?? []).filter { $0.pais == p || $0.pais == pais.uppercased() }
    }
}

// MARK: - Radio (API pública Radio Browser, radio-browser.info)

struct PaisRadio: Decodable, Hashable {
    let name: String
    let iso_3166_1: String
    let stationcount: Int
}

struct GeneroRadio: Decodable, Hashable {
    let name: String
    let stationcount: Int
}

actor ServicioRadio {
    static let shared = ServicioRadio()

    private let servidores = [
        "https://de1.api.radio-browser.info",
        "https://de2.api.radio-browser.info",
        "https://fi1.api.radio-browser.info",
        "https://nl1.api.radio-browser.info",
        "https://at1.api.radio-browser.info",
        "https://all.api.radio-browser.info",
    ]
    private var servidorBueno: String?
    private var cachePaises: [PaisRadio]?
    private var cacheGeneros: [GeneroRadio]?

    private func pedir(_ ruta: String, _ query: [URLQueryItem] = []) async throws -> Data {
        var lista = servidores
        if let b = servidorBueno { lista.removeAll { $0 == b }; lista.insert(b, at: 0) }
        var ultimoError: Error = URLError(.cannotFindHost)
        for s in lista {
            guard var comp = URLComponents(string: s + ruta) else { continue }
            if !query.isEmpty { comp.queryItems = query }
            guard let url = comp.url else { continue }
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue("TVyRadioMundial/1.0", forHTTPHeaderField: "User-Agent")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let h = resp as? HTTPURLResponse, h.statusCode == 200 {
                    servidorBueno = s
                    return data
                }
                ultimoError = URLError(.badServerResponse)
            } catch {
                ultimoError = error
            }
        }
        throw ultimoError
    }

    func emisoras(_ filtro: FiltroRadio, desde: Int = 0, cantidad: Int = 100) async throws -> [Emisora] {
        var q = [
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: String(cantidad)),
            URLQueryItem(name: "offset", value: String(desde)),
        ]
        if let p = filtro.pais { q.append(URLQueryItem(name: "countrycode", value: p)) }
        if let g = filtro.genero {
            q.append(URLQueryItem(name: "tag", value: g))
            q.append(URLQueryItem(name: "tagExact", value: "true"))
        }
        if let n = filtro.nombre { q.append(URLQueryItem(name: "name", value: n)) }
        let data = try await pedir("/json/stations/search", q)
        return try JSONDecoder().decode([Emisora].self, from: data)
    }

    /// Todas las emisoras de un país (hasta 3000, las más escuchadas primero), para el mapa por regiones.
    func emisorasDelPais(_ pais: String) async throws -> [Emisora] {
        let data = try await pedir("/json/stations/search", [
            URLQueryItem(name: "countrycode", value: pais.uppercased()),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: "3000"),
        ])
        return try JSONDecoder().decode([Emisora].self, from: data)
    }

    func paises() async throws -> [PaisRadio] {
        if let c = cachePaises { return c }
        let data = try await pedir("/json/countries")
        let lista = try JSONDecoder().decode([PaisRadio].self, from: data)
            .filter { $0.stationcount > 0 && $0.iso_3166_1.count == 2 }
        cachePaises = lista
        return lista
    }

    func generos() async throws -> [GeneroRadio] {
        if let c = cacheGeneros { return c }
        let data = try await pedir("/json/tags", [
            URLQueryItem(name: "order", value: "stationcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "limit", value: "200"),
        ])
        let lista = try JSONDecoder().decode([GeneroRadio].self, from: data)
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        cacheGeneros = lista
        return lista
    }

    /// Avisa a Radio Browser que se escuchó la emisora (así lo piden en su documentación).
    func registrarEscucha(_ uuid: String) async {
        _ = try? await pedir("/json/url/\(uuid)")
    }
}
