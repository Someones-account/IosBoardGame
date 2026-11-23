//
//  MatchLoggerScreen.swift
//  TableTop Hub
//

import SwiftUI
import Combine

// MARK: - Theme

enum Theme {
    static let background = Color(hex: 0xFBF8F3)
    static let card       = Color.white
    static let accent     = Color(hex: 0xBF5238)
    static let ink        = Color(hex: 0x2A1B14)
    static let muted      = Color(hex: 0x7A6B62)
    static let field      = Color(hex: 0xF4F1EC)
    static let stroke     = Color(hex: 0xE6DDD2)
    static let tabBar     = Color(hex: 0xFFFDFA)
    static let shadow     = Color(red: 0.31, green: 0.18, blue: 0.10).opacity(0.09)

    static let avatarPalette: [Color] = [
        Color(hex: 0xC8553D), Color(hex: 0x8A9A5B), Color(hex: 0x4F8A9C),
        Color(hex: 0xB4647A), Color(hex: 0xC98B4A), Color(hex: 0x5C7FA3),
        Color(hex: 0x6B8F71), Color(hex: 0x8E6BB0)
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - View model

final class MatchLoggerViewModel: ObservableObject {
    let gameStore: GameStore
    let playerStore: PlayerStore
    let matchStore: MatchStore

    @Published var selectedGameID: UUID?
    @Published var sessionName = ""
    @Published var date: Date?
    @Published var durationText = ""
    @Published var participants: [Participant] = []
    @Published var lastLogged: LoggedMatch?
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    init(gameStore: GameStore = .shared,
         playerStore: PlayerStore = .shared,
         matchStore: MatchStore = .shared,
         prefillDemoData: Bool = true) {
        self.gameStore = gameStore
        self.playerStore = playerStore
        self.matchStore = matchStore

        gameStore.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        playerStore.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        if prefillDemoData {
            selectedGameID = gameStore.games.first?.id
            let known = playerStore.players
            if known.count >= 3 {
                participants = [
                    Participant(player: known[0], score: 12),
                    Participant(player: known[1], score: 8),
                    Participant(player: known[2], score: 5)
                ]
            }
        }
    }

    var games: [Game] { gameStore.games }
    var selectedGame: Game? { games.first { $0.id == selectedGameID } }
    var canLog: Bool { selectedGame != nil && !participants.isEmpty }
    var addedPlayerIDs: Set<UUID> { Set(participants.map { $0.player.id }) }

    func add(_ player: Player) {
        guard !addedPlayerIDs.contains(player.id) else { return }
        withAnimation { participants.append(Participant(player: player)) }
    }

    func remove(_ id: UUID) {
        withAnimation { participants.removeAll { $0.id == id } }
    }

    func log() {
        do {
            let match = try MatchService.makeMatch(
                game: selectedGame,
                sessionName: sessionName,
                date: date,
                durationText: durationText,
                participants: participants
            )
            try matchStore.save(match)
            lastLogged = match
            reset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        selectedGameID = nil
        sessionName = ""
        date = nil
        durationText = ""
        participants = []
    }
}

// MARK: - Screen

struct MatchLoggerScreen: View {
    @StateObject private var vm = MatchLoggerViewModel()
    @State private var showAddPlayer = false
    @State private var showAddGameAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Match logger")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)

                GamePickerCard(games: vm.games,
                               selectedID: $vm.selectedGameID,
                               onAddGame: { showAddGameAlert = true })

                DetailsCard(sessionName: $vm.sessionName,
                            date: $vm.date,
                            duration: $vm.durationText)

                PlayersCard(participants: $vm.participants,
                            onDelete: vm.remove,
                            onAdd: { showAddPlayer = true })

                LogSessionButton(isEnabled: vm.canLog, action: vm.log)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 104)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showAddPlayer) {
            AddPlayerSheet(store: vm.playerStore,
                           alreadyAdded: vm.addedPlayerIDs,
                           onPick: vm.add)
        }
        .alert("Add game", isPresented: $showAddGameAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Adding games to the library is not implemented yet.")
        }
        .alert("Couldn't log session",
               isPresented: Binding(get: { vm.errorMessage != nil },
                                    set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("Session logged",
               isPresented: Binding(get: { vm.lastLogged != nil },
                                    set: { if !$0 { vm.lastLogged = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let m = vm.lastLogged {
                Text("\(m.game.name) with \(m.participants.count) player(s) was saved.")
            }
        }
    }
}

// MARK: - Cards

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
            .shadow(color: Theme.shadow, radius: 14, y: 6)
    }
}

private struct CardCaption: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
    }
}

struct FieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.field))
    }
}

// MARK: Game picker

