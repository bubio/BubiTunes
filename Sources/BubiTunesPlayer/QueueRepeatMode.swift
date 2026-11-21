enum QueueRepeatMode: String, Codable {
  case off, one, all

  var next: Self {
    switch self {
    case .off: .one
    case .one: .all
    case .all: .off
    }
  }

  var label: String {
    switch self {
    case .off: "Repeat off"
    case .one: "Repeat one"
    case .all: "Repeat queue"
    }
  }

  func nextIndex(after index: Int, count: Int, trackFinished: Bool = false) -> Int {
    guard index < count else { return count }
    if trackFinished && self == .one { return index }
    let following = index + 1
    return following == count && self == .all ? 0 : following
  }

  func previousIndex(before index: Int, count: Int) -> Int {
    if index == 0 && self == .all && count > 0 { return count - 1 }
    return max(0, index - 1)
  }
}
