//
//  ContentView.swift
//  Copypastik
//
//  Created by Andrii Ivanchenko on 27.04.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ClipboardStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clearingItems = Set<ClipboardHistoryItem>()
    @State private var isClearingHistory = false
    @State private var copiedItem: ClipboardHistoryItem?
    @State private var copiedFeedbackGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.55)

            if store.items.isEmpty {
                ClipboardEmptyState(
                    symbolName: "doc.on.clipboard",
                    title: "Nothing copied yet",
                    subtitle: "Copy text or images anywhere. Copypastik will keep them handy.",
                    reduceMotion: reduceMotion
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(store.items.enumerated()), id: \.element) { index, item in
                            ClipboardItemRow(
                                item: item,
                                isSelected: false,
                                isPressed: false,
                                isNewest: index == 0,
                                isDeleteRevealed: false,
                                isDeleting: false,
                                showsReturnGlyph: false,
                                showsCardFill: true,
                                selectionNamespace: nil,
                                revealDelay: 0,
                                isClearing: clearingItems.contains(item),
                                clearDelay: clearDelay(for: index),
                                showsCopiedConfirmation: copiedItem == item,
                                reduceMotion: reduceMotion,
                                onRevealDelete: {},
                                onBeginDelete: {},
                                onConfirmDelete: {}
                            ) {
                                store.copyItem(item)
                                showCopiedFeedback(for: item)
                            }
                            .id(item.id)
                        }
                    }
                    .padding(10)
                    .animation(listAnimation, value: store.items)
                }
                .scrollIndicators(.never)
            }

            Divider()
                .opacity(0.55)

            footer
        }
        .frame(width: 320, height: 420)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            Text("Copypastik")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Text("\(store.items.count) \(store.items.count == 1 ? "item" : "items")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var footer: some View {
        HStack {
            Button {
                beginClearHistory()
            } label: {
                Label("Clear History", systemImage: "trash")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.items.isEmpty || isClearingHistory ? Color.secondary.opacity(0.45) : Color.secondary)
            .disabled(store.items.isEmpty || isClearingHistory)

            Spacer()

            Text("Text and images")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var listAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.24, dampingFraction: 0.86)
    }

    private func beginClearHistory() {
        guard !store.items.isEmpty, !isClearingHistory else { return }

        let itemsToClear = store.items
        HistoryClearAnimation.run(
            items: itemsToClear,
            reduceMotion: reduceMotion,
            onStart: { items in
                isClearingHistory = true
                clearingItems = items
                copiedItem = nil
            },
            onFinish: {
                store.clearHistory()
                clearingItems.removeAll()
                isClearingHistory = false
            }
        )
    }

    private func clearDelay(for index: Int) -> Double {
        HistoryClearAnimation.clearDelay(for: index, reduceMotion: reduceMotion)
    }

    private func showCopiedFeedback(for item: ClipboardHistoryItem) {
        copiedFeedbackGeneration += 1
        let generation = copiedFeedbackGeneration

        withAnimation(copiedFeedbackAnimation) {
            copiedItem = item
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard copiedFeedbackGeneration == generation, copiedItem == item else { return }
            withAnimation(copiedFeedbackAnimation) {
                copiedItem = nil
            }
        }
    }

    private var copiedFeedbackAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.16)
    }
}

#Preview {
    ContentView()
        .environmentObject(ClipboardStore())
}
