//
//  MatchHistoryScreen.swift
//  TableTop Hub
//
//  Match History screen (screen 3) + RootView that switches between tabs.
//  Depends on MatchLoggerScreen.swift (models, Theme, AppTabBar, shared repository).
//  If your environment only supports ONE file, paste this file's contents below
//  the contents of MatchLoggerScreen.swift and delete the duplicate `import SwiftUI`.
//
//  ASSUMPTIONS (search for "ASSUMPTION"):
//  - "Me" (needed for the Won / Lost filter) is the first player in the library.
//  - Edit, opening a match (screen 4), Home, Rulebooks and Dice are MOCKED.
//  - Matches live in the shared in-memory repository, seeded with sample data.
//

import SwiftUI
import Combine

// MARK: - Helpers on models

extension LoggedMatch {
    var winners: [Participant] { participants.filter(\.isWinner) }

    var winnerText: String {
        winners.isEmpty ? "No winner" : "Winner: " + winners.map { $0.player.name }.joined(separator: ", ")
    }

    var scoreLine: String {
        participants
            .map { "\($0.player.name) \($0.score.map(String.init) ?? "–")" }
            .joined(separator: " · ")
    }
}

// MARK: - Filtering logic

struct HistoryFilter: Equatable {
    enum Period: String, CaseIterable, Identifiable {
        case all = "Any time", week = "Last 7 days", month = "Last month", year = "Last year"
        var id: String { rawValue }

        var startDate: Date? {
            let cal = Calendar.current
            switch self {
            case .all:   return nil
            case .week:  return cal.date(byAdding: .day, value: -7, to: Date())
            case .month: return cal.date(byAdding: .month, value: -1, to: Date())
            case .year:  return cal.date(byAdding: .year, value: -1, to: Date())
            }
        }
    }

    enum Outcome: String, CaseIterable, Identifiable {
        case all = "Any result", won = "Won", lost = "Lost"
        var id: String { rawValue }
    }

    var query = ""
    var gameID: UUID?
    var playerID: UUID?
    var period: Period = .all
    var outcome: Outcome = .all

    var isActive: Bool { self != HistoryFilter() }

    /// Newest first. `me` is the player used for the Won / Lost filter.
    func apply(to matches: [LoggedMatch], me: UUID?) -> [LoggedMatch] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return matches.filter { m in
            if let gameID, m.game.id != gameID { return false }
            if let playerID, !m.participants.contains(where: { $0.player.id == playerID }) { return false }
            if let start = period.startDate, m.date < start { return false }
            if outcome != .all {
                guard let me, let mine = m.participants.first(where: { $0.player.id == me }) else { return false }
                if (outcome == .won) != mine.isWinner { return false }
            }
            if !q.isEmpty {
                let haystack = ([m.game.name, m.sessionName ?? ""] + m.participants.map { $0.player.name })
                    .joined(separator: " ").lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
        .sorted { $0.date > $1.date }
    }
}

// MARK: - View model

final class MatchHistoryViewModel: ObservableObject {
    @Published var filter = HistoryFilter()
    @Published var matchToDelete: LoggedMatch?

    let repository: InMemoryMatchRepository
    let playerStore: PlayerStore
    let games = GameLibrary.sample
    private var cancellable: AnyCancellable?

    init(repository: InMemoryMatchRepository = .shared, playerStore: PlayerStore = .shared) {
        self.repository = repository
        self.playerStore = playerStore
        // Re-render when the repository changes (a match was logged or deleted).
        cancellable = repository.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// ASSUMPTION / MOCK: "me" is the first player until user accounts exist.
    var currentPlayerID: UUID? { playerStore.players.first?.id }

    var visibleMatches: [LoggedMatch] { filter.apply(to: repository.matches, me: currentPlayerID) }

    func delete(_ match: LoggedMatch) { withAnimation { repository.delete(id: match.id) } }
    func clearFilters() { filter = HistoryFilter() }
}

// MARK: - Screen

struct MatchHistoryScreen: View {
    @Binding var tab: AppTab
    @StateObject private var vm = MatchHistoryViewModel()
    @State private var showDiceAlert = false
    @State private var showEditAlert = false

    init(tab: Binding<AppTab>) { _tab = tab }

    var body: some View {
        let matches = vm.visibleMatches

        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)

            SearchField(text: $vm.filter.query)
            FilterBar(vm: vm)

            Text(matches.count == 1 ? "1 match" : "\(matches.count) matches")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)

