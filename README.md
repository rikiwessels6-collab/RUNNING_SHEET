# Running Sheet (WBBL & BBL)

An offline over-rate running sheet for the third umpire, wrapped as an iPad app. It handles WBBL|12 and BBL|16 matches; you choose the competition per match on the 1st Innings tab.

Version: **v49 (27 Nov 2026)** – add or change the bowler for any over already started (match screen or Summary); Summary stoppages show min:sec only.

## What's in the repo

```
Running Sheet.swiftpm/
  Package.swift            app name, bundle ID, version and build number
  RunningSheetApp.swift    app entry point, keeps the screen awake, saves when the app goes to the background
  SheetView.swift          the web view and the bridge for save, backups, PDF, email, print and export
  SheetModel.swift         saves the sheet to the app's files and keeps the last 20 backups
  PDFMaker.swift           A4 PDF of the over-rate report
  DLSScanner.swift         photographs the DLS sheet and reads it on the device
  Resources/running-sheet.html   the running sheet itself (one self-contained HTML file)
  Assets.xcassets/         app icon
```

## Opening it

- **Swift Playgrounds (iPad or Mac):** download the repo as a ZIP (Code → Download ZIP), unzip it, and open `Running Sheet.swiftpm`.
- **Xcode (Mac):** double-click `Running Sheet.swiftpm`. Choose your iPad as the destination and press Run.
- **In a browser:** open `Running Sheet.swiftpm/Resources/running-sheet.html`. Everything works offline except the app-only features (automatic backups, PDF and email).

## Automatic TestFlight uploads (GitHub Actions)

Every push to `main` that changes `Running Sheet.swiftpm/` builds the app on a GitHub-hosted Mac and uploads it to TestFlight (`.github/workflows/testflight.yml`). You can also start it by hand: **Actions → Upload to TestFlight → Run workflow**. Build numbers are set automatically (101, 102, …).

It needs four repository secrets (**Settings → Secrets and variables → Actions → New repository secret**):

| Secret | What goes in it |
|---|---|
| `ASC_KEY_ID` | Key ID of the App Store Connect API key |
| `ASC_ISSUER_ID` | Issuer ID shown above the list of API keys |
| `ASC_KEY_P8` | The full text of the downloaded `AuthKey_XXXX.p8` file, including the BEGIN and END lines |
| `APPLE_TEAM_ID` | Your 10-character Team ID (developer.apple.com → Account → Membership details) |

The API key needs **Admin** access so it can sign the app. `ci/project.yml` turns the Swift Playgrounds project into an Xcode project during the build.

## Uploading by hand from Swift Playgrounds

1. Increase `bundleVersion` in `Package.swift` (or the Build number in Swift Playgrounds' App Settings).
2. Swift Playgrounds: App Settings → Upload to App Store Connect. Xcode: Product → Archive → Distribute App → TestFlight Internal Only.
3. In App Store Connect, answer the encryption question ("None of the algorithms mentioned above") and add the build to the internal testing group.

## Not included in this public copy

The searchable **📖 PCs** reader is empty here: the full text of the 2026-27 WBBL and BBL Playing Conditions is Cricket Australia's document and has been left out of this public repository. Everything else in the sheet, including the competition rules it uses, works as normal.
