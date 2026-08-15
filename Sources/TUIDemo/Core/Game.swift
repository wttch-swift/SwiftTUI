
import TerminalUI



enum GameState {
    case menu // 菜单页面
}

class Game {
    private var state: GameState = .menu
    
    private var canvas: Canvas = Canvas(width: 200, height: 40)
    private var currentScene: Scene


    init( ) {
        currentScene = MenuScene(canvas: canvas)
    }

    func loop() {
        while true {
            // 游戏主循环
            // 清屏
            print("\u{001B}[2J\u{001B}[H", terminator: "")
            canvas.clean()
            currentScene.render()
            let input = readLine() ?? ""
            if let transition = currentScene.handleInput(input) {
                // 处理场景切换
                switch transition {
                    case .mainMenu:
                        currentScene = MenuScene(canvas: canvas)
                    case .settings:
                        currentScene = SettingScene(canvas: canvas)
                    case .game:
                        currentScene = GameScene(canvas: canvas)
                    default:
                        break
                }
            }
        }
    }
}
