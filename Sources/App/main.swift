import Foundation

if CommandLine.arguments.contains("--run") {
    let ok = HeadlessRunner.run()
    exit(ok ? 0 : 1)
} else {
    WolfcareSyncManagerApp.main()
}
