import Foundation
import AVFoundation
import AVKit
import MediaPlayer
import UIKit

enum SesionAudio {
    static func activar() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [])
        try? s.setActive(true)
    }
}

// MARK: - Radio (sigue sonando con la pantalla bloqueada)

/// Lee el título de la canción que mandan muchas emisoras (metadatos ICY).
final class LectorMetadatos: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    var alRecibir: ((String) -> Void)?

    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let items = groups.flatMap { $0.items }
        let titulo = items.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue
            ?? items.first?.stringValue
        guard let t = titulo?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return }
        alRecibir?(t)
    }
}

@MainActor
final class ReproductorRadio: ObservableObject {
    static let shared = ReproductorRadio()

    @Published private(set) var emisora: Emisora?
    @Published private(set) var reproduciendo = false
    @Published private(set) var cargando = false
    @Published private(set) var cancion: String?
    @Published var error: String?

    private let player = AVPlayer()
    private var observadorControl: NSKeyValueObservation?
    private var observadorItem: NSKeyValueObservation?
    private let lector = LectorMetadatos()
    private var portada: MPMediaItemArtwork?

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        lector.alRecibir = { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                self.cancion = t
                self.actualizarPantallaBloqueo()
            }
        }
        observadorControl = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let estado = p.timeControlStatus
            Task { @MainActor in self?.cambioEstado(estado) }
        }
        configurarControlesRemotos()
    }

    func reproducir(_ e: Emisora) {
        guard let url = URL(string: e.urlReproduccion) else {
            error = "La dirección de esta emisora no es válida."
            return
        }
        ReproductorVideo.shared.detener()
        SesionAudio.activar()
        emisora = e
        cancion = nil
        error = nil
        cargando = true
        portada = nil

        let item = AVPlayerItem(url: url)
        let salida = AVPlayerItemMetadataOutput(identifiers: nil)
        salida.setDelegate(lector, queue: .main)
        item.add(salida)

        observadorItem = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let fallo = it.status == .failed
            Task { @MainActor in
                guard let self, fallo else { return }
                self.cargando = false
                self.reproduciendo = false
                self.error = "No se pudo conectar con \(e.nombreLimpio). Puede que esté fuera del aire; prueba otra."
            }
        }

        player.replaceCurrentItem(with: item)
        player.play()
        actualizarPantallaBloqueo()
        cargarPortada(e)
        Task { await ServicioRadio.shared.registrarEscucha(e.stationuuid) }
    }

    func alternar() {
        if reproduciendo || cargando { pausar() } else { reanudar() }
    }

    func pausar() {
        player.pause()
        cargando = false
    }

    func reanudar() {
        guard let e = emisora else { return }
        // En vivo: se vuelve a conectar para no quedar atrasado.
        reproducir(e)
    }

    func detener() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        emisora = nil
        cancion = nil
        reproduciendo = false
        cargando = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func cambioEstado(_ estado: AVPlayer.TimeControlStatus) {
        switch estado {
        case .playing:
            reproduciendo = true
            cargando = false
        case .waitingToPlayAtSpecifiedRate:
            cargando = true
        case .paused:
            reproduciendo = false
        @unknown default:
            break
        }
        actualizarPantallaBloqueo()
    }

    private func actualizarPantallaBloqueo() {
        guard let e = emisora else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: cancion ?? e.nombreLimpio,
            MPMediaItemPropertyArtist: cancion != nil ? e.nombreLimpio : (e.country ?? "Radio"),
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: reproduciendo ? 1.0 : 0.0,
        ]
        if let p = portada { info[MPMediaItemPropertyArtwork] = p }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func cargarPortada(_ e: Emisora) {
        guard let f = e.favicon, let url = URL(string: f), !f.isEmpty else { return }
        Task {
            guard let respuesta = try? await URLSession.shared.data(from: url),
                  let img = UIImage(data: respuesta.0) else { return }
            guard self.emisora?.stationuuid == e.stationuuid else { return }
            self.portada = ReproductorRadio.crearPortada(img)
            self.actualizarPantallaBloqueo()
        }
    }

    nonisolated static func crearPortada(_ img: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: img.size) { _ in img }
    }

    private func configurarControlesRemotos() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.reanudar() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pausar() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.alternar() }
            return .success
        }
        c.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.detener() }
            return .success
        }
    }
}

