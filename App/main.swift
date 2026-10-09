import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate

if AppDelegate.isDemoExit {
    // CI has a window server, but didFinishLaunching is not guaranteed to run
    // before a runner kills a hung process. Leave if startup never completes.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        logLine("ferret: demo-exit fallback")
        exit(0)
    }
}

if OnboardingSnapshot.isRequested {
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
        logLine("ferret: demo-snapshot timed out")
        exit(2)
    }
}

app.run()
