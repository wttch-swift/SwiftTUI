import TerminalUI


protocol Scene {
    init(canvas: Canvas)

    func render()

    func handleInput(_ input: String) -> SceneTransition?
}