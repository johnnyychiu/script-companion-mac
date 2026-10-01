-- Script Companion 0.5. Position-only, read-only probe (no Foundation/notes access).
-- The caller passes the previously confirmed presentation identity.
on run argv
    if (count of argv) is not 1 then error "Missing linked presentation identity."
    set expectedIdentity to item 1 of argv
    if expectedIdentity is "" then error "Link PowerPoint before reading slide position."
    with timeout of 8 seconds
        tell application "Microsoft PowerPoint"
            if (count of slide show windows) is not 1 then error "Exactly one slideshow must be running."
            set showWindow to slide show window 1
            set showPresentation to presentation of showWindow
            set showIdentity to name of showPresentation as text
            try
                set fullName to full name of showPresentation as text
                if fullName is not "" then set showIdentity to fullName
            end try
            if showIdentity is not expectedIdentity then error "The presentation changed. Link again to confirm it."
            set totalSlides to count of slides of showPresentation
            if totalSlides < 1 or totalSlides > 2000 then error "Unsupported slide count."
            set currentSlide to slide of slide show view of showWindow
            set slideNumber to slide index of currentSlide
            set slideIDText to ""
            try
                set slideIDText to slide ID of currentSlide as text
            end try
        end tell
        return (slideNumber as text) & tab & (totalSlides as text) & tab & slideIDText
    end timeout
end run
