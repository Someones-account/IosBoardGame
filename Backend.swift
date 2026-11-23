//
//  Backend.swift
//  TableTop Hub
//
//  Data layer for the Match Logger and Match History screens:
//    - domain models and their Codable "records"
//    - local JSON persistence (behind the RecordStorage protocol)
//    - stores: GameStore, PlayerStore, MatchStore (ObservableObjects the UI observes)
//    - MatchService: validation and business rules for logging a match
//
//  ASSUMPTIONS (search for "ASSUMPTION"):
//  - Persistence is plain JSON files in Application Support (no SwiftData / network),
//    so it works in any Swift environment. To move to SwiftData or a server later,
//    implement RecordStorage or replace the three stores; the screens only use the
//    stores' public API.
//  - Stable IDs link records: a match stores gameID and playerIDs, not copies.
//  - On the very first launch the app is seeded with demo players and matches
//    (AppEnvironment.useDemoData). Set it to false for a clean start.
//  - Persisting players/games fails silently (printed to the console); persisting
//    matches reports errors to the UI.
//

import Foundation
import SwiftUI

// MARK: - Environment

enum AppEnvironment {
    static let storage: RecordStorage = FileRecordStorage()
    /// ASSUMPTION: seed demo players and matches on first launch only.
    static let useDemoData = true
}

// MARK: - Domain models

struct Game: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var shortName: String       // text inside the circle (max 5 characters)
    var colorHex: UInt32

    var color: Color { Color(hex: colorHex) }
}

struct Player: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var colorIndex: Int

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var color: Color { Theme.avatarPalette[colorIndex % Theme.avatarPalette.count] }
}

/// A player taking part in the match being logged.
struct Participant: Identifiable, Hashable {
    let id = UUID()
    let player: Player
    var score: Int?
    var isWinner = false
}

/// A match with its game and players already resolved (what the UI works with).
struct LoggedMatch: Identifiable {
    var id: UUID = UUID()
    let game: Game
    let sessionName: String?
    let date: Date
    let durationMinutes: Int?
    let participants: [Participant]
}

// MARK: - Persisted records (normalized: only IDs, no copies)

struct ParticipantRecord: Codable {
    var playerID: UUID
    var score: Int?
    var isWinner: Bool
}

struct MatchRecord: Codable, Identifiable {
    var id: UUID
    var gameID: UUID
    var sessionName: String?
    var date: Date
    var durationMinutes: Int?
    var results: [ParticipantRecord]

    init(_ m: LoggedMatch) {
        id = m.id
        gameID = m.game.id
        sessionName = m.sessionName
        date = m.date
        durationMinutes = m.durationMinutes
        results = m.participants.map { ParticipantRecord(playerID: $0.player.id, score: $0.score, isWinner: $0.isWinner) }
    }

    /// nil if the game or all players no longer exist.
    func resolved(games: [UUID: Game], players: [UUID: Player]) -> LoggedMatch? {
        guard let game = games[gameID] else { return nil }
        let participants = results.compactMap { r in
            players[r.playerID].map { Participant(player: $0, score: r.score, isWinner: r.isWinner) }
        }
        guard !participants.isEmpty else { return nil }
        return LoggedMatch(id: id, game: game, sessionName: sessionName, date: date,
                           durationMinutes: durationMinutes, participants: participants)
    }
}

// MARK: - Errors

enum LibraryError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Please enter a name."
        case .duplicateName(let n): return "“\(n)” already exists."
        }
    }
}

enum MatchValidationError: LocalizedError, Equatable {
    case noGame, noPlayers, duplicatePlayer(String), invalidDuration, dateInFuture

    var errorDescription: String? {
        switch self {
        case .noGame: return "Choose a game first."
        case .noPlayers: return "Add at least one player."
        case .duplicatePlayer(let n): return "\(n) is added more than once."
        case .invalidDuration: return "Duration must be between 1 and 1440 minutes."
        case .dateInFuture: return "The date can't be in the future."
        }
    }
}

enum StorageError: LocalizedError {
    case newerSchema(Int)
    var errorDescription: String? { "The saved data was written by a newer version of the app." }
}

// MARK: - Persistence

protocol RecordStorage {
    func load<T: Decodable>(_ type: T.Type, name: String) throws -> T?
    func save<T: Encodable>(_ value: T, name: String) throws
}

enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// One JSON file per collection in Application Support/TableTopHub.
struct FileRecordStorage: RecordStorage {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("TableTopHub", isDirectory: true)
        }
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name + ".json") }

    func load<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        let fileURL = url(name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONCoding.decoder().decode(T.self, from: data)
        } catch {
            // Keep the unreadable file for inspection instead of overwriting it silently.
            let backup = directory.appendingPathComponent("\(name).corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            throw error
        }
    }

    func save<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONCoding.encoder().encode(value).write(to: url(name), options: [.atomic])
    }
}

