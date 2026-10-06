-- Run against a disposable build with a separate bundle/App Group identity.
-- A hidden main window after background capture is revealed when the app above quits.
on run argv
    set appPath to item 1 of argv
    set testBundle to item 2 of argv
    if testBundle does not start with "org.example." then error "Use an isolated test bundle"
    tell application "System Events"
        if exists (first application process whose bundle identifier is testBundle) then
            error "Quit the test app before the cold-launch check"
        end if
    end tell
    set storePath to item 3 of argv
    set serviceURL to item 4 of argv
    do shell script "/usr/bin/open -g --env " & quoted form of ("RECEPTOR_TEST_STORE=" & storePath) & " --env " & quoted form of ("RECEPTOR_TEST_URL=" & serviceURL) & " -a " & quoted form of appPath & " 'receptor-regression://compose?source=regression-test'"
    repeat 100 times
        try
            tell application "System Events"
                if exists (first application process whose bundle identifier is testBundle) then
                    set appProcess to first application process whose bundle identifier is testBundle
                    if (count windows of appProcess) > 0 then exit repeat
                end if
            end tell
        end try
        delay 0.1
    end repeat
    tell application "System Events"
        set appProcess to first application process whose bundle identifier is testBundle
        if (count (windows of appProcess whose name is "Receptor")) is not 0 then
            error "Background capture exposed the main window"
        end if
        if (count windows of appProcess) is not 1 then error "Capture panel did not appear"
        click button 1 of group 1 of window 1 of appProcess
        delay 0.3
        if (count windows of appProcess) is not 0 then error "Cancel left a background window"
    end tell
    do shell script "/usr/bin/open -g -a " & quoted form of appPath & " 'receptor-regression://recept?text=Receptor%20regression%20capture&source=regression-test'"
    repeat 100 times
        try
            do shell script "/usr/bin/grep -q 'FLUSH-COMPLETE sent=1' " & quoted form of (storePath & "/debug.log")
            exit repeat
        end try
        delay 0.1
    end repeat
    tell application "System Events"
        if (count windows of appProcess) is not 0 then error "Sending exposed a background window"
    end tell
    -- Opening Receptor explicitly still works, including after closing it.
    do shell script "/usr/bin/open -a " & quoted form of appPath
    delay 0.5
    tell application "System Events"
        if (count (windows of appProcess whose name is "Receptor")) is not 1 then error "Explicit open failed"
        click menu bar item 1 of menu bar 2 of appProcess
        delay 0.3
        if (count windows of appProcess) is not 0 then error "Menu-bar toggle did not close the window"
        click menu bar item 1 of menu bar 2 of appProcess
        delay 0.3
        if (count (windows of appProcess whose name is "Receptor")) is not 1 then error "Menu-bar reopen failed"
        set frontmost of appProcess to true
        keystroke "q" using command down
    end tell
    repeat 50 times
        try
            tell application "System Events"
                if testBundle is not in (bundle identifier of every application process) then
                    exit repeat
                end if
            end tell
        end try
        delay 0.1
    end repeat
    tell application "System Events"
        if testBundle is in (bundle identifier of every application process) then error "Command-Q did not terminate Receptor"
    end tell
    do shell script "/usr/bin/open --env " & quoted form of ("RECEPTOR_TEST_STORE=" & storePath) & " --env " & quoted form of ("RECEPTOR_TEST_URL=" & serviceURL) & " -a " & quoted form of appPath
    repeat 100 times
        try
            tell application "System Events"
                if exists (first application process whose bundle identifier is testBundle) then
                    set appProcess to first application process whose bundle identifier is testBundle
                    if (count (windows of appProcess whose name is "Receptor")) is 1 then
                        return "PASS: background compose/send, cancel, menu-bar toggle/reopen, Command-Q and cold explicit open"
                    end if
                end if
            end tell
        end try
        delay 0.1
    end repeat
    error "Cold explicit open did not show the main window"
end run