private struct GamePickerCard: View {
    let games: [Game]
    @Binding var selectedID: UUID?
    let onAddGame: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardCaption(text: "Choose a game")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(games) { game in
                            Button { selectedID = game.id } label: {
                                GameChip(game: game, isSelected: game.id == selectedID)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(game.name)
                            .accessibilityAddTraits(game.id == selectedID ? .isSelected : [])
                        }
                        Button(action: onAddGame) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 52, height: 52)
                                .overlay(Circle().strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                                .frame(minWidth: 52, minHeight: 66, alignment: .top)
                        }
                        .accessibilityLabel("Add game")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct GameChip: View {
    let game: Game
    let isSelected: Bool
    var body: some View {
        VStack(spacing: 6) {
            Text(game.shortName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(width: 52, height: 52)
                .background(Circle().fill(game.color))
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2))
            Text(game.name)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .frame(width: 62)
    }
}

// MARK: Details

private struct DetailsCard: View {
    @Binding var sessionName: String
    @Binding var date: Date?
    @Binding var duration: String
    @State private var showDatePicker = false

    var body: some View {
        Card {
            VStack(spacing: 10) {
                TextField("Session name (optional)", text: $sessionName)
                    .font(.system(size: 17))
                    .modifier(FieldBackground())

                HStack(spacing: 10) {
                    Button { showDatePicker = true } label: {
                        Text(date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Date and time")
                            .font(.system(size: 17))
                            .foregroundStyle(date == nil ? Theme.muted.opacity(0.7) : Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(FieldBackground())
                    }
                    .buttonStyle(.plain)

                    TextField("Duration", text: $duration)
                        .font(.system(size: 17))
                        .keyboardType(.numberPad)
                        .onChange(of: duration) { _, new in
                            let digits = new.filter(\.isNumber)
                            if digits != new { duration = digits }
                        }
                        .modifier(FieldBackground())
                        .frame(width: 112)
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DateTimeSheet(date: $date)
                .presentationDetents([.height(540)])
        }
    }
}

private struct DateTimeSheet: View {
    @Binding var date: Date?
    @State private var draft = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("Date and time", selection: $draft)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .navigationTitle("Date and time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { date = draft; dismiss() }
                    }
                }
            Spacer()
        }
        .onAppear { draft = date ?? Date() }
    }
}

// MARK: Players

private struct PlayersCard: View {
    @Binding var participants: [Participant]
    let onDelete: (UUID) -> Void
    let onAdd: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardCaption(text: "Players")
                ForEach($participants) { $participant in
                    PlayerRow(participant: $participant,
                              onDelete: { onDelete(participant.id) })
                }
                Button(action: onAdd) {
                    Label("Add player", systemImage: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .labelStyle(AccentIconLabelStyle())
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct AccentIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

private struct PlayerRow: View {
    @Binding var participant: Participant
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(player: participant.player, size: 40)
            Text(participant.player.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 4)

            TextField("0", value: $participant.score, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 62, height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.background))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
                .accessibilityLabel("Score for \(participant.player.name)")

            SquareIconButton(systemName: "crown",
                             isOn: participant.isWinner,
                             label: "Mark \(participant.player.name) as winner") {
                participant.isWinner.toggle()
            }
            SquareIconButton(systemName: "trash",
                             isOn: false,
                             label: "Remove \(participant.player.name)",
                             action: onDelete)
        }
    }
}

private struct SquareIconButton: View {
    let systemName: String
    let isOn: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "\(systemName).fill" : systemName)
                .font(.system(size: 18))
                .foregroundStyle(isOn ? .white : Theme.accent)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? Theme.accent : Theme.background))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? .clear : Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct AvatarView: View {
    let player: Player
    let size: CGFloat
    var body: some View {
        Text(player.initial)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(player.color))
            .accessibilityHidden(true)
    }
}

// MARK: Log button

private struct LogSessionButton: View {
    let isEnabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Log Session", systemImage: "person.2")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Capsule().fill(Theme.accent))
                .shadow(color: Theme.accent.opacity(0.3), radius: 10, y: 6)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - Add player sheet

struct AddPlayerSheet: View {
    @ObservedObject var store: PlayerStore
    let alreadyAdded: Set<UUID>
    let onPick: (Player) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var createError: String?

    private var available: [Player] { store.players.filter { !alreadyAdded.contains($0.id) } }
    private var trimmed: String { newName.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool { !trimmed.isEmpty && store.exists(name: trimmed) }
    private var canCreate: Bool { !trimmed.isEmpty && !isDuplicate }

    var body: some View {
        NavigationStack {
            List {
                Section("Existing players") {
                    if available.isEmpty {
                        Text("Everyone you know is already in this session.")
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(available) { player in
                        Button {
                            onPick(player)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(player: player, size: 36)
                                Text(player.name).foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { quickCreateBar }
        }
        .presentationDetents([.medium, .large])
    }

    private var quickCreateBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardCaption(text: "New player")
            HStack(spacing: 10) {
                TextField("Name", text: $newName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(create)
                    .modifier(FieldBackground())
                Button("Create & add", action: create)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(Theme.accent))
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.45)
            }
            if isDuplicate {
                Text("A player with this name already exists. Pick them from the list above.")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            } else if let createError {
                Text(createError)
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .background(.bar)
    }

    private func create() {
        guard canCreate else { return }
        do {
            let created = try store.createPlayer(name: trimmed)
            onPick(created)
            dismiss()
        } catch {
            createError = error.localizedDescription
        }
    }
}

#Preview {
    MatchLoggerScreen()
}