/// For previews and tests.
final class InMemoryRecordStorage: RecordStorage {
    private var blobs: [String: Data] = [:]

    func load<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        guard let data = blobs[name] else { return nil }
        return try JSONCoding.decoder().decode(T.self, from: data)
    }
    func save<T: Encodable>(_ value: T, name: String) throws {
        blobs[name] = try JSONCoding.encoder().encode(value)
    }
}

private enum Schema { static let version = 1 }

private struct Envelope<Item: Codable>: Codable {
    var version: Int
    var items: [Item]
}

enum LoadResult<Item> {
    case missing            // nothing saved yet (first launch)
    case loaded([Item])
    case failed             // unreadable (a backup of the file was kept)
}

extension RecordStorage {
    func loadItems<Item: Codable>(_ type: Item.Type, name: String) -> LoadResult<Item> {
        do {
            guard let envelope = try load(Envelope<Item>.self, name: name) else { return .missing }
            guard envelope.version <= Schema.version else { throw StorageError.newerSchema(envelope.version) }
            return .loaded(envelope.items)
        } catch {
            print("[Storage] could not read \(name): \(error)")
            return .failed
        }
    }

    func saveItems<Item: Codable>(_ items: [Item], name: String) throws {
        try save(Envelope(version: Schema.version, items: items), name: name)
    }
}

// MARK: - GameStore

final class GameStore: ObservableObject {
    static let shared = GameStore(storage: AppEnvironment.storage)

    static let palette: [UInt32] = [0x4E7A63, 0x5C7FA3, 0xC98B4A, 0xB4647A, 0x8E6BB0, 0x6B8F71]

    /// Fixed IDs so saved matches keep pointing at the same games.
    static let defaults: [Game] = [
        Game(id: UUID(uuidString: "6F1A0001-0000-4000-8000-000000000001")!, name: "Catan", shortName: "Catan", colorHex: 0x4E7A63),
        Game(id: UUID(uuidString: "6F1A0001-0000-4000-8000-000000000002")!, name: "HoMM", shortName: "HoMM", colorHex: 0x5C7FA3),
        Game(id: UUID(uuidString: "6F1A0001-0000-4000-8000-000000000003")!, name: "Munchkin", shortName: "Munch", colorHex: 0xC98B4A)
    ]

    @Published private(set) var games: [Game] = []
    private let storage: RecordStorage

    init(storage: RecordStorage) {
        self.storage = storage
        switch storage.loadItems(Game.self, name: "games") {
        case .loaded(let items) where !items.isEmpty:
            games = items
        default:
            games = Self.defaults
            persist()
        }
    }

    func game(id: UUID) -> Game? { games.first { $0.id == id } }

    @discardableResult
    func addGame(name: String, shortName: String = "", colorHex: UInt32? = nil) throws -> Game {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyName }
        guard !games.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw LibraryError.duplicateName(trimmed)
        }
        var short = shortName.trimmingCharacters(in: .whitespaces)
        if short.isEmpty { short = trimmed }
        short = String(short.filter { !$0.isWhitespace }.prefix(5))

        let game = Game(name: trimmed, shortName: short,
                        colorHex: colorHex ?? Self.palette[games.count % Self.palette.count])
        games.append(game)
        persist()
        return game
    }

    private func persist() {
        do { try storage.saveItems(games, name: "games") }
        catch { print("[GameStore] save failed: \(error)") }
    }
}

// MARK: - PlayerStore

final class PlayerStore: ObservableObject {
    static let shared = PlayerStore(storage: AppEnvironment.storage)

    static let demoPlayers: [Player] = ["Alex", "Nikita", "Maria", "Piotr", "Ola"]
        .enumerated().map { Player(name: $0.element, colorIndex: $0.offset) }

    @Published private(set) var players: [Player] = []
    /// True when this launch created the demo players (used to seed demo matches too).
    private(set) var seededDemoData = false
    private let storage: RecordStorage

    init(storage: RecordStorage) {
        self.storage = storage
        switch storage.loadItems(Player.self, name: "players") {
        case .loaded(let items):
            players = items
        case .missing:
            if AppEnvironment.useDemoData {
                players = Self.demoPlayers
                seededDemoData = true
            }
            persist()
        case .failed:
            players = []
        }
    }

    func player(id: UUID) -> Player? { players.first { $0.id == id } }

    func exists(name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        return players.contains { $0.name.caseInsensitiveCompare(n) == .orderedSame }
    }

    @discardableResult
    func createPlayer(name: String) throws -> Player {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyName }
        guard !exists(name: trimmed) else { throw LibraryError.duplicateName(trimmed) }
        let player = Player(name: trimmed, colorIndex: players.count)   // next palette color
        players.append(player)
        persist()
        return player
    }

    private func persist() {
        do { try storage.saveItems(players, name: "players") }
        catch { print("[PlayerStore] save failed: \(error)") }
    }
}

