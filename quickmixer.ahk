;================================================================================;
;	QuickMixer - Fast access to Windows Volume Mixer (SndVol)                    ;
;	Copyright (C) 2026  Fooly Cooly https://github.com/Fooly-Cooly               ;
;	Licensed under the MIT License https://opensource.org/licenses/MIT           ;
;================================================================================;

#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Input"
SetWinDelay -1
SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Screen"
DetectHiddenWindows true

; ──────────────────────────────────────────────
; Target & State
; ──────────────────────────────────────────────
global MixerTarget        := "ahk_class #32770 ahk_exe sndvol.exe"
global CachedMixerHwnd    := 0
global ForegroundHook     := 0
global ForegroundCb       := 0
global ScriptJob          := 0

; ──────────────────────────────────────────────
; Defaults
; ──────────────────────────────────────────────
global IniFile            := RegExReplace(A_ScriptName, "\.[^.]+$") . ".ini"
global HotkeyValue        := "^!v"
global TrayIconEnabled    := true
global MixerMode          := "Full"    ; "Full" (all apps & devices) or "Master" (single slider)
global MinimalDecorations := true      ; Strips titlebar in Full mode for a clean flyout look
global PrewarmEnabled     := true      ; Keeps instance warm in background for 0ms instant pop-in
global PosX               := 0
global PosY               := 0

; Initialize kernel job object so any sndvol child process is unconditionally
; terminated by the Windows kernel if this script exits or crashes (32-bit & 64-bit compatible)
ScriptJob := CreateScriptJob()

OnExit CleanUp

LoadSettings()

; Register WinEvent callback for event-driven blur detection
ForegroundCb := CallbackCreate(OnForegroundChange, "F", 7)

if TrayIconEnabled {
    appIcon := FileExist(A_ScriptDir "\quickmixer.ico") ? (A_ScriptDir "\quickmixer.ico") : "sndvol.exe"
    TraySetIcon appIcon, 1
    A_IconHidden := false
    SetupTrayMenu()
    ApplyHotkey()
    
    ; Pre-warm instance silently in background if Full mode & Prewarm enabled
    if (PrewarmEnabled && MixerMode = "Full")
        SetTimer PrewarmMixer, -100
} else {
    A_IconHidden := true
    OpenVolumeMixerAt(PosX, PosY)
    ExitApp()
}

; ──────────────────────────────────────────────
; Windows Job Object (Kernel-Enforced Child Process Cleanup)
; ──────────────────────────────────────────────
CreateScriptJob() {
    hJob := DllCall("CreateJobObjectW", "ptr", 0, "ptr", 0, "ptr")
    if !hJob
        return 0

    ; 144 bytes on 64-bit AHK, 112 bytes on 32-bit AHK
    jobSize := (A_PtrSize = 8) ? 144 : 112
    info := Buffer(jobSize, 0)
    ; BasicLimitInformation.LimitFlags at offset 16 (JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000)
    NumPut("uint", 0x2000, info, 16)

    ; JobObjectExtendedLimitInformation = 9
    if !DllCall("SetInformationJobObject", "ptr", hJob, "int", 9, "ptr", info, "uint", jobSize) {
        DllCall("CloseHandle", "ptr", hJob)
        return 0
    }
    return hJob
}

AssignPidToJob(hJob, pid) {
    if (!hJob || !pid)
        return false
    ; PROCESS_ALL_ACCESS (0x1F0FFF) ensures compatibility across 32-bit WOW64 and 64-bit
    hProcess := DllCall("OpenProcess", "uint", 0x1F0FFF, "int", 0, "uint", pid, "ptr")
    if !hProcess
        return false
    res := DllCall("AssignProcessToJobObject", "ptr", hJob, "ptr", hProcess)
    DllCall("CloseHandle", "ptr", hProcess)
    return res
}

