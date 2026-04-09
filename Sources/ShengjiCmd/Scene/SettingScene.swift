

class SettingScene: BaseScene {
    
    override func render() {
        canvas.clean()

        canvas.drawText(x: 4, y: 3, text: "设置", foreground: .yellow)
        canvas.drawText(x: 4, y: 6, text: "当前版本为最小原型，设置项尚未开放", foreground: .yellow)
        canvas.drawText(x: 4, y: 9, text: "输入 b 返回主菜单", foreground: .yellow)

        canvas.render()
    }

    override func handleInput(_ input: String) -> SceneTransition? {
        if input.lowercased() == "b" {
            return .mainMenu
        }
        return nil
    }
}