// MARK: - MatchStore

final class MatchStore: ObservableObject {
    static let shared = MatchStore(storage: AppEnvironment.storage,
                                   gameStore: .shared, playerStore: .shared)

    /// Newest logged first.
    @Published private(set) var matches: [LoggedMatch] = []

    private let storage: RecordStorage
    /// Records whose game/players no longer exist. Kept and written back so no data is lost.
    private var orphans: [MatchRecord] = []

    init(storage: RecordStorage, gameStore: GameStore, playerStore: PlayerStore) {
        self.storage = storage
        switch storage.loadItems(MatchRecord.self, name: "matches") {
        case .loaded(let records):
            let games = Dictionary(uniqueKeysWithValues: gameStore.games.map { ($0.id, $0) })
            let players = Dictionary(uniqueKeysWithValues: playerStore.players.map { ($0.id, $0) })
            for record in records {
                if let match = record.resolved(games: games, players: players) {
                    matches.append(match)
                } else {
                    orphans.append(record)
                }
            }
        case .missing:
            if AppEnvironment.useDemoData && playerStore.seededDemoData {
                matches = Self.demoMatches(games: gameStore.games, players: playerStore.players)
                try? persist()
            }
        case .failed:
            break
        }
    }

    /// Saves a new match. If writing to disk fails, the in-memory list is rolled back and the error is thrown.
    func save(_ match: LoggedMatch) throws {
        let previous = matches
        matches.insert(match, at: 0)
        do { try persist() } catch { matches = previous; throw error }
    }

    func delete(id: UUID) throws {
        let previous = matches
        matches.removeAll { $0.id == id }
        do { try persist() } catch { matches = previous; throw error }
    }

    private func persist() throws {
        try storage.saveItems(matches.map(MatchRecord.init) + orphans, name: "matches")
    }

    private static func demoMatches(games g: [Game], players p: [Player]) -> [LoggedMatch] {
        guard g.count >= 3, p.count >= 5 else { return [] }
        func ago(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date() }
        func match(_ game: Game, _ name: String?, _ days: Int, _ mins: Int,
                   _ results: [(Player, Int, Bool)]) -> LoggedMatch {
            LoggedMatch(game: game, sessionName: name, date: ago(days), durationMinutes: mins,
                        participants: results.map { Participant(player: $0.0, score: $0.1, isWinner: $0.2) })
        }
        return [
            match(g[0], "Friday night", 2, 78, [(p[0], 12, true), (p[1], 8, false), (p[2], 5, false)]),
            match(g[2], nil, 6, 45, [(p[1], 9, true), (p[0], 7, false), (p[3], 4, false)]),
            match(g[1], "Hot seat", 13, 120, [(p[2], 3, true), (p[0], 2, false)]),
            match(g[0], nil, 24, 85, [(p[4], 11, true), (p[0], 10, false), (p[2], 6, false)]),
            match(g[2], "Office lunch", 60, 50, [(p[3], 10, true), (p[4], 8, false), (p[1], 8, false)])
        ]
    }
}

// MARK: - MatchService (business rules)

enum MatchService {
    static let durationRange = 1...1440

    /// ASSUMPTION: if nobody is marked as winner but scores exist, the highest score(s) win.
    static let autoPickWinners = true

    /// Validates the form input and builds the match. Throws a MatchValidationError.
    static func makeMatch(game: Game?,
                          sessionName: String,
                          date: Date?,
                          durationText: String,
                          participants: [Participant],
                          now: Date = Date()) throws -> LoggedMatch {
        guard let game else { throw MatchValidationError.noGame }
        guard !participants.isEmpty else { throw MatchValidationError.noPlayers }

        var seen = Set<UUID>()
        for p in participants where !seen.insert(p.player.id).inserted {
            throw MatchValidationError.duplicatePlayer(p.player.name)
        }

        var minutes: Int?
        let durationInput = durationText.trimmingCharacters(in: .whitespaces)
        if !durationInput.isEmpty {
            guard let value = Int(durationInput), durationRange.contains(value) else {
                throw MatchValidationError.invalidDuration
            }
            minutes = value
        }

        let when = date ?? now
        guard when <= now.addingTimeInterval(300) else { throw MatchValidationError.dateInFuture }   // 5 min clock slack

        var finalParticipants = participants
        if autoPickWinners && !participants.contains(where: \.isWinner) {
            finalParticipants = withHighestScoreAsWinners(participants)
        }

        let name = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return LoggedMatch(game: game,
                           sessionName: name.isEmpty ? nil : name,
                           date: when,
                           durationMinutes: minutes,
                           participants: finalParticipants)
    }

    static func withHighestScoreAsWinners(_ participants: [Participant]) -> [Participant] {
        guard let top = participants.compactMap(\.score).max() else { return participants }
        return participants.map { p in
            var copy = p
            copy.isWinner = (p.score == top)
            return copy
        }
    }
}
