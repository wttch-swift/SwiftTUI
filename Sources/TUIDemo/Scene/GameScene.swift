import TerminalUI


class GameScene: BaseScene {
    private enum Phase {
        case kouDi
        case redistribute
        case takeBottom
        case discardBottom
        case trickPlay
    }

    private struct KouDiEntry {
        let player: Int
        let cards: [Card]
        let suit: Suit
        let pairRank: Rank
    }

    private var hands: [[Card]] = Array(repeating: [], count: 4)
    private var bottomCards: [Card] = []
    private var trick: [(player: Int, card: Card)] = []
    private var scores: [Int] = [0, 0, 0, 0]

    private var phase: Phase = .kouDi
    private var currentPlayer: Int = 0
    private var message: String = "输入 q 返回主菜单"
    private var gameFinished: Bool = false

    private var kouDiEntries: [KouDiEntry] = []
    private var trumpSuit: Suit? = nil
    private var absorberPlayer: Int? = nil
    private var stakeCountByPlayer: [Int: Int] = [:]

    private var redistributeTargets: [Int] = []
    private var redistributeCursor: Int = 0

    required init(canvas: Canvas) {
        super.init(canvas: canvas)
        startGame()
    }

    private func startGame() {
        let deck = Deck(2)
        deck.shuffle()

        let dealt = deck.deal(4, bottomCount: 8)
        hands = dealt.0
        bottomCards = dealt.1
        sortAllHands()

        phase = .kouDi
        trick.removeAll()
        scores = [0, 0, 0, 0]
        currentPlayer = 0
        gameFinished = false
        kouDiEntries.removeAll()
        trumpSuit = nil
        absorberPlayer = nil
        stakeCountByPlayer.removeAll()
        redistributeTargets.removeAll()
        redistributeCursor = 0
        message = "扣底阶段: P1 输入 k 序号 序号 序号 扣底，或输入 p 跳过"
    }

    override func render() {
        canvas.clean()

        canvas.drawText(x: 3, y: 2, text: "升级牌 - 扣底规则原型", foreground: .green)
        canvas.drawText(x: 3, y: 4, text: "底牌数量: \(bottomCards.count)", foreground: .green)

        if let trumpSuit = trumpSuit {
            canvas.drawText(x: 3, y: 5, text: "主花色: \(trumpSuit.rawValue)", foreground: .green)
        }

        let scoreText = "比分(墩数) P1:\(scores[0]) P2:\(scores[1]) P3:\(scores[2]) P4:\(scores[3])"
        canvas.drawText(x: 3, y: 7, text: scoreText, foreground: .green)

        let trickText: String
        if trick.isEmpty {
            trickText = "本墩尚未出牌"
        } else {
            trickText = trick.map { "P\($0.player + 1):\($0.card)" }.joined(separator: "  ")
        }
        canvas.drawText(x: 3, y: 9, text: "本墩: \(trickText)", foreground: .green)

        canvas.drawText(x: 3, y: 11, text: "阶段: \(phaseTitle())", foreground: .green)
        canvas.drawText(x: 3, y: 12, text: message, foreground: .green)

        canvas.drawText(x: 3, y: 14, text: "当前行动玩家: P\(currentPlayer + 1)", foreground: .green)

        let hand = hands[currentPlayer]
        let handTitle = "P\(currentPlayer + 1) 手牌(输入序号):"
        canvas.drawText(x: 3, y: 16, text: handTitle, foreground: .green)

        if hand.isEmpty {
            canvas.drawText(x: 3, y: 18, text: "(无可出手牌)", foreground: .green)
        } else {
            drawHandLine(hand, atY: 18)
        }

        canvas.render()
    }

    override func handleInput(_ input: String) -> SceneTransition? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized == "q" {
            return .mainMenu
        }

        switch phase {
        case .kouDi:
            handleKouDiInput(normalized)
        case .redistribute:
            handleRedistributeInput(normalized)
        case .takeBottom:
            handleTakeBottomInput(normalized)
        case .discardBottom:
            handleDiscardBottomInput(normalized)
        case .trickPlay:
            handleTrickPlayInput(normalized)
        }

