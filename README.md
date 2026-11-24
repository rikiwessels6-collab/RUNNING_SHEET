# Running Sheet (WBBL & BBL)

An offline over-rate running sheet for the third umpire, wrapped as an iPad app. It handles WBBL|12 and BBL|16 matches; you choose the competition per match on the 1st Innings tab.

Version: **v39 (24 Nov 2026)**, build 2.

## What's in the repo

```
Running Sheet.swiftpm/
  Package.swift            app name, bundle ID, version and build number
  RunningSheetApp.swift    app entry point, keeps the screen awake, saves when the app goes to the background
  SheetView.swift          the web view and the bridge for save, backups, PDF, email, print and export
  SheetModel.swift         saves the sheet to the app's files and keeps the last 20 backups
  PDFMaker.swift           A4 PDF of the over-rate report
  Resources/running-sheet.html   the running sheet itself (one self-contained HTML file)
  Assets.xcassets/         app icon
```

## Opening it

- **Swift Playgrounds (iPad or Mac):** download the repo as a ZIP (Code → Download ZIP), unzip it, and open `Running Sheet.swiftpm`.
- **Xcode (Mac):** double-click `Running Sheet.swiftpm`. Choose your iPad as the destination and press Run.
- **In a browser:** open `Running Sheet.swiftpm/Resources/running-sheet.html`. Everything works offline except the app-only features (automatic backups, PDF and email).

## Uploading a new build to TestFlight

1. Increase `bundleVersion` in `Package.swift` (or the Build number in Swift Playgrounds' App Settings).
2. Swift Playgrounds: App Settings → Upload to App Store Connect. Xcode: Product → Archive → Distribute App → TestFlight Internal Only.
3. In App Store Connect, answer the encryption question ("None of the algorithms mentioned above") and add the build to the internal testing group.

## Not included in this public copy

The searchable **📖 PCs** reader is empty here: the full text of the 2026-27 WBBL and BBL Playing Conditions is Cricket Australia's document and has been left out of this public repository. Everything else in the sheet, including the competition rules it uses, works as normal.
