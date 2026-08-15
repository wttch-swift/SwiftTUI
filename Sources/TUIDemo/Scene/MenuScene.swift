
import Foundation
import TerminalUI

class MenuScene: BaseScene {
    override func render() {

        let row = VStack {
            GroupBox("拖拉机", style: .rounded) {
                VStack(alignment: .center) {
                    Text("欢迎来到打升级")
                        .foregroundColor(.yellow)
                        .padding(horizontal: 2)
                        .bordered(.magenta, style: .double)

                    Text("")

                    GroupBox("主菜单") {
                        VStack {
                            Text("1 开始游戏").foregroundColor(.green)
                            Text("")
                            Text("2 设置").foregroundColor(.cyan)
                            Text("")
                            Text("3 退出").foregroundColor(.red)
                        }
                        .padding(horizontal: 2, vertical: 1)
                    }
                    .foregroundColor(.blue)

                    Text("")
                    ProgressBar(value: 0.35, width: 28)
                        .tint(.green)
                        .trackColor(.black)
                }
                .padding(horizontal: 2, vertical: 1)
            }
            .foregroundColor(.cyan)
        }

        canvas.draw(row, in: Rect(x: 0, y: 0, w: canvas.width, h: canvas.height))

        canvas.render()
    }

    override func handleInput(_ input: String) -> SceneTransition? {
        if input == "1" {
            return .game
        }
        if input == "2" {
            return .settings
        }
        if input == "3" {
            exit(0)
        }
        return nil
    }
}
