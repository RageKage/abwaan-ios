import SwiftUI
import FirebaseCore

// ─────────────────────────────────────────────────────────────────────────────
// M0 LIQUID GLASS SPIKE  (throwaway — replaced at M2)
//
// Purpose: prove the iOS 26/27 Liquid Glass + TabView APIs from docs 09/10
// actually exist and behave as designed, BEFORE any feature work. No Firebase
// here on purpose — this must compile and run with zero dependencies.
//
// Each line marked  // ⚠️ VERIFY  is an API I annotated "(verify)" in the docs.
// If the build fails, it will fail on one of these. Send me the exact compiler
// error for the flagged line and I'll correct it — that IS the spike working.
// ─────────────────────────────────────────────────────────────────────────────

@main
struct AbwaanApp: App {
    init() {
        FirebaseApp.configure()
        #if DEBUG
        if ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATOR"] == "1" {
            EmulatorConfig.connect()
        } else {
            let project = FirebaseApp.app()?.options.projectID ?? "?"
            print("⚠️ Firebase pointed at REAL project \(project) — USE_FIREBASE_EMULATOR is not set")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            SpikeRootView()
                #if DEBUG
                .task { await EmulatorConfig.healthCheck() }
                #endif
        }
    }
}

private enum SpikeTab: Hashable {
    case archive, desk, you, search
}

struct SpikeRootView: View {
    @State private var selection: SpikeTab = .archive

    var body: some View {
        TabView(selection: $selection) {
            Tab("Archive", systemImage: "books.vertical", value: SpikeTab.archive) {
                SpikeList(title: "Archive")
            }
            Tab("Desk", systemImage: "tray.full", value: SpikeTab.desk) {
                SpikeList(title: "Desk")
            }
            Tab("You", systemImage: "person.crop.circle", value: SpikeTab.you) {
                SpikeList(title: "You")
            }
            // ⚠️ VERIFY — Tab(role: .search) search-role tab (08 §Search)
            Tab(value: SpikeTab.search, role: .search) {
                SpikeList(title: "Search")
            }
        }
        // ⚠️ VERIFY — tab bar minimizes on scroll down (07 §1.2)
        .tabBarMinimizeBehavior(.onScrollDown)
        // ⚠️ VERIFY — persistent bottom accessory, the ambient-audio slot (07 §1.12)
        .tabViewBottomAccessory {
            SpikeAudioAccessory()
        }
    }
}

/// A scrollable list so the tab bar has something to minimize against,
/// plus a glass toolbar button to test `.buttonStyle(.glass)`.
struct SpikeList: View {
    let title: String

    var body: some View {
        NavigationStack {
            List(0..<40, id: \.self) { i in
                Text("Row \(i)")
                    .font(.system(.title3, design: .serif))  // New York serif (09 §1)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Filter", systemImage: "line.3.horizontal.decrease") {}
                        .buttonStyle(.glass)   // ⚠️ VERIFY — glass button style (09 §6)
                }
            }
            // ⚠️ VERIFY — soft scroll-edge effect so serif dissolves into the bar (07 §1.2)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }
}

/// Two controls inside a GlassEffectContainer to test grouping/morphing.
struct SpikeAudioAccessory: View {
    @Namespace private var glassNS
    @State private var playing = false

    var body: some View {
        // ⚠️ VERIFY — GlassEffectContainer groups sibling glass elements (09 §6)
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: playing ? "speaker.wave.2" : "speaker.slash")
                Text("Ambient")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Button(playing ? "Pause" : "Play") { playing.toggle() }
                    .buttonStyle(.glassProminent)   // ⚠️ VERIFY — prominent glass (09 §6)
                    .glassEffectID("toggle", in: glassNS)  // ⚠️ VERIFY — morph id (09 §6)
            }
            .padding(.horizontal, 12)
        }
    }
}

#Preview {
    SpikeRootView()
}
