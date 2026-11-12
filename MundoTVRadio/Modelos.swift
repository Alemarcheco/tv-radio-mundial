import Foundation

// MARK: - Canal de TV (viene de las listas públicas de iptv-org)

struct Canal: Identifiable, Codable, Hashable {
    var id: String { url }
    let nombre: String
    let url: String
    let logo: String?
    let grupo: String?
    let userAgent: String?
    let referer: String?
}

// MARK: - Emisora de radio (viene de la API pública Radio Browser)

struct Emisora: Identifiable, Codable, Hashable {
    var id: String { stationuuid }
    let stationuuid: String
    let name: String
    let url: String
    let url_resolved: String?
    let favicon: String?
    let tags: String?
    let country: String?
    let countrycode: String?
    let codec: String?
    let bitrate: Int?
    let homepage: String?
    let geo_lat: Double?
    let geo_long: Double?

    var urlReproduccion: String {
        if let r = url_resolved, !r.isEmpty { return r }
        return url
    }

    var nombreLimpio: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Emisora sin nombre" : n
    }

    var detalle: String {
        var partes: [String] = []
        if let c = countrycode, !c.isEmpty { partes.append(Pais.bandera(c) + " " + Pais.nombre(c)) }
        let generos = (tags ?? "").split(separator: ",").prefix(2).map { $0.trimmingCharacters(in: .whitespaces) }
        if !generos.isEmpty { partes.append(generos.joined(separator: ", ")) }
        if let b = bitrate, b > 0 { partes.append("\(b) kbps") }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Países

struct Pais: Identifiable, Hashable {
    let codigo: String
    let nombre: String
    var id: String { codigo }
    var bandera: String { Pais.bandera(codigo) }

    static func bandera(_ codigo: String) -> String {
        let c = codigo.uppercased()
        guard c.count == 2, c.allSatisfy({ $0.isASCII && $0.isLetter }) else { return "🌐" }
        var s = ""
        for u in c.unicodeScalars {
            if let v = UnicodeScalar(127397 + u.value) { s.unicodeScalars.append(v) }
        }
        return s
    }

    static func nombre(_ codigo: String) -> String {
        Locale(identifier: "es").localizedString(forRegionCode: codigo.uppercased()) ?? codigo
    }

    static let todos: [Pais] = Locale.isoRegionCodes
        .filter { $0.count == 2 && $0.allSatisfy { $0.isLetter } }
        .map { Pais(codigo: $0, nombre: nombre($0)) }
        .sorted { $0.nombre.localizedCompare($1.nombre) == .orderedAscending }

    static var actual: String {
        Locale.current.region?.identifier ?? "US"
    }
}

// MARK: - Fuentes de TV

struct FuenteTV: Hashable, Identifiable {
    let titulo: String
    let ruta: String
    var icono: String = "tv"
    var id: String { ruta }

    static func pais(_ codigo: String) -> FuenteTV {
        // iptv-org usa "uk" para Reino Unido
        let c = codigo.uppercased() == "GB" ? "uk" : codigo.lowercased()
        return FuenteTV(titulo: Pais.bandera(codigo) + " " + Pais.nombre(codigo), ruta: "countries/\(c).m3u")
    }

    static let internacional = FuenteTV(titulo: "🌐 Internacionales", ruta: "countries/int.m3u", icono: "globe")
    static let todos = FuenteTV(titulo: "Todos los canales", ruta: "index.m3u", icono: "globe.americas.fill")

    static let categorias: [FuenteTV] = ([
        ("Noticias", "news", "newspaper"),
        ("Deportes", "sports", "sportscourt"),
        ("Películas", "movies", "film"),
        ("Series", "series", "play.rectangle.on.rectangle"),
        ("Infantiles", "kids", "teddybear"),
        ("Animación", "animation", "sparkles.tv"),
        ("Música", "music", "music.note.tv"),
        ("Documentales", "documentary", "binoculars"),
        ("Entretenimiento", "entertainment", "theatermasks"),
        ("Comedia", "comedy", "face.smiling"),
        ("Cocina", "cooking", "fork.knife"),
        ("Cultura", "culture", "building.columns"),
        ("Educación", "education", "graduationcap"),
        ("Ciencia", "science", "atom"),
        ("Viajes", "travel", "airplane"),
        ("Estilo de vida", "lifestyle", "heart"),
        ("Familia", "family", "figure.2.and.child.holdinghands"),
        ("Clásicos", "classic", "clock"),
        ("Clima", "weather", "cloud.sun"),
        ("Autos", "auto", "car"),
        ("Aire libre", "outdoor", "leaf"),
        ("Relax", "relax", "moon.stars"),
        ("Religiosos", "religious", "book"),
        ("Negocios", "business", "chart.line.uptrend.xyaxis"),
        ("Parlamento", "legislative", "person.3"),
        ("Compras", "shop", "cart"),
        ("Generales", "general", "tv"),
    ] as [(String, String, String)]).map { FuenteTV(titulo: $0.0, ruta: "categories/\($0.1).m3u", icono: $0.2) }

    static let idiomas: [FuenteTV] = ([
        ("Español", "spa"), ("Inglés", "eng"), ("Portugués", "por"), ("Francés", "fra"),
        ("Italiano", "ita"), ("Alemán", "deu"), ("Árabe", "ara"), ("Ruso", "rus"),
        ("Chino", "zho"), ("Japonés", "jpn"), ("Coreano", "kor"), ("Hindi", "hin"),
        ("Turco", "tur"), ("Neerlandés", "nld"), ("Polaco", "pol"), ("Griego", "ell"),
    ] as [(String, String)]).map { FuenteTV(titulo: $0.0, ruta: "languages/\($0.1).m3u", icono: "character.bubble") }
}

// MARK: - Filtros de radio

struct FiltroRadio: Hashable, Identifiable {
    let titulo: String
    var id: String { [titulo, pais ?? "", genero ?? "", nombre ?? ""].joined(separator: "|") }
    var pais: String? = nil
    var genero: String? = nil
    var nombre: String? = nil

    static let masEscuchadas = FiltroRadio(titulo: "Más escuchadas del mundo")
    static func delPais(_ codigo: String) -> FiltroRadio {
        FiltroRadio(titulo: Pais.bandera(codigo) + " " + Pais.nombre(codigo), pais: codigo.uppercased())
    }
}
