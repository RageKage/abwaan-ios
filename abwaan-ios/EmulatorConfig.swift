import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// ─────────────────────────────────────────────────────────────────────────────
// M0 — Firebase emulator wiring + connectivity health check.
//
// ⚠️ THE MOST DANGEROUS FILE IN THE PROJECT (10 §3, R7).
// `connect()` MUST run after FirebaseApp.configure() and BEFORE the first
// Firestore/Auth/Functions use. It is only ever called from a #if DEBUG branch
// gated on the USE_FIREBASE_EMULATOR env var. If a debug build ever skips this,
// it writes to the real project instead of the emulator.
// ─────────────────────────────────────────────────────────────────────────────

enum EmulatorConfig {

    /// Point every Firebase service at the local emulator suite.
    /// Simulator: host stays 127.0.0.1. Physical device: set EMULATOR_HOST to the
    /// Mac's LAN IP in the scheme's env vars (R6).
    static func connect() {
        let host = ProcessInfo.processInfo.environment["EMULATOR_HOST"] ?? "127.0.0.1"

        Auth.auth().useEmulator(withHost: host, port: 9099)
        Functions.functions().useEmulator(withHost: host, port: 5001)

        let db = Firestore.firestore()
        let settings = db.settings
        settings.host = "\(host):8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()   // emulator data is ephemeral
        db.settings = settings

        let project = FirebaseApp.app()?.options.projectID ?? "?"
        print("🧪 EMULATOR: wired at \(host) (firestore 8080 / auth 9099 / functions 5001) — project \(project)")
    }

    /// Write one doc and read it back, to prove the app can actually reach the
    /// emulator. Prints the M0 "done-when" line on success.
    static func healthCheck() async {
        let ref = Firestore.firestore().collection("_healthcheck").document("m0")
        do {
            try await ref.setData([
                "note": "M0 emulator connectivity check",
                "ts": FieldValue.serverTimestamp(),
            ])
            let snap = try await ref.getDocument()
            if snap.exists {
                let project = FirebaseApp.app()?.options.projectID ?? "?"
                print("✅ EMULATOR: connected — write+read round-trip OK against \(project)")
            } else {
                print("⚠️ EMULATOR: wrote but read back empty (check firestore.rules)")
            }
        } catch {
            print("❌ EMULATOR: connection FAILED — \(error.localizedDescription)")
            print("   → is `firebase emulators:start` running, on the same host/ports?")
        }
    }
}
