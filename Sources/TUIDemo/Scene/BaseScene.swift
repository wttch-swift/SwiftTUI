import TerminalUI


class BaseScene: Scene {
    let canvas: Canvas
    required init(canvas: Canvas) {
        self.canvas = canvas
    }
    
    func render() {
        
    }
    
    func handleInput(_ input: String) -> SceneTransition? {
        return nil
    }
}