
class Deck {
    var cards: [Card] = []
    
    init(_ deckCount: Int) {
        for i in 0..<deckCount * 54 {
            cards.append(Card(i))
        }
    }

    func shuffle() {
        cards.shuffle()
    }

    func deal(_ playerCount: Int, bottomCount: Int) -> ([[Card]], [Card]) {
        var hands: [[Card]] = Array(repeating: [], count: playerCount)
        for i in 0..<(cards.count - bottomCount) {
            hands[i % playerCount].append(cards[i])
        }
        let bottomCards = Array(cards.dropFirst(cards.count - bottomCount))
        return (hands, bottomCards)
    }
}