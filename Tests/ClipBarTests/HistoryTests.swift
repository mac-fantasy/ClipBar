import Foundation
import Testing

@testable import ClipBar

@Test func defaultLimitAndFIFO() {
    var state = HistoryState()
    #expect(state.limit == 20)
    for index in 0..<25 {
        state.record(HistoryEntry(content: .text("记录 \(index)")))
    }
    #expect(state.entries.count == 20)
    #expect(state.entries.first?.content == .text("记录 24"))
    #expect(state.entries.last?.content == .text("记录 5"))
}

@Test func onlyConsecutiveDuplicatesAreSuppressed() {
    var state = HistoryState()
    let firstInserted = state.record(HistoryEntry(content: .text("A")))
    #expect(firstInserted)
    let originalID = state.entries[0].id
    let duplicateInserted = state.record(HistoryEntry(content: .text("A")))
    #expect(!duplicateInserted)
    #expect(state.entries[0].id == originalID)
    state.record(HistoryEntry(content: .text("B")))
    state.record(HistoryEntry(content: .text("A")))
    #expect(state.entries.map(\.content) == [.text("A"), .text("B"), .text("A")])
}

@Test func customCapacityTrimsImmediatelyAndRejectsInvalidValues() throws {
    var state = HistoryState()
    for index in 0..<10 { state.record(HistoryEntry(content: .text("\(index)"))) }
    try state.setLimit(3)
    #expect(state.entries.map(\.content) == [.text("9"), .text("8"), .text("7")])
    #expect(throws: ClipBarError.self) { try state.setLimit(0) }
    #expect(throws: ClipBarError.self) { try state.setLimit(101) }
    #expect(state.limit == 3)
    try state.setLimit(1)
    #expect(state.entries.count == 1)
    try state.setLimit(100)
    for index in 10..<120 { state.record(HistoryEntry(content: .text("\(index)"))) }
    #expect(state.entries.count == 100)
    #expect(state.entries.first?.content == .text("119"))
    #expect(state.entries.last?.content == .text("20"))
}

@Test func clearKeepsConfiguredLimit() throws {
    var state = HistoryState(limit: 37)
    state.record(HistoryEntry(content: .text("待清理")))
    state.clear()
    #expect(state.entries.isEmpty)
    #expect(state.limit == 37)
}