        return nil
    }

    private func handleKouDiInput(_ input: String) {
        let parts = input.split(separator: " ").map(String.init)

        if parts.count == 1, parts[0] == "p" {
            moveToNextKouDiPlayer(passed: true)
            return
        }

        guard parts.count == 4, parts[0] == "k" else {
            message = "格式错误。示例: k 1 2 3 或 p"
            return
        }

        let indexTexts = Array(parts.dropFirst())
        let indices = indexTexts.compactMap { Int($0) }
        guard indices.count == 3 else {
            message = "扣底必须提供 3 个有效序号"
            return
        }

        if Set(indices).count != indices.count {
            message = "扣底序号不能重复"
            return
        }

        let hand = hands[currentPlayer]
        guard indices.allSatisfy({ $0 >= 1 && $0 <= hand.count }) else {
            message = "扣底序号超出范围"
            return
        }

        let selected = indices.map { hand[$0 - 1] }

        guard let suit = selected.first?.suit, selected.allSatisfy({ $0.suit == suit }) else {
            message = "扣底必须同花色，且不能包含大小王"
            return
        }

        let ranks = selected.compactMap { $0.rank }
        guard ranks.count == selected.count else {
            message = "扣底必须是常规花色牌"
            return
        }

        let hasKing = ranks.contains(.king)
        guard hasKing else {
            message = "扣底必须包含同花色 K"
            return
        }

        let grouped = Dictionary(grouping: ranks, by: { $0 })
        let pairCandidates = grouped.filter { $0.value.count >= 2 }.map { $0.key }
        guard let pairRank = pairCandidates.max(by: { $0.rawValue < $1.rawValue }) else {
            message = "扣底必须包含同花色对子"
            return
        }

        let sortedIndices = indices.sorted(by: >)
        for idx in sortedIndices {
            hands[currentPlayer].remove(at: idx - 1)
        }

        kouDiEntries.append(
            KouDiEntry(player: currentPlayer, cards: selected, suit: suit, pairRank: pairRank)
        )

        moveToNextKouDiPlayer(passed: false)
    }

    private func moveToNextKouDiPlayer(passed: Bool) {
        let oldPlayer = currentPlayer
        if oldPlayer == 3 {
            resolveKouDiResult()
            return
        }
        currentPlayer += 1
        if passed {
            message = "P\(oldPlayer + 1) 跳过扣底。现在轮到 P\(currentPlayer + 1)"
        } else {
            message = "P\(oldPlayer + 1) 扣底完成。现在轮到 P\(currentPlayer + 1)"
        }
    }

    private func resolveKouDiResult() {
        guard !kouDiEntries.isEmpty else {
            message = "无人扣底，重新发牌"
            startGame()
            return
        }

        let winnerEntry = kouDiEntries.max {
            kouDiValue($0) < kouDiValue($1)
        }!

        trumpSuit = winnerEntry.suit
        absorberPlayer = winnerEntry.player
        currentPlayer = winnerEntry.player

        stakeCountByPlayer.removeAll()
        var allStaked: [Card] = []
        for entry in kouDiEntries {
            stakeCountByPlayer[entry.player] = entry.cards.count
            allStaked.append(contentsOf: entry.cards)
        }
        hands[winnerEntry.player].append(contentsOf: allStaked)
        sortHand(player: winnerEntry.player)

        redistributeTargets = kouDiEntries.map { $0.player }.filter { $0 != winnerEntry.player }
        redistributeCursor = 0

        if redistributeTargets.isEmpty {
            phase = .takeBottom
            message = "P\(winnerEntry.player + 1) 扣底最大，主花色 \(winnerEntry.suit.rawValue)。输入 t 拿底牌 8 张"
        } else {
            phase = .redistribute
            let target = redistributeTargets[redistributeCursor]
            let count = stakeCountByPlayer[target] ?? 0
            message = "P\(winnerEntry.player + 1) 扣底最大，主花色 \(winnerEntry.suit.rawValue)。输入 r \(target + 1) ... 回给 P\(target + 1) 共 \(count) 张且同花色"
        }
    }

    private func handleRedistributeInput(_ input: String) {
        guard let absorber = absorberPlayer else {
            message = "状态异常，无法回牌"
            return
        }
        guard redistributeCursor < redistributeTargets.count else {
            phase = .takeBottom
            message = "回牌已完成，输入 t 拿底牌 8 张"
            return
        }

        let target = redistributeTargets[redistributeCursor]
        let required = stakeCountByPlayer[target] ?? 0
        let parts = input.split(separator: " ").map(String.init)

        guard parts.count == required + 2, parts[0] == "r" else {
            message = "格式错误。示例: r \(target + 1) 序号... (共 \(required) 张)"
            return
        }

        guard let targetInput = Int(parts[1]), targetInput == target + 1 else {
            message = "本轮只能给 P\(target + 1) 回牌"
            return
        }

        let indices = parts.dropFirst(2).compactMap(Int.init)
        guard indices.count == required else {
            message = "回牌数量不对，需要 \(required) 张"
            return
        }
        if Set(indices).count != indices.count {
            message = "回牌序号不能重复"
            return
        }

        let hand = hands[absorber]
        guard indices.allSatisfy({ $0 >= 1 && $0 <= hand.count }) else {
            message = "回牌序号超出范围"
            return
        }

        let selected = indices.map { hand[$0 - 1] }
        guard let suit = selected.first?.suit, selected.allSatisfy({ $0.suit == suit }) else {
            message = "回牌必须全部同花色，且不能包含大小王"
            return
        }

        for idx in indices.sorted(by: >) {
            hands[absorber].remove(at: idx - 1)
        }
        hands[target].append(contentsOf: selected)
        sortHand(player: target)

        redistributeCursor += 1
        if redistributeCursor >= redistributeTargets.count {
            phase = .takeBottom
            message = "回牌完成。输入 t 拿底牌 8 张"
            return
        }

        let nextTarget = redistributeTargets[redistributeCursor]
        let nextCount = stakeCountByPlayer[nextTarget] ?? 0
        message = "已回给 P\(target + 1)。继续输入 r \(nextTarget + 1) ... 回给 P\(nextTarget + 1) 共 \(nextCount) 张且同花色"
    }

    private func handleTakeBottomInput(_ input: String) {
        guard let absorber = absorberPlayer else {
            message = "状态异常，无法拿底牌"
            return
        }
        guard input == "t" else {
            message = "输入 t 才能拿底牌 8 张"
            return
        }

        hands[absorber].append(contentsOf: bottomCards)
        bottomCards.removeAll()
        sortHand(player: absorber)

        phase = .discardBottom
        currentPlayer = absorber
        message = "P\(absorber + 1) 已拿底牌。输入 d 序号x8 扣下新的 8 张底牌"
    }

    private func handleDiscardBottomInput(_ input: String) {
        guard let absorber = absorberPlayer else {
            message = "状态异常，无法扣新底牌"
            return
        }

        let parts = input.split(separator: " ").map(String.init)
        guard parts.count == 9, parts[0] == "d" else {
            message = "格式错误。示例: d 1 2 3 4 5 6 7 8"
            return
        }

        let indices = parts.dropFirst().compactMap(Int.init)
        guard indices.count == 8 else {
            message = "需要精确输入 8 张牌的序号"
            return
        }
        if Set(indices).count != indices.count {
            message = "扣底序号不能重复"
            return
        }

        let hand = hands[absorber]
        guard indices.allSatisfy({ $0 >= 1 && $0 <= hand.count }) else {
            message = "扣底序号超出范围"
            return
        }

        let selected = indices.map { hand[$0 - 1] }
        for idx in indices.sorted(by: >) {
            hands[absorber].remove(at: idx - 1)
        }
        bottomCards = selected

        phase = .trickPlay
        currentPlayer = absorber
        message = "新底牌已扣下，进入出牌阶段。输入手牌序号出牌"
    }

    private func handleTrickPlayInput(_ input: String) {
        if gameFinished {
            message = "本局已结束，输入 q 返回主菜单"
            return
        }

        guard let index = Int(input) else {
            message = "输入无效，请输入手牌序号或 q"
            return
        }

        let hand = hands[currentPlayer]
        guard index >= 1, index <= hand.count else {
            message = "序号超出范围，请重新输入"
            return
        }

        let played = hands[currentPlayer].remove(at: index - 1)
        trick.append((player: currentPlayer, card: played))

        if trick.count == 4 {
            let winner = decideTrickWinner(from: trick)
            scores[winner] += 1

            trick.removeAll()
            currentPlayer = winner

            if hands[0].isEmpty && hands[1].isEmpty && hands[2].isEmpty && hands[3].isEmpty {
                gameFinished = true
                message = "P\(winner + 1) 赢下最后一墩"
            } else {
                message = "P\(winner + 1) 赢下此墩，并获得下一墩先手"
            }
        } else {
            currentPlayer = (currentPlayer + 1) % 4
            message = "已出牌，轮到 P\(currentPlayer + 1)"
        }

    }

    private func phaseTitle() -> String {
        switch phase {
        case .kouDi:
            return "扣底"
        case .redistribute:
            return "回牌"
        case .takeBottom:
            return "拿底牌"
        case .discardBottom:
            return "重扣底牌"
        case .trickPlay:
            return "出牌"
        }
    }

    private func kouDiValue(_ entry: KouDiEntry) -> Int {
        return entry.pairRank.rawValue * 10 + suitPriority(entry.suit)
    }

    private func suitPriority(_ suit: Suit) -> Int {
        switch suit {
        case .spades:
            return 4
        case .hearts:
            return 3
        case .clubs:
            return 2
        case .diamonds:
            return 1
        }
    }

    private func drawHandLine(_ hand: [Card], atY y: Int) {
        var currentX = 3
        let gap = "  "

        for (index, card) in hand.enumerated() {
            let indexText = "\(index + 1)."
            canvas.drawText(x: currentX, y: y, text: indexText, foreground: .white)
            currentX += displayWidth(of: indexText)

            let cardText = card.description
            canvas.drawText(x: currentX, y: y, text: cardText, foreground: displayColor(for: card))
            currentX += displayWidth(of: cardText)

            canvas.drawText(x: currentX, y: y, text: gap, foreground: .green)
            currentX += displayWidth(of: gap)

            if currentX >= canvas.width - 3 {
                break
            }
        }
    }

    private func displayColor(for card: Card) -> Color {
        if card.isBigJoker {
            return .yellow
        }
        if card.isSmallJoker {
            return .magenta
        }
        if let suit = card.suit {
            if suit == .hearts || suit == .diamonds {
                return .red
            }
            return .blue
        }
        return .white
    }

    private func displayWidth(of text: String) -> Int {
        return text.reduce(0) { $0 + $1.displayWidth }
    }

    private func sortAllHands() {
        for i in 0..<hands.count {
            sortHand(player: i)
        }
    }

    private func sortHand(player: Int) {
        hands[player].sort { lhs, rhs in
            cardSortKey(lhs) < cardSortKey(rhs)
        }
    }

    private func cardSortKey(_ card: Card) -> (Int, Int, Int) {
        if card.isBigJoker {
            return (3, 0, 0)
        }
        if card.isSmallJoker {
            return (2, 0, 0)
        }

        guard let suit = card.suit, let rank = card.rank else {
            return (4, 0, 0)
        }

        // 黑牌在前(黑桃、梅花)，红牌在后(红桃、方块)，同组内按花色和点数升序。
        return (0, colorGroup(of: suit), suitOrder(of: suit) * 100 + rank.rawValue)
    }

    private func colorGroup(of suit: Suit) -> Int {
        switch suit {
        case .spades, .clubs:
            return 0
        case .hearts, .diamonds:
            return 1
        }
    }

    private func suitOrder(of suit: Suit) -> Int {
        switch suit {
        case .spades:
            return 0
        case .clubs:
            return 1
        case .hearts:
            return 2
        case .diamonds:
            return 3
        }
    }

    private func decideTrickWinner(from cards: [(player: Int, card: Card)]) -> Int {
        var bestPlayer = cards[0].player
        var bestValue = cardValue(cards[0].card)

        for entry in cards.dropFirst() {
            let value = cardValue(entry.card)
            if value > bestValue {
                bestValue = value
                bestPlayer = entry.player
            }
        }

        return bestPlayer
    }

    private func cardValue(_ card: Card) -> Int {
        if card.isBigJoker {
            return 200
        }
        if card.isSmallJoker {
            return 190
        }
        return card.rank?.rawValue ?? 0
    }
}
