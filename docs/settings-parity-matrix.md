# Settings UI parity matrix

Status: baseline inventory for the settings UI migration.

This document records the current source contract. It is intentionally
separate from the future `Settings*` component design: the migration must
replace presentation components without changing the entries below.

## Page order and non-Config behavior

| Order | Page | Source | Non-Config behavior to preserve |
|---:|---|---|---|
| 0 | Quick | `modules/settings/QuickConfig.qml` | Random Konachan/osu! processes, wallpaper switch command, palette regeneration, theme mode command, config-path clipboard action, wallpaper preview and `OpacityMask`. |
| 1 | General | `modules/settings/GeneralConfig.qml` | Gemini translation process/restart, locale handling, battery/audio policy controls, `sed` update of `hyprlock.conf`. |
| 2 | Bar | `modules/settings/BarConfig.qml` | Bar position and utility-button toggles, tray/workspace/weather settings. |
| 3 | Background | `modules/settings/BackgroundConfig.qml` | Digital/cookie clock controls, weather widget controls, placement and parallax dependencies. |
| 4 | Interface | `modules/settings/InterfaceConfig.qml` | External crosshair editor URL, region selector actions, sidebar controls, font selectors and wallpaper-dialog preference. |
| 5 | Services | `modules/settings/ServicesConfig.qml` | Search prefixes, service intervals, weather/network settings and the intentionally commented updates section. |
| 6 | Screen Recording | `modules/settings/ScreenRecordingConfig.qml` | Recording scripts/IPC, audio-device selection, pause/resume/stop actions and output validation. |
| 7 | Advanced | `modules/settings/AdvancedConfig.qml` | Wallpaper color-generation settings and terminal/application theming. |
| 8 | Foundation | `modules/settings/FoundationConfig.qml` | Schema/status presentation and validated appearance/system controls. |
| 9 | About | `modules/settings/About.qml` | Distro and dotfiles links; every action opens its existing external URL. |

## Config.options inventory

The following paths are extracted from the current settings pages. A path may
appear in more than one page by design (for example, bar position,
transparency, recording save path, and ear protection). The migration must
preserve each occurrence, its transformation, and its enabled/visible
dependencies.

### Quick

- `appearance.fakeScreenRounding`
- `appearance.palette.type`
- `appearance.transparency.enable`
- `background.wallpaperPath`
- `bar.bottom`
- `bar.cornerStyle`
- `bar.vertical`
- `cheatsheet.superKey`
- `policies.weeb`

### General

- `audio.protection.enable`
- `audio.protection.maxAllowed`
- `audio.protection.maxAllowedIncrease`
- `battery.automaticSuspend`
- `battery.critical`
- `battery.full`
- `battery.low`
- `battery.suspend`
- `language.ui`
- `policies.ai`
- `policies.weeb`
- `sounds.battery`
- `sounds.pomodoro`
- `time.format`
- `time.secondPrecision`
- `workSafety.enable.clipboard`
- `workSafety.enable.wallpaper`

### Bar

- `bar.autoHide.enable`
- `bar.borderless`
- `bar.bottom`
- `bar.cornerStyle`
- `bar.indicators.notifications.showUnreadCount`
- `bar.tooltips.clickToShow`
- `bar.utilButtons.showColorPicker`
- `bar.utilButtons.showDarkModeToggle`
- `bar.utilButtons.showKeyboardToggle`
- `bar.utilButtons.showMicToggle`
- `bar.utilButtons.showPerformanceProfileToggle`
- `bar.utilButtons.showScreenRecord`
- `bar.utilButtons.showScreenSnip`
- `bar.vertical`
- `bar.weather.enable`
- `bar.workspaces.alwaysShowNumbers`
- `bar.workspaces.monochromeIcons`
- `bar.workspaces.numberMap`
- `bar.workspaces.showAppIcons`
- `bar.workspaces.shown`
- `bar.workspaces.showNumberDelay`
- `tray.invertPinnedItems`
- `tray.monochromeIcons`

### Background

- `background.parallax.enableSidebar`
- `background.parallax.enableWorkspace`
- `background.parallax.vertical`
- `background.parallax.workspaceZoom`
- `background.widgets.clock.cookie.aiStyling`
- `background.widgets.clock.cookie.constantlyRotate`
- `background.widgets.clock.cookie.dateStyle`
- `background.widgets.clock.cookie.dialNumberStyle`
- `background.widgets.clock.cookie.hourHandStyle`
- `background.widgets.clock.cookie.hourMarks`
- `background.widgets.clock.cookie.minuteHandStyle`
- `background.widgets.clock.cookie.secondHandStyle`
- `background.widgets.clock.cookie.sides`
- `background.widgets.clock.cookie.timeIndicators`
- `background.widgets.clock.cookie.useSineCookie`
- `background.widgets.clock.digital.adaptiveAlignment`
- `background.widgets.clock.digital.animateChange`
- `background.widgets.clock.digital.font.family`
- `background.widgets.clock.digital.font.roundness`
- `background.widgets.clock.digital.font.size`
- `background.widgets.clock.digital.font.weight`
- `background.widgets.clock.digital.font.width`
- `background.widgets.clock.digital.showDate`
- `background.widgets.clock.digital.vertical`
- `background.widgets.clock.enable`
- `background.widgets.clock.placementStrategy`
- `background.widgets.clock.quote.enable`
- `background.widgets.clock.quote.text`
- `background.widgets.clock.showOnlyWhenLocked`
- `background.widgets.clock.style`
- `background.widgets.clock.styleLocked`
- `background.widgets.weather.enable`
- `background.widgets.weather.placementStrategy`

