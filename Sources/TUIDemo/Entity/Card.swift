import Foundation

struct Card {
    let suit: Suit?
    let rank: Rank?
    let isSmallJoker: Bool
    let isBigJoker: Bool
    let rawValue: Int

    init(_ rawValue: Int) {
        self.rawValue = rawValue
        let rawValue = rawValue % 54
        if rawValue == 52 {
            self.suit = nil 
            self.rank = nil
            self.isSmallJoker = true
            self.isBigJoker = false
        } else if rawValue == 53 {
            self.suit = nil
            self.rank = nil
            self.isSmallJoker = false
            self.isBigJoker = true
        } else {
            let suitIndex = rawValue / 13
            let rankIndex = rawValue % 13
            self.suit = Suit.allCases[suitIndex]
            self.rank = Rank(rawValue: rankIndex + 2)
            self.isSmallJoker = false
            self.isBigJoker = false
        }
    }
}

extension Card: CustomStringConvertible {
    var description: String {
        if isSmallJoker {
            return "小王"
        } else if isBigJoker {
            return "大王"
        } else if let suit = suit, let rank = rank {
            return "\(suit.rawValue)\(rank.description)"
        } else {
            return "未知牌"
        }
    }
}

