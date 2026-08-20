import SwiftUI
import AVFoundation

/// De koppelflow: één commando op de server, één QR scannen in de app.
struct PairServerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// Gezet wanneer de flow via een koppel-link binnenkomt in plaats van via
    /// de camera; dan slaan we de uitleg over en koppelen we direct.
    var incoming: PairingInfo?

    private enum Step { case instructions, scanning, manual, working, done, failed }
    @State private var step: Step = .instructions
    @State private var errorText = ""
    @State private var newServerName = ""

    // Handmatige invoer
    @State private var host = ""
    @State private var port = "29500"
    @State private var code = ""
    @State private var fingerprint = ""

    private let installCommand = "curl -fsSL https://get.mest.dev/si | sudo bash"

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .instructions: instructions
                case .scanning:     scanner
                case .manual:       manualForm
                case .working:      working
                case .done:         success
                case .failed:       failure
                }
            }
            .screenBackground()
            .task {
                if let incoming, step == .instructions {
                    await enroll(incoming)
                }
            }
            .navigationTitle("Server koppelen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuleren") { dismiss() }
                }
            }
        }
    }

    // MARK: - Stap 1: uitleg

    private var instructions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepRow(1, "Draai dit op je server", "Plak dit commando in een SSH-sessie. Het installeert de agent en opent een koppelvenster van 15 minuten.")

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(installCommand)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.C.text)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = installCommand
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Label("Kopieer commando", systemImage: "doc.on.doc")
                                .font(.footnote)
                        }
                    }
                }

                Text("Al geïnstalleerd? Draai dan alleen:")
                    .font(.footnote)
                    .foregroundStyle(Theme.C.textSecondary)
                Card {
                    Text("sudo serverinfo-agent enroll --new")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.C.text)
                        .textSelection(.enabled)
                }

                stepRow(2, "Scan de QR-code", "Die verschijnt in je terminal. Er gaat geen sleutelmateriaal doorheen — alleen adres, fingerprint en een eenmalige code.")

                VStack(spacing: 10) {
                    Button {
                        step = .scanning
                    } label: {
                        Label("QR scannen", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Handmatig invoeren") { step = .manual }
                        .font(.footnote)
                }
                .padding(.top, 4)
            }
            .padding(Theme.M.screenMargin)
        }
    }

    private func stepRow(_ n: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.footnote.bold())
                .foregroundStyle(Theme.C.base)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.C.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.C.text)
                Text(body).font(.footnote).foregroundStyle(Theme.C.textSecondary)
            }
        }
    }

    // MARK: - Stap 2: scannen

    private var scanner: some View {
        ZStack {
            QRScannerView { value in
                guard let url = URL(string: value), let info = PairingInfo(url: url) else { return }
                Task { await enroll(info) }
            }
            .ignoresSafeArea(edges: .bottom)

            VStack {
                Spacer()
                Text("Richt op de QR-code in je terminal")
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Handmatig

    private var manualForm: some View {
        Form {
            Section("Server") {
                TextField("Host of IP", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Poort", text: $port).keyboardType(.numberPad)
            }
            Section {
                TextField("Koppelcode", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("CA-fingerprint", text: $fingerprint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
            } header: {
                Text("Koppelgegevens")
            } footer: {
                Text("Beide waarden staan in de uitvoer van `serverinfo-agent enroll --new`. De fingerprint is nodig om te controleren dat je met de juiste server praat.")
            }
            Section {
                Button("Koppelen") {
                    let info = PairingInfo(host: host.trimmingCharacters(in: .whitespaces),
                                           port: Int(port) ?? 29500,
                                           caFingerprint: fingerprint.trimmingCharacters(in: .whitespaces),
                                           code: code,
                                           name: host)
                    Task { await enroll(info) }
                }
                .disabled(host.isEmpty || code.count < 8 || fingerprint.count < 32)
            }
        }
        .screenBackground()
    }

    // MARK: - Bezig / resultaat

    private var working: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Koppelen…").foregroundStyle(Theme.C.textSecondary)
            Text("Sleutelpaar aanmaken en certificaat ophalen")
                .font(.caption).foregroundStyle(Theme.C.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var success: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.C.ok)
            Text("\(newServerName) gekoppeld")
                .font(.title3.bold())
                .foregroundStyle(Theme.C.text)
            Text("Dit toestel heeft nu een eigen certificaat voor deze server. Andere apparaten komen er niet in.")
                .font(.footnote)
                .foregroundStyle(Theme.C.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Klaar") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failure: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.C.warn)
            Text("Koppelen mislukt").font(.title3.bold()).foregroundStyle(Theme.C.text)
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(Theme.C.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Opnieuw proberen") { step = .instructions }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Uitvoeren

    private func enroll(_ info: PairingInfo) async {
        step = .working
        let serverID = UUID()
        do {
            let key = try Keychain.createKeyPair(for: serverID)
            let pub = try Keychain.publicKeyData(from: key)
            let client = EnrollmentClient(expectedFingerprint: info.caFingerprint)
            let resp = try await client.enroll(info, publicKey: pub,
                                               deviceName: await UIDevice.current.name)
            try IdentityStore.save(serverID: serverID,
                                   clientCertPEM: resp.clientCertPem,
                                   caCertPEM: resp.caCertPem,
                                   token: resp.apiToken)
            var server = Server(id: serverID,
                                name: resp.displayName.isEmpty ? info.name : resp.displayName,
                                host: info.host, port: info.port)
            server.deviceID = resp.deviceId
            server.certExpiresAt = resp.expiresAt
            server.accentIndex = app.servers.count
            newServerName = server.name
            app.add(server)
            app.restartStream()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            step = .done
        } catch {
            Keychain.deleteKeyPair(for: serverID)
            IdentityStore.remove(serverID: serverID)
            errorText = error.localizedDescription
            step = .failed
        }
    }
}

/// Bewerken van een bestaande server (adres/naam). Koppelgegevens blijven staan.
struct EditServerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var server: Server

    var body: some View {
        NavigationStack {
            Form {
                Section("Naam") {
                    TextField("Naam", text: $server.name)
                }
                Section("Adres") {
                    TextField("Host", text: $server.host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Extern adres (optioneel)",
                              text: Binding(get: { server.remoteHost ?? "" },
                                            set: { server.remoteHost = $0.isEmpty ? nil : $0 }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    LabeledContent("Poort", value: "\(server.port)")
                }
                Section("Koppeling") {
                    LabeledContent("Apparaat-ID", value: server.deviceID)
                    LabeledContent("Certificaat verloopt", value: Fmt.shortDate(server.certExpiresAt))
                }
                Section {
                    Button("Server verwijderen", role: .destructive) {
                        app.remove(server)
                        dismiss()
                    }
                } footer: {
                    Text("Dit verwijdert ook het certificaat en token van dit toestel. Op de server blijft het apparaat in de lijst staan tot je het daar intrekt.")
                }
            }
            .screenBackground()
            .navigationTitle(server.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { app.update(server); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
            }
        }
    }
}

/// Dunne wrapper om AVFoundation voor het scannen van de koppel-QR.
struct QRScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: ScannerController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onFound: (String) -> Void
        private var done = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !done,
                  let obj = objects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue,
                  value.hasPrefix("serverinfo://") else { return }
            done = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onFound(value)
        }
    }

    final class ScannerController: UIViewController {
        weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }
    }
}
