import Foundation

if let runIndex = CommandLine.arguments.firstIndex(of: "--run") {
    let taskIDArg = CommandLine.arguments.indices.contains(runIndex + 1)
        ? CommandLine.arguments[runIndex + 1]
        : nil
    guard let taskIDArg, let taskID = UUID(uuidString: taskIDArg) else {
        ConfigIO.appendLog("ABORT: --run requires a valid task id")
        exit(1)
    }

    // If the GUI is already open, hand the run to it (via ScheduledRunBridge)
    // so it shows up the normal way — progress bar, spinning menu bar icon,
    // live log — instead of running invisibly in this second process. The
    // running instance also takes care of its own once-schedule cleanup.
    if ScheduledRunBridge.forwardToRunningAppIfPossible(taskID: taskID) {
        exit(0)
    }

    let ok = HeadlessRunner.run(taskID: taskID)

    // A "Run once at" schedule is meant to fire exactly one time — clear it
    // afterward so the task doesn't keep showing a schedule that already fired.
    var tasks = ConfigIO.loadTasks()
    if let index = tasks.firstIndex(where: { $0.id == taskID }), case .once = tasks[index].schedule {
        try? LaunchAgentManager.remove(taskID: taskID)
        tasks[index].schedule = .off
        ConfigIO.saveTasks(tasks)
    }

    exit(ok ? 0 : 1)
} else {
    WolfcareSyncManagerApp.main()
}
