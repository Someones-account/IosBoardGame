//
//  AppShell.swift
//  TableTop Hub
//

import SwiftUI
import Combine

// MARK: - Routes

enum AppTab: String, CaseIterable {
    case home = "Home", history = "History", log = "Log", rulebooks = "Rulebooks", dice = "Dice"

    var icon: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .log: "doc.text"
        case .rulebooks: "book"
        case .dice: "die.face.5"
        }
    }
}

final class AppRouter: ObservableObject {
    @Published var selected: AppTab = .home
    func go(_ tab: AppTab) { selected = tab }
}

// MARK: - Root

struct RootView: View {
    @StateObject private var router = AppRouter()

    var body: some View {
        ZStack {
            page(.home) { HomeScreen() }
            page(.history) { MatchHistoryScreen() }
            page(.log) { MatchLoggerScreen() }
            page(.rulebooks) { ComingSoonScreen(title: "Rulebooks") }
            page(.dice) { ComingSoonScreen(title: "Dice") }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(selection: $router.selected)
        }
        .environmentObject(router)
    }

    private func page<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let isSelected = router.selected == tab
        return content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

// MARK: - Screens

struct HomeScreen: View {
    var body: some View {
        Theme.background
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Home")
    }
}

struct ComingSoonScreen: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            Text("This screen is not implemented yet.")
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
    }
}

// MARK: - Tab bar

struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            item(.home)
            item(.history)
            Color.clear.frame(width: 76, height: 1)
            item(.log)
            item(.rulebooks)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(Theme.tabBar)
                .shadow(color: Theme.shadow, radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Button { selection = .dice } label: {
                Image(systemName: AppTab.dice.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(selection == .dice ? Color(hex: 0xA3442D) : Theme.accent))
                    .overlay(Circle().strokeBorder(Theme.background, lineWidth: 4))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 6)
            }
            .offset(y: -28)
            .accessibilityLabel("Dice")
            .accessibilityAddTraits(selection == .dice ? .isSelected : [])
        }
    }

    private func item(_ tab: AppTab) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon).font(.system(size: 20))
                Text(tab.rawValue).font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(selection == tab ? Theme.accent : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

#Preview {
    RootView()
}
