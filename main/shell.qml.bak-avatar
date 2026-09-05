//@ pragma UseQApplication
import Quickshell
import Quickshell.Services.Pipewire

ShellRoot {
    // Keep the current sink bound so volume and mute state are valid.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Bar {}
}
