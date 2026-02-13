# Notes

## Repository scan

- Tech stack: HarmonyOS NEXT ArkTS multi-module app (entry/location/map), hvigor build.
- Product: '遨游轨迹' app for recording cemetery visit tracks + tomb spots + media.
- Entry flow: EntryAbility -> Splash -> Login/Main based on AuthStore.
- Data strategy: local-first via preferences in TrackStore/AuthStore; sync via SyncService to AGC CloudDB/CloudStorage.
- Cloud: AGC Auth + Cloud DB zone 'aoyou' + CloudStorage image upload/restore.
- Key pages: Login, Main (My tracks/Public tracks), CreateOrEditTrack, TrackRecord (map+GPS), TrackDetail/TombSpotDetail.
- Observed potential legacy/demo page: entry/src/main/ets/pages/Index.ets has template-string syntax issues and likely not active route.
- Docs are detailed and aligned to implementation intent (v1.0 local-first, public/private visibility, Huawei login only).

## UX warning fix pass (2026-02-13)
- Fixed top/bottom rebound by adding or upgrading edgeEffect on all detected Scroll/List pages in entry module.
- Standardized to: `.edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })`.
- Updated files: About, UserAgreement, PrivacyPolicy, ProfileEdit, Feedback, CreateOrEditTrack, Main, TrackDetail, TombSpotDetail, Index.

## Test entry + data switch (2026-02-13)
- Added secondary page `pages/TestLab` for dev-only testing controls.
- Moved Cloud DB diagnose action from profile page to TestLab.
- Added persisted test-data toggle (`TestEnvStore`) with runtime cache + preferences.
- Cloud DB zone switches between `aoyou` and `aoyouTest` via `CloudDBService.getCurrentZoneName()`.
- Cloud Storage upload/delete paths use `test/` prefix in test mode.
- Privacy-policy-update popup: no app-side custom trigger found; likely SDK-level behavior from AccountKit login component.
