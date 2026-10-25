import GravadorCore
import SwiftUI

struct MeetingsListView: View {
    @EnvironmentObject private var state: AppState
    @State private var meetings: [SavedMeeting] = []
    @State private var selection: SavedMeeting?
    var selectFirst = false

    var body: some View {
        NavigationSplitView {
            List(meetings, selection: $selection) { meeting in
                Text(meeting.name).tag(meeting)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                Button { reload() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
            }
        } detail: {
            if let selection {
                VStack(spacing: 0) {
                    HStack {
                        Text(selection.name).font(.headline)
                        Spacer()
                        Button("Mostrar no Finder") { state.openInFinder(selection.folder) }
                        Button("Abrir transcrição") { NSWorkspace.shared.open(selection.transcriptURL) }
                    }
                    .padding(12)
                    Divider()
                    TranscriptList(segments: TranscriptWriter.readSegments(in: selection.folder).sorted { $0.start < $1.start })
                }
            } else {
                ContentUnavailableView("Selecione uma reunião", systemImage: "list.bullet.rectangle",
                                       description: Text("Salvas em \(state.outputFolder.displayPath)"))
            }
        }
        .onAppear(perform: reload)
        .onChange(of: state.lastSavedFolder) { reload() }
        .onChange(of: state.lastRefinedFolder) { reload() }
    }

    private func reload() {
        guard let root = state.outputFolder.url else { meetings = []; return }
        meetings = MeetingLibrary.meetings(in: root)
        if selectFirst, selection == nil { selection = meetings.first }
    }
}
