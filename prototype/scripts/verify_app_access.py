"""Check notch geometry and cross-process launch exclusion without opening a UI."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="north-star-access-") as temporary:
    temporary = Path(temporary)
    source = temporary / "main.swift"
    source.write_text('''import AppKit
let args = CommandLine.arguments
if args[1] == "geometry" {
    let screen = NSRect(x: 0, y: 0, width: 1800, height: 1169)
    let left = NSRect(x: 0, y: 1131, width: 790, height: 38)
    let right = NSRect(x: 1010, y: 1131, width: 790, height: 38)
    func accessible(_ x: CGFloat) -> Bool {
        PanelPlacement.canAnchor(NSRect(x: x, y: 1131, width: 38, height: 38), on: screen, left: left, right: right)
    }
    precondition(accessible(100) && accessible(1500))
    precondition(!accessible(860) && !accessible(780) && !accessible(1000))
    precondition(!accessible(-10) && !accessible(1790))
    precondition(PanelPlacement.canAnchor(NSRect(x: 860, y: 1131, width: 38, height: 38), on: screen, left: nil, right: nil))
    precondition(!PanelPlacement.canAnchor(.zero, on: screen, left: nil, right: nil))
    for visible in [NSRect(x: 0, y: 0, width: 1800, height: 1125),
                    NSRect(x: -1920, y: -100, width: 1920, height: 1050),
                    NSRect(x: 100, y: 200, width: 400, height: 350)] {
        let frame = PanelPlacement.floatingFrame(size: NSSize(width: 470, height: 768), visible: visible)
        precondition(visible.contains(frame))
        precondition(frame.maxY <= visible.maxY - 16)
    }
    print("PASS: notch overlap, partial overlap, offscreen, unnotched and secondary-screen placement")
} else {
    let gate = SingleInstance(identifier: "local.northstar.lock-verification", directory: URL(fileURLWithPath: args[2]))
    let acquired = try gate.acquire()
    print(acquired ? "acquired" : "already-running")
    fflush(stdout)
    if acquired && args[1] == "hold" { _ = readLine() }
    withExtendedLifetime(gate) {}
}
''')
    binary = temporary / "check-access"
    subprocess.run(["swiftc", "-module-cache-path", str(root / "build/module-cache"),
                    "-framework", "AppKit", "-framework", "Carbon",
                    str(root / "native/AppAccess.swift"), str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary), "geometry"], check=True)
    holder = subprocess.Popen([str(binary), "hold", str(temporary / "lock")],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        assert holder.stdout.readline().strip() == "acquired"
        contenders = [subprocess.Popen([str(binary), "check", str(temporary / "lock")],
                                      stdout=subprocess.PIPE, text=True) for _ in range(6)]
        for contender in contenders:
            output, _ = contender.communicate(timeout=15)
            assert contender.returncode == 0 and output.strip() == "already-running", output
    finally:
        holder.communicate(input="done\n", timeout=10)
    assert subprocess.check_output([str(binary), "check", str(temporary / "lock")], text=True).strip() == "acquired"
    print("PASS: six simultaneous duplicate attempts excluded; lock released on exit")
