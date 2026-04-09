/// 声明一个由布局实现绘制的终端边框。
package struct _Box: View, _NeverView {
    package let style: BorderStyle

    package init(style: BorderStyle = .single) {
        self.style = style
    }
}
