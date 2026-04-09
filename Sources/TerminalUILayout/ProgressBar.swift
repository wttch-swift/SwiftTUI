extension ProgressBar: _LayoutNodeProducing {
    package func _makeLayoutNode() -> any _LayoutNode {
        _LeafNode(size: Size(w: width, h: 1)) { canvas, frame, _ in
            let filled = Int(Double(width) * value)
            canvas.drawText(x: frame.x, y: frame.y, text: String(repeating: "█", count: filled), foreground: fillColor, background: track)
            canvas.drawText(x: frame.x + filled, y: frame.y, text: String(repeating: "░", count: width-filled), foreground: fillColor, background: track)
        }
    }
}
