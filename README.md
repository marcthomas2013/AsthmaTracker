# Asthma Tracker

Asthma Tracker is an iOS/iPadOS SwiftUI app for tracking inhaler usage, exercise, and asthma progress, with HealthKit integration and SwiftData + CloudKit sync support.

## What the App Can Do

- Log inhaler doses with:
  - inhaler type (`Preventative`, `Reliever`, `Combined`)
  - reason for use
  - date/time taken
  - puff count
  - optional notes
- Save inhaler usage to HealthKit (`Inhaler Usage`) including metadata for inhaler type and reason.
- Read HealthKit data for:
  - peak expiratory flow
  - workouts/exercise
  - inhaler usage totals and recent entries
- Show dashboard trends:
  - latest peak flow and trend direction
  - recent exercise totals
  - inhaler usage in the last 7 and 30 days
- Manage reason lists in Settings:
  - reasons are scoped per inhaler type
  - custom reasons can be added per type
- Sync app data across Apple devices using SwiftData + CloudKit (after iCloud capability is configured).

## Current App Tabs

- **Log Dose**
  - Main data-entry flow for inhaler usage.
  - Segmented inhaler type selector.
  - Reason picker from per-type reason list.
  - Puff count stepper.
  - Notes field with keyboard dismissal support.
- **Dashboard**
  - Peak flow, exercise, and inhaler usage summaries.
  - Recent HealthKit inhaler usage entries.
- **History**
  - Local event history with inhaler type, reason, puffs, date/time, notes, and HealthKit sync status.
- **Settings**
  - HealthKit connection/sync status (including green tick when connected and synced).
  - Manual sync action.
  - Per-inhaler reason management.

## HealthKit Behavior

The app requests HealthKit permission to:

- **Read**
  - Peak Expiratory Flow Rate
  - Workouts
  - Inhaler Usage
- **Write**
  - Inhaler Usage

When a dose is logged, the selected date/time and puff count are written to HealthKit as an inhaler usage quantity sample.

## Sync Behavior

- The app attempts to auto-connect/sync HealthKit when launched.
- It also syncs on app lifecycle changes (active/background) and via manual **Sync Now**.
- A green check in Settings indicates the app is connected and has completed a successful sync.

## Data Model (SwiftData)

- `InhalerEvent`
  - `takenAt`, `inhalerTypeRaw`, `reason`, `puffCount`, `notes`, `isSyncedToHealthKit`
- `InhalerReasonOption`
  - `inhalerTypeRaw`, `reason`, `createdAt`

## Project Structure

- `Asthma Tracker/Asthma_TrackerApp.swift`  
  App entry point and SwiftData model container setup.
- `Asthma Tracker/ContentView.swift`  
  Main tab UI, logging flow, dashboard, history, settings.
- `Asthma Tracker/AsthmaDashboardViewModel.swift`  
  Health state, sync orchestration, and dashboard calculations.
- `Asthma Tracker/HealthKitManager.swift`  
  HealthKit authorization, reads, and writes.
- `Asthma Tracker/Item.swift`  
  SwiftData models and inhaler type definitions.

## Setup Notes

1. Open `Asthma Tracker.xcodeproj` in Xcode.
2. In target **Signing & Capabilities**, ensure:
   - HealthKit capability is enabled.
   - iCloud capability is enabled with CloudKit.
3. Configure an iCloud container (required for cross-device CloudKit sync).
4. Run on a real device for full HealthKit behavior.
5. For ads + ad removal monetization:
   - Add the `Google-Mobile-Ads-SDK` Swift Package to the app target.
   - In `Asthma Tracker/Info.plist`, set:
     - `GADApplicationIdentifier` to your AdMob App ID.
     - `AdMobBannerUnitID` to your banner ad unit ID.
     - `AdRemovalMonthlyProductID` to your App Store Connect monthly subscription product ID.
   - Create the monthly subscription in App Store Connect with the same product ID.

## Limitations / Notes

- HealthKit and CloudKit behavior depends on device permissions and account state.
- Simulator support for HealthKit data is limited compared to physical devices.
- Existing local stores from older incompatible schemas may not be automatically migrated.

## Build

Example CLI build:

```bash
xcodebuild -scheme "Asthma Tracker" -destination "generic/platform=iOS" build
```

