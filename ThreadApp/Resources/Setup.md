# Thread POC setup

Thread starts observing only after you choose Start Thread on first launch. You can reopen this guide from Getting started in the menu. Accessibility window access is optional; grant it only through the app's Allow access button and macOS's settings. Application observation works without it.

## Terminal

The Getting started window shows two zsh setup lines using your actual app location. Run them in an interactive zsh session. If you want future shells connected, add those lines to your own .zshrc. Thread never edits that file automatically. To disconnect, remove those lines and restart the shell. Command text, history and output are not captured.

## Chromium browsers

The POC extension must be installed separately from the source checkout. In Chrome, Chromium, Brave or Edge, open the browser's extensions page, enable developer mode and load the BrowserExtensions/Chromium directory as an unpacked extension. Keep private/incognito access disabled.

From the checkout, register the native host for the selected browser:

```sh
python3 scripts/install-browser-host.py --app '/actual/path/to/Thread.app' --browser chrome
```

Use chrome, chromium, brave or edge as appropriate. This explicit command writes that browser's native-messaging registration. BrowserExtensions/README.md describes the protocol and registration paths. Extension installation and live browser behavior still require verification; an installed app alone does not connect tabs.

## Safari

The embedded Safari extension needs a configured signing team and shared App Group. The ad-hoc POC build does not provide that entitlement. Do not expect live Safari context or exact-tab restoration before a signed setup is configured.

## Continue and correct

Press Option-Space for the switcher. Return continues selected work; arrows select and Escape closes. Details let you rename, archive, pin, move resources, merge or split Threads. Privacy exclusions and launch at login are in Settings. Existing history remains when exclusions change.

Restoration reports partial or unavailable capabilities. Terminal directories can reopen in Apple Terminal; no commands are replayed. No remote AI backend is configured in this build. Local observation, inference, history and restoration work offline.
