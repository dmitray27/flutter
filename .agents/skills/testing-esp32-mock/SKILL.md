---
name: testing-esp32-mock
description: How to run and test the radio_bridge_dual Flutter app end-to-end on a Linux VM against a mock ESP32 (HTTP /ping + WebSocket :81), without real ESP32/AD9851/PCM1808 hardware.
---

# Testing the Flutter radio chat against a mock ESP32

The app (`lib/screen_pro.dart`) talks to an ESP32 access point at `192.168.4.1`
(`GET /ping`, `ws://192.168.4.1:81`). On a VM there is no hardware, so mock the network side.

## 1. Build the Linux desktop app

The repo ships only `android/`. Linux build needs:

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev xclip wmctrl imagemagick
export PATH="/home/ubuntu/flutter_sdk/bin:$PATH"          # Flutter 3.22.3
cd <repo>
# the repo dir may be literally named "flutter", which breaks the default project name:
flutter create --platforms=linux --project-name radio_bridge_dual .
flutter build linux --debug
./build/linux/x64/debug/bundle/radio_bridge_dual > /tmp/app.log 2>&1 &
```

Do **not** commit the generated `linux/`, `test/` or the modified `.metadata`.
All `debugPrint` output (`✅ Успешно подключено`, `Отправлено имя: …`, `Отправлено через WS: …`)
goes to the redirected stdout — that log is the fastest way to see what the app did.

## 2. Fake the ESP32 network

```bash
sudo ip addr add 192.168.4.1/24 dev lo
sudo pip install aiohttp websockets      # the mock must run as root to bind :80
sudo python3 mock_esp32.py > /tmp/mock_stdout.log 2>&1 &
sudo chmod 666 /tmp/mock_esp32.log
```

`mock_esp32.py` (next to this SKILL.md) implements the firmware contract from
`wifi_link.c`: `GET /ping`→`pong`, WS `:81`, `setName:<name>` logged,
`msg:<name>:<text>` split on the **first** `:` after `msg:` and rebroadcast to all
clients as `<name>:<text>`, plus `POST /inject` to push an arbitrary raw frame
(`Remote:…`, `System:…`, `ping`) to all clients. Every RX frame is logged to
`/tmp/mock_esp32.log` — tail it in a visible terminal so the recording shows frame formats.

Note `/tmp` may be wiped mid-session on these VMs; keep screenshots under `~/screenshots`,
not `/tmp`.

## 3. `network_info_plus` does not work on this VM

`getWifiIP()` throws `org.freedesktop.DBus.Error.ServiceUnknown: org.freedesktop.NetworkManager`.
Adding the IP to `lo` does **not** help — the plugin queries NetworkManager, not interfaces.
Without a fix the app is stuck on "Подключитесь к WiFi ESP32".

Workaround (working-copy only, never commit) in `_checkConnection`:

```dart
String deviceIp = '';
try { deviceIp = await networkInfo.getWifiIP() ?? ''; } catch (e) { debugPrint('TEST-ONLY: $e'); }
if (deviceIp.isEmpty) deviceIp = '192.168.4.2';   // TEST-ONLY
```

Always state in the report that this gate was bypassed and that the
"wrong network" branch was therefore not exercised. Revert with
`git checkout -- lib/screen_pro.dart .metadata` when done.

## 4. GUI interaction gotchas

- `xdotool type` (the `type` action) does **not** produce Cyrillic in the Flutter app.
  Put the text in the clipboard and paste it instead:
  `printf '%s' 'привет' | DISPLAY=:0 xclip -selection clipboard`, then click the field and `ctrl+v`.
- SnackBars last only 2 s — a screenshot taken through the computer-use tool usually misses them.
  Capture from the shell with controlled timing:
  `curl ... /inject && sleep 0.7 && DISPLAY=:0 import -window root ~/screenshots/snack.png`.
- The window is a fixed 400x800 with a hidden title bar (`window_manager`), so it cannot be
  maximized; place the log terminal beside it with `wmctrl -r Konsole -e 0,600,90,900,900`.
- `pkill -f radio_bridge_dual` from the exec tool kills the calling shell too (the pattern matches
  its own `bash -c` command line). Use a bracketed pattern: `pkill -f 'radio_bridge_dua[l]'`.

## 5. Known fragile area: dialog TextEditingController lifetime

Renaming via the "Изменить имя" dialog used to crash the app to the red Flutter error screen:
`A TextEditingController was used after being disposed` → `Failed assertion: '_dependents.isEmpty'`.
Cause: `.whenComplete(nameController.dispose)` in `_showChangeNameDialog` freed a locally created
controller while the dialog's close animation was still listening to it. Fixed in `c807ccb` by
hoisting the controller into `_ChatScreenState` and disposing it once in `State.dispose()`.

When testing any dialog that owns a controller, always run these two checks, because the crash is
**intermittent without a concurrent overlay but 100% reproducible with one**:

1. Open the dialog, then push a `System:` frame from the mock so a SnackBar is on screen, then
   press Save → must not show the red error screen.
2. Open/Save repeatedly (5+ times) and use Отмена at least once; on each reopen assert the field is
   pre-filled with the CURRENT value (a reused State-level controller must be refilled) and that
   Отмена sends no `setName:` frame.

Verify with the log, not just pixels:
`grep -c "used after being disposed\|Failed assertion\|Flutter Error" /tmp/app.log` must be 0.

## 6. Dark theme cannot be switched from the desktop on this VM

`lib/main.dart` uses `themeMode: ThemeMode.system`, but there is no session D-Bus here, so
Flutter never sees the GSettings value. Installing `gsettings-desktop-schemas` and setting
`org.gnome.desktop.interface color-scheme='prefer-dark'` (also `gtk-theme='Adwaita-dark'`,
`GTK_THEME=Adwaita:dark`) had no effect — the app rendered light on every relaunch.

Workaround (working-copy only, never commit) — make the theme env-driven so ONE build covers both
runs instead of rebuilding twice:

```dart
themeMode: Platform.environment['FORCE_DARK'] == '1' ? ThemeMode.dark : ThemeMode.system, // TEST-ONLY
```

Then launch normally for light and with `FORCE_DARK=1 ./…/radio_bridge_dual` for dark.
Always report that `ThemeMode.system` auto-detection itself stays unverified.
For readability evidence, `zoom` into the bubble area rather than posting the full 1024x768 shot.

## 7. Testing autoscroll and the message input

- The list is `reverse: true`, so "bottom" is offset 0 and `_scrollToBottom()` calls `animateTo(0)`
  over 200 ms. A screenshot taken immediately after sending can catch the animation mid-flight and
  look like autoscroll failed — always take a second screenshot ~1 s later before judging.
- To build history fast with varying item heights, inject from the mock in a shell loop, mixing
  short frames, a very long single-line frame and frames containing real newlines
  (`curl --data-binary $'a\nb\nc'`); newlines survive the app's parsing and give multi-line bubbles.
- Enter sends (`textInputAction: send` + `maxLines: 4`), so `type` with a trailing `\n` both types and
  sends. Latin text can be typed directly; Cyrillic must be pasted (see §4). Typing right after a
  send without clicking the field is the actual proof that focus is retained.
- Disabled-input check: the field stays mounted with `enabled: isConnected`. Kill the mock, wait ~8 s
  for the 5 s poll to fail, then assert the hint text `Нет связи с ESP32`, that clicking + typing
  produces no characters, and that the send icon is greyed.

## 8. Mock modes for delivery-status / firmware-semantics testing

`mock_esp32.py` (copy kept next to this skill) exposes `POST /mode` with space-separated
`key=value` pairs, so you can drive the app's delivery-status state machine deterministically
without editing the app:

- `echodelay=<seconds>` — delay the echo so the `sending` (clock icon) state is actually
  screenshot-able; with an instant echo the pending state can be too short to catch.
- `dropecho=<substring>` — suppress the echo only for frames containing the substring; this is how
  you prove per-message statuses do not get mixed (send 3 messages, only the matching one fails).
- `noecho=1` — never echo; combine with killing the mock within the timeout window to exercise the
  "connection dropped" failure path instead of the timeout path.
- `queuefull=1` — reply `System:Очередь передачи занята, сообщение не отправлено` instead of
  echoing (firmware TX-queue-full branch).
- `maxframe=<bytes>` — ignore longer frames with `System:Сообщение слишком длинное` and keep the
  socket open. The real firmware limit is 1024 bytes, but the app caps input at 300 chars
  (~620 bytes for Cyrillic), so temporarily lower the mock limit (e.g. 200) to reach this branch,
  then reset to 1024.

Always verify a new mock branch with a raw WS probe (`mock_probe.py`) before blaming the app.
Reset all modes at the start of each test block; a leftover `dropecho`/`queuefull` silently makes
later messages fail.

Status icons are 12 px — `zoom` into the bubble's bottom-right corner; clock = `Icons.schedule`,
check = `Icons.done`, red = `Icons.error_outline` with tooltip `ESP32 не подтвердил приём`
(hover to capture it). The echo timeout is 6 s, so wait > 6 s before asserting `failed`.

## 9. Long runs get interrupted — record in segments

A full A–G run can exceed quota or survive a VM restart. Keep each recording focused on a block of
checks and stop it (which finalizes the mp4) before starting the next one; if a recording is cut
off mid-run, the segments still exist as `<id>-edited-00N.mp4` and can be concatenated with
`ffmpeg -f concat -safe 0 -i list.txt -c copy out.mp4`. After a VM restart re-add
`sudo ip addr add 192.168.4.1/24 dev lo`, delete a root-owned `/tmp/mock_esp32.log`, and relaunch
the already-built bundle (no rebuild needed if the commit is unchanged).

## 10. Comparing two variant branches in one run

When two branches implement rival variants of the same feature (e.g. with vs. without delivery
status), test them back to back in one recording and carry the TEST-ONLY patches across the switch:

```bash
git stash push -m 'test-only patches' lib/main.dart lib/screen_pro.dart
git checkout <other-branch>
git stash pop           # auto-merges cleanly if the patched hunks are untouched
flutter build linux --debug
```

The `getWifiIP()` fallback hunk sits in `_checkConnection()` and exists on every branch, so the pop
merges without conflicts. Verify with `git diff --stat` (expect only the two patched files) before
building, and after the run restore the original branch the same way so the user's working tree is
untouched.

The strongest evidence for a "feature removed" variant is a negative assertion captured visually:
zoom into the bubble corner and show that the timestamp is alone, then reproduce the exact scenario
that would trigger the removed behaviour (send with `noecho=1`, kill the mock, wait longer than the
other variant's 6 s timeout) and show that nothing appears. Waiting less than that timeout proves
nothing.

Launching the bundle with `nohup ... &` in the same `exec` call as a following `sleep` sometimes
returns exit code -1 and the app never starts; launch it in its own command, then poll
`pgrep -c -f 'radio_bridge_dua[l]'` in a separate call.

## Devin Secrets Needed

None — everything runs locally against the mock.
