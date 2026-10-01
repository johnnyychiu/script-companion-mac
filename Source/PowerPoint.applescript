-- Script Companion 0.5: READ-ONLY PowerPoint notes/status adapter.
-- Slide buttons use a separate, opt-in native keyboard shortcut.
use framework "Foundation"
use scripting additions

on run argv
    set actionName to item 1 of argv
    set expectedIdentity to ""
    if (count of argv) > 1 then set expectedIdentity to item 2 of argv
    if actionName is not in {"status", "snapshot"} then error "Unsupported command."
    with timeout of 45 seconds
        tell application "Microsoft PowerPoint"
            set showCount to count of slide show windows
            if showCount is 0 then error "No slideshow is running. Start Presenter View first."
            if showCount is not 1 then error "More than one slideshow is running. Close the extra show before linking."
            set showWindow to slide show window 1
            set showPresentation to presentation of showWindow
            set showName to name of showPresentation as text
            set showIdentity to showName
            try
                set fullName to full name of showPresentation as text
                if fullName is not "" then set showIdentity to fullName
            end try
            if expectedIdentity is not "" and expectedIdentity is not showIdentity then error "The presentation changed. Link again to confirm the new presentation."
            set totalSlides to count of slides of showPresentation
            if totalSlides < 1 or totalSlides > 2000 then error "This prototype supports 1 to 2,000 slides."
            set showView to slide show view of showWindow
            set slideNumber to slide index of slide of showView
        end tell
        set rows to current application's NSMutableArray's array()
        if actionName is "snapshot" then
            repeat with n from 1 to totalSlides
                tell application "Microsoft PowerPoint" to set oneSlide to slide n of showPresentation
                rows's addObject:(my readSlideRecord(oneSlide, n))
            end repeat
        end if
        -- Re-read the actual current slide after extraction/navigation.
        tell application "Microsoft PowerPoint"
            if (count of slides of showPresentation) is not totalSlides then error "Slides changed while reading. Refresh notes and try again."
            set slideNumber to slide index of slide of showView
            set currentSlide to slide slideNumber of showPresentation
        end tell
        set currentRecord to my readSlideRecord(currentSlide, slideNumber)
        set resultObject to current application's NSMutableDictionary's dictionary()
        resultObject's setObject:showName forKey:"name"
        resultObject's setObject:showIdentity forKey:"identity"
        resultObject's setObject:slideNumber forKey:"number"
        resultObject's setObject:totalSlides forKey:"total"
        resultObject's setObject:currentRecord forKey:"current"
        if actionName is "snapshot" then resultObject's setObject:rows forKey:"slides"
        set jsonData to current application's NSJSONSerialization's dataWithJSONObject:resultObject options:0 |error|:(missing value)
        if jsonData is missing value then error "Could not encode PowerPoint notes."
        set jsonText to current application's NSString's alloc()'s initWithData:jsonData encoding:(current application's NSUTF8StringEncoding)
        return jsonText as text
    end timeout
end run

on readSlideRecord(oneSlide, n)
    set noteText to ""
    set notesOK to true
    set noteError to ""
    set slideIDText to ""
    set slideTitle to "Slide " & (n as text)
    tell application "Microsoft PowerPoint"
        try
            set slideIDText to slide ID of oneSlide as text
        end try
        -- Standard title placeholder, with a neutral fallback for non-title layouts.
        try
            set candidate to content of text range of text frame of place holder 1 of oneSlide
            if candidate is not missing value and candidate is not "" then set slideTitle to candidate as text
        end try
        try
            -- The standard speaker-notes BODY is placeholder 2, not notes-page headers.
            set candidate to content of text range of text frame of place holder 2 of notes page of oneSlide
            if candidate is not missing value then set noteText to candidate as text
        on error errorText number errorNumber
            set notesOK to false
            set noteError to "Notes body unavailable (" & (errorNumber as text) & "). " & errorText
        end try
    end tell
    set row to current application's NSMutableDictionary's dictionary()
    row's setObject:n forKey:"number"
    row's setObject:slideIDText forKey:"id"
    row's setObject:slideTitle forKey:"title"
    row's setObject:noteText forKey:"notes"
    row's setObject:(current application's NSNumber's numberWithBool:notesOK) forKey:"notesOK"
    row's setObject:noteError forKey:"notesError"
    return row
end readSlideRecord
