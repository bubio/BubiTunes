import Testing
@testable import BubiTunesPlayer

@Test func queueRepeatModesHandleNaturalEndAndManualNavigation() {
  #expect(QueueRepeatMode.off.next == .one)
  #expect(QueueRepeatMode.one.next == .all)
  #expect(QueueRepeatMode.all.next == .off)
  #expect(QueueRepeatMode.off.nextIndex(after: 1, count: 2, trackFinished: true) == 2)
  #expect(QueueRepeatMode.one.nextIndex(after: 0, count: 2, trackFinished: true) == 0)
  #expect(QueueRepeatMode.one.nextIndex(after: 0, count: 2) == 1)
  #expect(QueueRepeatMode.all.nextIndex(after: 1, count: 2, trackFinished: true) == 0)
  #expect(QueueRepeatMode.all.previousIndex(before: 0, count: 2) == 1)
  #expect(QueueRepeatMode.all.nextIndex(after: 0, count: 0, trackFinished: true) == 0)
  #expect(QueueRepeatMode.one.nextIndex(after: 2, count: 2, trackFinished: true) == 2)
}
