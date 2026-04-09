import TerminalUI


class GameUI {
    let width: Int
    let height: Int
    let canvas: Canvas

    init(width: Int = 160, height: Int = 40) {
        self.width = width
        self.height = height
        self.canvas = Canvas(width: width, height: height)
    }

}