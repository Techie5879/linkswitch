# Tahoe Menu Bar Identity Reset

## Problem shape

On macOS Tahoe, LinkSwitch can get stuck in a bad menu-bar state where:

- the app launches normally
- `AppDelegate.installStatusItem()` runs successfully
- the status item logs as installed
- the icon does not appear in the visible menu bar
- the app can still remain listed under `System Settings > Menu Bar > Allow in the Menu Bar` after uninstall

During debugging, the same built app under a fresh bundle ID showed up immediately, while the original `dev.helios.LinkSwitch` identity stayed hidden. That points to Tahoe keeping stale menu-bar tracking state outside the app bundle itself.

## What did not fix it

These cleanup steps were not sufficient on their own:

- reinstalling `LinkSwitch Dev.app`
- unregistering app paths from Launch Services
- deleting the app's `UserDefaults` domain
- deleting `com.apple.controlcenter.plist`
- deleting `com.apple.systemuiserver.plist`
- deleting the ByHost `com.apple.controlcenter*` plists
- `lsregister -delete` followed by reboot

## What did fix it

The successful reset was:

1. uninstall all installed LinkSwitch test/dev app bundles
2. delete Tahoe's shared Control Center plist
3. log out and log back in
4. reinstall the normal `LinkSwitch Dev.app`

After that reset, the original `dev.helios.LinkSwitch` identity returned to a normal visible menu-bar position.

## Reset commands

Back up and remove the shared Control Center plist with:

```bash
mkdir -p /tmp/linkswitch-menubar-backup

cp "$HOME/Library/GroupContainersAlias/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist" /tmp/linkswitch-menubar-backup/alias-group.com.apple.controlcenter.plist 2>/dev/null || true
cp "$HOME/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist" /tmp/linkswitch-menubar-backup/group.com.apple.controlcenter.plist 2>/dev/null || true

rm -f "$HOME/Library/GroupContainersAlias/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"
rm -f "$HOME/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"
```

Important details:

- Use `$HOME`, not quoted `~`. `~` does not expand inside quotes.
- If Terminal reports `Operation not permitted`, give Terminal Full Disk Access first.
- This reset clears Tahoe's shared menu-bar tracking state, so ghost entries in `Allow in the Menu Bar` should disappear after logout/login.

## After the reset

After deleting the shared plist:

1. log out of macOS
2. log back in
3. confirm ghost LinkSwitch entries are gone from `System Settings > Menu Bar`
4. reinstall the normal dev app with `./scripts/install-dev.sh`

Expected result after reinstall:

- LinkSwitch appears in the visible menu bar again
- `System Settings > Menu Bar` shows only the current installed app identity

## Why this matters

This incident strongly suggests Tahoe keeps third-party menu-bar app tracking in a shared Control Center store outside the app bundle and outside the normal per-app defaults domain. Reinstalling the same bundle ID is not enough if that shared state is stale.
