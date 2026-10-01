# Changelog

## 0.5.3 — notes at the top

Moved the slide number/title to the lower dashboard. Removed the top heading/spacer so the current line sits 4 CSS pixels below the content edge, in normal and compact modes. Kept the native title bar and existing PowerPoint-control code.

### Public-sharing preparation

Added a public README, reviewed browser screenshots, runnable test instructions, fresh test evidence, an MIT license for original work, retained third-party notices, contribution/privacy guidance, issue templates and browser CI. Made test browser paths portable. Removed inherited historical logs/results from the publication set and normalized generated sample PowerPoint metadata. Runtime source and the Mac builder remain byte-identical to the 0.5.3 package.

## 0.5.2

Removed the app's extra top margin and added **Move reader to top**, respecting the selected display's usable bounds. Not a borderless-window feature.

## 0.5.1

Added a confirmed reset of all slides' saved reading positions without changing notes, slide selection or timing.

## 0.5

Notes-first layout, cumulative presentation/per-slide timing, and position-only PowerPoint polling to reduce unnecessary notes reads. Real-world latency was not benchmarked.

## Earlier prototypes

Introduced the offline reader, Mac wrapper, experimental notes connection, independent line/slide controls, per-slide memory, clock, exported-image snapshots, and successive navigation recovery attempts. Not every experimental branch is included here: this version has static image previews, not live window capture.
