import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // The command line reaches `main` (storage design §6.8):
    // `nanoflow_ui <graph file> [--store <place>] [--session <id>]`.
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "nanoflow"
    // The screens are drawn for 1440×900; much smaller, they get cramped.
    self.contentMinSize = NSSize(width: 1100, height: 700)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
