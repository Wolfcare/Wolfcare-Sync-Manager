import Foundation

if let runIndex = CommandLine.arguments.firstIndex(of: "--run") {
    let taskIDArg = CommandLine.arguments.indices.contains(runIndex + 1)
        ? CommandLine.arguments[runIndex + 1]
        : nil
    guard let taskIDArg, let taskID = UUID(uuidString: taskIDArg) else {
        ConfigIO.appendLog("ABORT: --run requires a valid task id")
        exit(1)
    }
    let ok = HeadlessRunner.run(taskID: taskID)
    exit(ok ? 0 : 1)
} else {
    WolfcareSyncManagerApp.main()
}