### Interface

- `appearance.fonts.expressive`
- `appearance.fonts.iconNerd`
- `appearance.fonts.main`
- `appearance.fonts.monospace`
- `appearance.fonts.numbers`
- `appearance.fonts.reading`
- `appearance.fonts.title`
- `cheatsheet.fontSize.comment`
- `cheatsheet.fontSize.key`
- `cheatsheet.splitButtons`
- `cheatsheet.superKey`
- `cheatsheet.useFnSymbol`
- `cheatsheet.useMacSymbol`
- `cheatsheet.useMouseSymbol`
- `crosshair.code`
- `dock.enable`
- `dock.hoverToReveal`
- `dock.monochromeIcons`
- `dock.pinnedOnStartup`
- `lock.blur.enable`
- `lock.blur.extraZoom`
- `lock.centerClock`
- `lock.launchOnStartup`
- `lock.materialShapeChars`
- `lock.security.requirePasswordToPower`
- `lock.security.unlockKeyring`
- `lock.showLockedText`
- `lock.useHyprlock`
- `notifications.monitor.enable`
- `notifications.monitor.name`
- `notifications.timeout`
- `osd.timeout`
- `overlay.darkenScreen`
- `overlay.floatingImage.imageSource`
- `overlay.openingZoomAnimation`
- `overview.centerIcons`
- `overview.columns`
- `overview.enable`
- `overview.orderBottomUp`
- `overview.orderRightLeft`
- `overview.rows`
- `overview.scale`
- `regionSelector.circle.padding`
- `regionSelector.circle.strokeWidth`
- `regionSelector.rect.showAimLines`
- `regionSelector.targetRegions.content`
- `regionSelector.targetRegions.layers`
- `regionSelector.targetRegions.windows`
- `search.imageSearch.useCircleSelection`
- `sidebar.cornerOpen.bottom`
- `sidebar.cornerOpen.clickless`
- `sidebar.cornerOpen.clicklessCornerEnd`
- `sidebar.cornerOpen.clicklessCornerVerticalOffset`
- `sidebar.cornerOpen.cornerRegionHeight`
- `sidebar.cornerOpen.cornerRegionWidth`
- `sidebar.cornerOpen.enable`
- `sidebar.cornerOpen.valueScroll`
- `sidebar.cornerOpen.visualize`
- `sidebar.keepRightSidebarLoaded`
- `sidebar.quickSliders.enable`
- `sidebar.quickSliders.showBrightness`
- `sidebar.quickSliders.showMic`
- `sidebar.quickSliders.showVolume`
- `sidebar.quickToggles.android.columns`
- `sidebar.quickToggles.style`
- `sidebar.translator.enable`
- `wallpaperSelector.useSystemFileDialog`

### Services

- `ai.systemPrompt`
- `bar.weather.city`
- `bar.weather.enableGPS`
- `bar.weather.fetchInterval`
- `bar.weather.useUSCS`
- `musicRecognition.interval`
- `musicRecognition.timeout`
- `networking.userAgent`
- `resources.updateInterval`
- `screenRecord.savePath`
- `screenSnip.savePath`
- `search.engineBaseUrl`
- `search.prefix.action`
- `search.prefix.clipboard`
- `search.prefix.emojis`
- `search.prefix.math`
- `search.prefix.shellCommand`
- `search.prefix.webSearch`
- `search.sloppy`
- `updates.checkInterval`
- `updates.enableCheck`

### Screen Recording

- `screenRecord.audioSource`
- `screenRecord.barButtonAction`
- `screenRecord.fileFormat`
- `screenRecord.fps`
- `screenRecord.fullscreenUsesFocusedMonitor`
- `screenRecord.micDevice`
- `screenRecord.pixelFormat`
- `screenRecord.recordAudioByDefault`
- `screenRecord.savePath`
- `screenRecord.systemAudioDevice`

### Advanced

- `appearance.wallpaperTheming.enableAppsAndShell`
- `appearance.wallpaperTheming.enableQtApps`
- `appearance.wallpaperTheming.enableTerminal`
- `appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode`
- `appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold`
- `appearance.wallpaperTheming.terminalGenerationProps.harmony`
- `appearance.wallpaperTheming.terminalGenerationProps.termFgBoost`

### Foundation

- `appearance.transparency.enable`
- `appearance.transparency.backgroundTransparency`
- `audio.protection.enable`

## Migration acceptance rules

- Every current path above remains present after migration.
- Duplicate paths remain duplicated in their original page locations.
- No new `Config.options` path is introduced by the component layer.
- Component signals carry values to the page; pages retain the existing writes.
- The page order and all non-Config behavior in the first table remain unchanged.
- The matrix is not complete evidence by itself: each row still requires
  functional, visual, keyboard, and persistence verification.