// MARK: - TV (pantalla completa de Apple, con AirPlay e imagen dentro de imagen)

final class PantallaVideo: AVPlayerViewController {
    var enImagenEnImagen = false

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Si se cerró con "X"/deslizar (y no fue a imagen dentro de imagen), se detiene el video.
        if !enImagenEnImagen && presentingViewController == nil {
            player?.pause()
        }
    }
}

@MainActor
final class ReproductorVideo: NSObject, ObservableObject, AVPlayerViewControllerDelegate {
    static let shared = ReproductorVideo()

    @Published var error: String?
    @Published private(set) var canalActual: Canal?

    private var pantalla: PantallaVideo?
    private var observador: NSKeyValueObservation?
    private var espera: Task<Void, Never>?

    func reproducir(_ c: Canal) {
        guard let url = URL(string: c.url) else {
            error = "La dirección de este canal no es válida."
            return
        }
        ReproductorRadio.shared.pausar()
        detener()
        SesionAudio.activar()

        var cabeceras: [String: String] = [:]
        if let ua = c.userAgent { cabeceras["User-Agent"] = ua }
        if let rf = c.referer { cabeceras["Referer"] = rf }
        let asset = AVURLAsset(url: url, options: cabeceras.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": cabeceras])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        let vc = PantallaVideo()
        vc.player = player
        vc.delegate = self
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.modalPresentationStyle = .fullScreen
        pantalla = vc
        canalActual = c

        observador = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            let estado = it.status
            Task { @MainActor in
                guard let self else { return }
                if estado == .failed { self.fallo("«\(c.nombre)» no está transmitiendo ahora o no está disponible en tu país. Prueba otro canal.") }
                if estado == .readyToPlay { self.espera?.cancel() }
            }
        }
        espera = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if item.status != .readyToPlay {
                self.fallo("«\(c.nombre)» no responde. Puede estar caído por ahora; prueba otro canal.")
            }
        }

        guard let arriba = Self.controladorSuperior() else { return }
        arriba.present(vc, animated: true) { player.play() }
    }

    func detener() {
        espera?.cancel()
        observador = nil
        if let p = pantalla {
            p.player?.pause()
            if p.presentingViewController != nil { p.dismiss(animated: false) }
        }
        pantalla = nil
        canalActual = nil
    }

    private func fallo(_ mensaje: String) {
        guard pantalla != nil else { return }
        espera?.cancel()
        pantalla?.player?.pause()
        let p = pantalla
        pantalla = nil
        observador = nil
        canalActual = nil
        if let p, p.presentingViewController != nil {
            Task { @MainActor in
                // Si todavía se está abriendo, se espera un momento antes de cerrarla.
                if p.isBeingPresented { try? await Task.sleep(nanoseconds: 700_000_000) }
                p.dismiss(animated: true) { [weak self] in self?.error = mensaje }
            }
        } else {
            error = mensaje
        }
    }

    static func controladorSuperior() -> UIViewController? {
        let escenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let ventana = escenas.flatMap { $0.windows }.first { $0.isKeyWindow } ?? escenas.first?.windows.first
        var arriba = ventana?.rootViewController
        while let siguiente = arriba?.presentedViewController { arriba = siguiente }
        return arriba
    }

    // Imagen dentro de imagen
    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        (playerViewController as? PantallaVideo)?.enImagenEnImagen = true
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        (playerViewController as? PantallaVideo)?.enImagenEnImagen = false
        if playerViewController.presentingViewController == nil {
            playerViewController.player?.pause()
        }
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        if playerViewController.presentingViewController == nil, let arriba = Self.controladorSuperior() {
            arriba.present(playerViewController, animated: true) { completionHandler(true) }
        } else {
            completionHandler(true)
        }
    }
}