; ──────────────────────────────────────────────
; Clean up hooks, callbacks, and cached processes on exit
; ──────────────────────────────────────────────
CleanUp(*) {
    global ForegroundHook, ForegroundCb, ScriptJob, CachedMixerHwnd
    if ForegroundHook {
        DllCall("UnhookWinEvent", "ptr", ForegroundHook)
        ForegroundHook := 0
    }
    if ForegroundCb {
        CallbackFree(ForegroundCb)
        ForegroundCb := 0
    }
    if (CachedMixerHwnd && DllCall("IsWindow", "ptr", CachedMixerHwnd)) {
        WinClose CachedMixerHwnd
        CachedMixerHwnd := 0
    }
    if ScriptJob {
        DllCall("CloseHandle", "ptr", ScriptJob)
        ScriptJob := 0
    }
}

; ──────────────────────────────────────────────
; INI Read with type validation and fallback
; ──────────────────────────────────────────────
IniReadSafe(file, section, key, default) {
    try {
        val := IniRead(file, section, key, default)
        return (val = "" || val = "ERROR") ? default : val
    }
    return default
}

; ──────────────────────────────────────────────
; Screen boundary & multi-monitor clamping
; Uses reference point (cursor/center) to lock to the correct display
; ──────────────────────────────────────────────
ClampCoordinates(x, y, w, h, refX := unset, refY := unset) {
    centerX := IsSet(refX) ? refX : (x + (w // 2))
    centerY := IsSet(refY) ? refY : (y + (h // 2))

    monCount := MonitorGetCount()
    chosenMon := MonitorGetPrimary()

    Loop monCount {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if (centerX >= ml && centerX < mr && centerY >= mt && centerY < mb) {
            chosenMon := A_Index
            break
        }
    }

    MonitorGetWorkArea(chosenMon, &wl, &wt, &wr, &wb)
    clampedX := Max(wl + 4, Min(x, wr - w - 4))
    clampedY := Max(wt + 4, Min(y, wb - h - 4))
    return { x: clampedX, y: clampedY }
}

; ──────────────────────────────────────────────
; Fast non-blocking wait for mixer window
; ──────────────────────────────────────────────
WaitForMixerWindow(timeoutMs := 1200) {
    global MixerTarget
    startTime := A_TickCount
    while (A_TickCount - startTime < timeoutMs) {
        if (hwnd := WinExist(MixerTarget))
            return hwnd
        Sleep 20
    }
    return 0
}

; ──────────────────────────────────────────────
; State check: Is mixer currently visible on screen?
; ──────────────────────────────────────────────
IsMixerVisible() {
    global CachedMixerHwnd, MixerTarget
    if (CachedMixerHwnd && DllCall("IsWindow", "ptr", CachedMixerHwnd))
        return DllCall("IsWindowVisible", "ptr", CachedMixerHwnd)
    return WinActive(MixerTarget)
}

; ──────────────────────────────────────────────
; Dismiss Mixer (Hide if pre-warmed, Close if cold or Master)
; ──────────────────────────────────────────────
DismissMixer() {
    global CachedMixerHwnd, ForegroundHook, PrewarmEnabled, MixerTarget
    if ForegroundHook {
        DllCall("UnhookWinEvent", "ptr", ForegroundHook)
        ForegroundHook := 0
    }
    if (CachedMixerHwnd && DllCall("IsWindow", "ptr", CachedMixerHwnd)) {
        if PrewarmEnabled {
            ; Simply hide window (SW_HIDE completely removes it from rendering and taskbar)
            DllCall("ShowWindow", "ptr", CachedMixerHwnd, "int", 0) ; SW_HIDE
        } else {
            ; Cold mode: terminate completely so SndVol never lingers
            WinClose CachedMixerHwnd
            CachedMixerHwnd := 0
        }
    } else if WinExist(MixerTarget) {
        WinClose MixerTarget
    }
}

; ──────────────────────────────────────────────
; Pre-warm Full mixer instance silently in background
; ──────────────────────────────────────────────
PrewarmMixer() {
    global CachedMixerHwnd, MixerMode, MinimalDecorations, ScriptJob, PrewarmEnabled
    if (!PrewarmEnabled || MixerMode != "Full")
        return
    if (CachedMixerHwnd && DllCall("IsWindow", "ptr", CachedMixerHwnd))
        return

    try {
        Run "sndvol", , "Hide", &pid
        if ScriptJob
            AssignPidToJob(ScriptJob, pid)

        hwnd := WaitForMixerWindow(1200)
        if !hwnd
            return

        ; Immediately park off-screen and mark as toolwindow
        WinMove -32000, -32000, , , hwnd
        WinSetExStyle "+0x80", hwnd
        WinSetExStyle "-0x40000", hwnd
        if MinimalDecorations
            WinSetStyle "-0xC00000", hwnd

        ; Wait briefly for sndvol's internal startup ShowWindow to finish, then guarantee SW_HIDE
        Sleep 200
        DllCall("ShowWindow", "ptr", hwnd, "int", 0) ; SW_HIDE

        CachedMixerHwnd := hwnd
    }
}

; ──────────────────────────────────────────────
; Event-Driven Blur: dismisses mixer on focus change
; ──────────────────────────────────────────────
OnForegroundChange(hHook, event, hwnd, idObject, idChild, idThread, dwmsEventTime) {
    global CachedMixerHwnd
    try {
        if (!hwnd || !DllCall("IsWindow", "ptr", hwnd))
            return
        if (!CachedMixerHwnd || !DllCall("IsWindow", "ptr", CachedMixerHwnd))
            return

        mixerPid  := WinGetPID(CachedMixerHwnd)
        activePid := WinGetPID(hwnd)

        ; When the active window is no longer the mixer, dismiss it
        if (activePid != mixerPid)
            DismissMixer()
    }
}

; ──────────────────────────────────────────────
; Core Launcher: Zero-latency open & position
; ──────────────────────────────────────────────
LaunchMixer(x := 0, y := 0, isAboveTray := false) {
    global MixerTarget, MixerMode, MinimalDecorations, CachedMixerHwnd, ForegroundHook, ForegroundCb, PrewarmEnabled, ScriptJob
    static isBusy := false
    static lastTrigger := 0

    ; Debounce rapid consecutive triggers
    now := A_TickCount
    if (now - lastTrigger < 250)
        return
    lastTrigger := now

    ; Toggle: if mixer is currently open & visible, dismiss it
    if IsMixerVisible() {
        DismissMixer()
        return
    }

    if isBusy
        return
    isBusy := true

    try {
        hwnd := 0

        ; Path A: Fast pre-warmed instance (Full mode)
        if (MixerMode = "Full" && PrewarmEnabled && CachedMixerHwnd && DllCall("IsWindow", "ptr", CachedMixerHwnd)) {
            hwnd := CachedMixerHwnd
        } else {
            ; Path B: Cold launch
            CachedMixerHwnd := 0
            cmd := (MixerMode = "Master") ? "sndvol -f" : "sndvol"
            Run cmd, , "Hide", &pid
            if ScriptJob
                AssignPidToJob(ScriptJob, pid)

            hwnd := WaitForMixerWindow(1200)
            if !hwnd {
                MsgBox "Volume Mixer failed to open.", "Error", "Icon! T3"
                return
            }

            ; Apply toolwindow style so taskbar ignores it
            if (MixerMode = "Full") {
                WinSetExStyle "+0x80", hwnd
                WinSetExStyle "-0x40000", hwnd
                if MinimalDecorations
                    WinSetStyle "-0xC00000", hwnd
                CachedMixerHwnd := hwnd
            }
        }

        ; Measure geometry
        WinGetPos , , &mw, &mh, hwnd
        if (mw <= 0 || mh <= 0) {
            mw := (MixerMode = "Master") ? 200 : 380
            mh := 320
        }

        refX := 0
        refY := 0

        if isAboveTray {
            MouseGetPos &mx, &my
            refX := mx
            refY := my
            tbHwnd := WinExist("ahk_class Shell_TrayWnd")
            ty := 0
            if tbHwnd
                WinGetPos , &ty, , , tbHwnd

            targetX := mx - (mw // 2)
            targetY := (tbHwnd && ty > 0) ? (ty - mh - 5) : (my - mh - 5)
        } else {
            ; Centered on mouse position for hotkey invocation
            refX := x
            refY := y
            targetX := x - (mw // 2)
            targetY := y - (mh // 2)
        }

        pos := ClampCoordinates(targetX, targetY, mw, mh, refX, refY)

        ; Move into position and reveal cleanly
        WinMove pos.x, pos.y, , , hwnd
        DllCall("ShowWindow", "ptr", hwnd, "int", 5) ; SW_SHOW
        WinActivate hwnd

        ; Register event-driven blur hook in Full mode so clicking outside dismisses it
        if (MixerMode = "Full") {
            if ForegroundHook
                DllCall("UnhookWinEvent", "ptr", ForegroundHook)
            ForegroundHook := DllCall("SetWinEventHook",
                "uint", 3, "uint", 3,      ; EVENT_SYSTEM_FOREGROUND
                "ptr", 0, "ptr", ForegroundCb,
                "uint", 0, "uint", 0,
                "uint", 0                 ; WINEVENT_OUTOFCONTEXT
            )
        }
    } finally {
        isBusy := false
    }
}

OpenVolumeMixerAt(x, y) {
    LaunchMixer(x, y, false)
}

OpenVolumeMixerAtMouse(*) {
    MouseGetPos &mx, &my
    LaunchMixer(mx, my, false)
}

OpenVolumeMixerAboveTray(*) {
    LaunchMixer(0, 0, true)
}

; ──────────────────────────────────────────────
; Tray icon message handler
; ──────────────────────────────────────────────
TrayClick(wParam, lParam, msg, hwnd) {
    ; 0x202 = WM_LBUTTONUP
    if (lParam = 0x202)
        OpenVolumeMixerAboveTray()
}

; ──────────────────────────────────────────────
; Load + validate all settings from INI
; ──────────────────────────────────────────────
LoadSettings() {
    global IniFile, PosX, PosY, HotkeyValue, TrayIconEnabled, MixerMode, MinimalDecorations, PrewarmEnabled

    if !FileExist(IniFile) {
        MouseGetPos &PosX, &PosY
        return
    }

    rawX := IniReadSafe(IniFile, "Position", "X", 0)
    rawY := IniReadSafe(IniFile, "Position", "Y", 0)
    PosX := IsInteger(rawX) ? Max(SysGet(76), Min(Integer(rawX), SysGet(78))) : 0
    PosY := IsInteger(rawY) ? Max(SysGet(77), Min(Integer(rawY), SysGet(79))) : 0

    if (!PosX && !PosY)
        MouseGetPos &PosX, &PosY

    rawHK := IniReadSafe(IniFile, "Settings", "Hotkey", "^!v")
    try {
        Hotkey rawHK, (*) => 0
        Hotkey rawHK, "Off"
        HotkeyValue := rawHK
    } catch {
        HotkeyValue := "^!v"
        IniWrite HotkeyValue, IniFile, "Settings", "Hotkey"
    }

    rawTray := IniReadSafe(IniFile, "Settings", "TrayIcon", "1")
    TrayIconEnabled := (rawTray = "1" || rawTray = "0") ? (rawTray = "1") : true

    rawMode := IniReadSafe(IniFile, "Settings", "MixerMode", "Full")
    MixerMode := (rawMode = "Master") ? "Master" : "Full"

    rawDeco := IniReadSafe(IniFile, "Settings", "MinimalDecorations", "1")
    MinimalDecorations := (rawDeco = "1" || rawDeco = "0") ? (rawDeco = "1") : true

    rawPrewarm := IniReadSafe(IniFile, "Settings", "Prewarm", "1")
    PrewarmEnabled := (rawPrewarm = "1" || rawPrewarm = "0") ? (rawPrewarm = "1") : true
}

; ──────────────────────────────────────────────
; Save all settings to INI
; ──────────────────────────────────────────────
SaveSettings() {
    global IniFile, PosX, PosY, HotkeyValue, TrayIconEnabled, MixerMode, MinimalDecorations, PrewarmEnabled
    IniWrite PosX,                               IniFile, "Position", "X"
    IniWrite PosY,                               IniFile, "Position", "Y"
    IniWrite HotkeyValue,                        IniFile, "Settings", "Hotkey"
    IniWrite (TrayIconEnabled ? "1" : "0"),      IniFile, "Settings", "TrayIcon"
    IniWrite MixerMode,                          IniFile, "Settings", "MixerMode"
    IniWrite (MinimalDecorations ? "1" : "0"),   IniFile, "Settings", "MinimalDecorations"
    IniWrite (PrewarmEnabled ? "1" : "0"),       IniFile, "Settings", "Prewarm"
}

; ──────────────────────────────────────────────
; Register hotkey dynamically (ensures "On" state)
; ──────────────────────────────────────────────
ApplyHotkey() {
    global HotkeyValue
    try {
        Hotkey HotkeyValue, OpenVolumeMixerAtMouse, "On"
    } catch as e {
        MsgBox "Could not register hotkey '" HotkeyValue "':`n" e.Message
            . "`n`nReverting to default (^!v).", "Hotkey Error", "Icon! T5"
        HotkeyValue := "^!v"
        IniWrite HotkeyValue, IniFile, "Settings", "Hotkey"
        Hotkey HotkeyValue, OpenVolumeMixerAtMouse, "On"
    }
}

; ──────────────────────────────────────────────
; Build tray menu and bind click handler
; ──────────────────────────────────────────────
SetupTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add "Open Volume Mixer", OpenVolumeMixerAboveTray
    A_TrayMenu.Add
    A_TrayMenu.Add "Settings", ShowSettings
    A_TrayMenu.Add
    A_TrayMenu.Add "Exit", (*) => ExitApp()
    A_TrayMenu.Default := "Open Volume Mixer"
    OnMessage(0x404, TrayClick)
}

; ──────────────────────────────────────────────
; Settings GUI
; ──────────────────────────────────────────────
ShowSettings(*) {
    global HotkeyValue, TrayIconEnabled, PosX, PosY, MixerMode, MinimalDecorations, PrewarmEnabled, CachedMixerHwnd

    sGui := Gui("+AlwaysOnTop", "QuickMixer Settings")
    sGui.SetFont("s10", "Segoe UI")

    ; --- Mixer Mode Group ---
    sGui.Add "GroupBox", "x10 y10 w320 h130", "Mixer Mode"
    radFull   := sGui.Add("Radio", "x25 y35 Checked" . (MixerMode = "Full" ? 1 : 0), "Full Volume Mixer (all apps && devices)")
    radMaster := sGui.Add("Radio", "x25 y60 Checked" . (MixerMode = "Master" ? 1 : 0), "Master Volume only (single slider)")
    chkDeco   := sGui.Add("Checkbox", "x25 y85 Checked" . MinimalDecorations, "Minimal decorations (borderless flyout)")
    chkWarm   := sGui.Add("Checkbox", "x25 y110 Checked" . PrewarmEnabled, "Instant reveal (keep pre-warmed in background)")

    ToggleDecoEnable(*) {
        chkDeco.Enabled := radFull.Value
        chkWarm.Enabled := radFull.Value
    }
    radFull.OnEvent("Click", ToggleDecoEnable)
    radMaster.OnEvent("Click", ToggleDecoEnable)
    ToggleDecoEnable()

    ; --- Mixer Positioning Group ---
    sGui.Add "GroupBox", "x10 y150 w320 h98", "Mixer Positioning"
    tiCtrl   := sGui.Add("Checkbox", "x25 y175 Checked" . TrayIconEnabled, "Show tray icon (speaker)")
    sGui.Add "Text",     "x25 y211",             "Fallback:"
    sGui.Add "Text",     "x85 y211",             "X:"
    xCtrl    := sGui.Add("Edit", "x100 y207 w48", PosX)
    sGui.Add "Text",     "x156 y211",            "Y:"
    yCtrl    := sGui.Add("Edit", "x171 y207 w48", PosY)
    btnMouse := sGui.Add("Button", "x229 y206 w90 h26", "⟳ Mouse")
    btnMouse.OnEvent("Click", (*) => (MouseGetPos(&mx, &my), xCtrl.Value := mx, yCtrl.Value := my))

    ; --- Hotkey Group ---
    sGui.Add "GroupBox", "x10 y258 w320 h85", "Hotkey"
    sGui.Add "Text",     "x25 y283",             "Hotkey:"
    hkCtrl := sGui.Add("Edit", "x80 y280 w239",  HotkeyValue)
    sGui.Add "Text",     "x25 y313 w290",         "Modifiers: ^ Ctrl  ! Alt  + Shift  # Win"

    ; --- Action Buttons ---
    sGui.Add("Button", "x10  y355 w155 h32 Default", "Save").OnEvent("Click", SaveAndClose)
    sGui.Add("Button", "x175 y355 w155 h32",          "Cancel").OnEvent("Click", (*) => sGui.Destroy())
    sGui.Show "w340 h400"

    SaveAndClose(*) {
        global HotkeyValue, TrayIconEnabled, PosX, PosY, MixerMode, MinimalDecorations, PrewarmEnabled, CachedMixerHwnd

        newX := Trim(xCtrl.Value)
        newY := Trim(yCtrl.Value)
        if !IsInteger(newX) || !IsInteger(newY) {
            MsgBox "X and Y must be whole numbers.", "Invalid Input", "Icon! T4"
            return
        }

        newHK := Trim(hkCtrl.Value)
        if (newHK = "") {
            MsgBox "Hotkey cannot be empty.", "Invalid Input", "Icon! T4"
            return
        }
        try {
            Hotkey newHK, (*) => 0
            Hotkey newHK, "Off"
        } catch {
            MsgBox "'" newHK "' is not a valid hotkey.`n`nNo changes were saved.", "Invalid Hotkey", "Icon! T5"
            return
        }

        oldTray    := TrayIconEnabled
        oldMode    := MixerMode
        oldDeco    := MinimalDecorations
        oldPrewarm := PrewarmEnabled
        oldHK      := HotkeyValue

        ; Disable previous hotkey cleanly if changed
        if (oldHK != newHK) {
            try Hotkey oldHK, "Off"
        }

        PosX               := Integer(newX)
        PosY               := Integer(newY)
        HotkeyValue        := newHK
        TrayIconEnabled    := tiCtrl.Value
        MixerMode          := radFull.Value ? "Full" : "Master"
        MinimalDecorations := chkDeco.Value
        PrewarmEnabled     := chkWarm.Value

        ; If MinimalDecorations, Prewarm, or Mode changed, terminate any active cached instance
        ; so the new style/mode takes effect immediately without needing a script restart!
        if ((oldDeco != MinimalDecorations || oldMode != MixerMode || oldPrewarm != PrewarmEnabled) && CachedMixerHwnd) {
            if DllCall("IsWindow", "ptr", CachedMixerHwnd)
                WinClose CachedMixerHwnd
            CachedMixerHwnd := 0
            ; Re-trigger prewarm with the new styling immediately
            if (PrewarmEnabled && MixerMode = "Full")
                SetTimer PrewarmMixer, -100
        }

        SaveSettings()
        ApplyHotkey()
        sGui.Destroy()

        if (oldTray != TrayIconEnabled)
            MsgBox "Restart the script for tray icon changes to take effect.", "Restart Required", "Icon! T5"
    }
}