            if matches.isEmpty {
                EmptyHistoryView(isFiltered: vm.filter.isActive,
                                 onClear: vm.clearFilters,
                                 onLog: { tab = .log })
            } else {
                List(matches) { match in
                    MatchRow(match: match)
                        .listRowInsets(EdgeInsets(top: 6, leading: 2, bottom: 6, trailing: 2))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { vm.matchToDelete = match } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            // MOCK: editing a logged match is not built yet.
                            Button { showEditAlert = true } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color(hex: 0x2F7468))
                        }
                    // MOCK: tapping a row will open the Match Detail screen (screen 4).
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -2)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(selection: $tab, onDice: { showDiceAlert = true })
        }
        .confirmationDialog("Delete this match?",
                            isPresented: Binding(get: { vm.matchToDelete != nil },
                                                 set: { if !$0 { vm.matchToDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: vm.matchToDelete) { match in
            Button("Delete \(match.game.name) match", role: .destructive) { vm.delete(match) }
        } message: { match in
            Text("\(match.date.formatted(date: .abbreviated, time: .omitted)) · \(match.scoreLine)")
        }
        .alert("Edit match", isPresented: $showEditAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Editing a logged match is not implemented yet.")
        }
        .diceStubAlert($showDiceAlert)
    }
}

// MARK: - Search & filters

private struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Search game, player or session", text: $text)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .modifier(FieldBackground())
    }
}

private struct FilterBar: View {
    @ObservedObject var vm: MatchHistoryViewModel

    private var gameTitle: String { vm.games.first { $0.id == vm.filter.gameID }?.name ?? "Game" }
    private var playerTitle: String { vm.playerStore.players.first { $0.id == vm.filter.playerID }?.name ?? "Player" }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Game", selection: $vm.filter.gameID) {
                        Text("All games").tag(UUID?.none)
                        ForEach(vm.games) { Text($0.name).tag(Optional($0.id)) }
                    }
                } label: { FilterChip(title: gameTitle, isActive: vm.filter.gameID != nil) }

                Menu {
                    Picker("Player", selection: $vm.filter.playerID) {
                        Text("All players").tag(UUID?.none)
                        ForEach(vm.playerStore.players) { Text($0.name).tag(Optional($0.id)) }
                    }
                } label: { FilterChip(title: playerTitle, isActive: vm.filter.playerID != nil) }

                Menu {
                    Picker("Period", selection: $vm.filter.period) {
                        ForEach(HistoryFilter.Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    FilterChip(title: vm.filter.period == .all ? "Date" : vm.filter.period.rawValue,
                               isActive: vm.filter.period != .all)
                }

                Menu {
                    Picker("Result", selection: $vm.filter.outcome) {
                        ForEach(HistoryFilter.Outcome.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    FilterChip(title: vm.filter.outcome == .all ? "Result" : vm.filter.outcome.rawValue,
                               isActive: vm.filter.outcome != .all)
                }

                if vm.filter.isActive {
                    Button("Clear", action: vm.clearFilters)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isActive: Bool
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(isActive ? .white : Theme.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(Capsule().fill(isActive ? Theme.accent : Theme.card))
        .shadow(color: Theme.shadow, radius: 5, y: 2)
    }
}

// MARK: - Row

private struct MatchRow: View {
    let match: LoggedMatch

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(match.game.shortName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(match.game.color))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(match.game.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 4)
                    Text(match.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                }
                if let name = match.sessionName {
                    Text(name).font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Text(match.scoreLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill").font(.system(size: 10))
                        Text(match.winnerText).lineLimit(1)
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color(hex: 0x9E3F28))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: 0xF9E6DF)))

                    if let mins = match.durationMinutes {
                        Text("\(mins) min").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
        .shadow(color: Theme.shadow, radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyHistoryView: View {
    let isFiltered: Bool
    let onClear: () -> Void
    let onLog: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(Theme.muted)
            Text(isFiltered ? "No matches found" : "No matches yet")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(isFiltered ? "Try different filters or a different search."
                            : "Log your first session to see it here.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button(isFiltered ? "Clear filters" : "Log a match", action: isFiltered ? onClear : onLog)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(minHeight: 46)
                .background(Capsule().fill(Theme.accent))
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

// MARK: - Dice stub (shared by screens that don't have a dice screen yet)

extension View {
    /// MOCK: the dice screen is not built yet.
    func diceStubAlert(_ isPresented: Binding<Bool>) -> some View {
        alert("Dice", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The dice screen is not implemented yet.")
        }
    }
}

// MARK: - Placeholder tabs (MOCK)

struct PlaceholderScreen: View {
    let title: String
    @Binding var tab: AppTab
    @State private var showDiceAlert = false

    init(title: String, tab: Binding<AppTab>) {
        self.title = title
        _tab = tab
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)
            Text("This screen is not implemented yet.")
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(selection: $tab, onDice: { showDiceAlert = true })
        }
        .diceStubAlert($showDiceAlert)
    }
}

// MARK: - Root

/// Owns the selected tab and shows the matching screen.
struct RootView: View {
    @State private var tab: AppTab = .history   // ASSUMPTION: start on History for now

    var body: some View {
        switch tab {
        case .log:       MatchLoggerScreen(tab: $tab)
        case .history:   MatchHistoryScreen(tab: $tab)
        case .home:      PlaceholderScreen(title: "Home", tab: $tab)
        case .rulebooks: PlaceholderScreen(title: "Rulebooks", tab: $tab)
        }
    }
}

#Preview {
    RootView()
}
