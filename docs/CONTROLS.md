# Handling Controls in a muOS Love2D App

Input on muOS is the least obvious part of app development. This doc explains
how button presses actually reach your app, why they sometimes don't, and the
dual-source pattern this project uses to stay responsive on every build.

---

## 1. How Input Reaches Your App

There are **two independent paths** from a physical button to your Lua code:

```
                      ┌────────────────────────────────────────────┐
 physical button ──►  │ Path A: gptokeyb (evdev grab)              │
                      │   button ──► synthetic KEYBOARD event      │
                      │   └─► love.keypressed("a"), ("left"), ...  │
                      ├────────────────────────────────────────────┤
                      │ Path B: SDL game controller                │
                      │   button ──► native GAMEPAD event          │
                      │   └─► love.gamepadpressed(js, "dpleft"),...│
                      └────────────────────────────────────────────┘
```

### Path A: gptokeyb (the classic pattern)

muOS ships `gptokeyb2` ("gamepad to keyboard"). Your launch script starts it
in the background before Love2D; it grabs the joystick device and injects
keyboard events according to a `.gptk` mapping file:

```sh
GPTOKEYB="$ROM_MOUNT/MUOS/emulator/gptokeyb/gptokeyb2.armhf"   # or gptokeyb2
"$GPTOKEYB" "love" -c "$APPDIR/yourapp.gptk" &
"$BINDIR/love" .
kill -9 $(pidof gptokeyb2) $(pidof gptokeyb2.armhf) 2>/dev/null
```

The first argument (`"love"`) is the process gptokeyb watches. The binary
name varies by build — check for `gptokeyb2.armhf` first, then `gptokeyb2`.

The `.gptk` mapping file:

```ini
dpup = up
dpdown = down
dpleft = left
dpright = right

a = a
b = b
x = x
y = y

l1 = l1
r1 = r1

start = start
select = select

# Map analog sticks to defined keys to prevent ghost inputs
leftanalogh = left_analog_left|left_analog_right
leftanalogv = left_analog_up|left_analog_down
```

Your Lua code then receives plain keyboard events:

```lua
function love.keypressed(key, scancode, isrepeat)
    if key == "left" then ... end     -- dpad left
    if key == "a" then ... end        -- A button
    if key == "start" then ... end    -- START button
end
```

### Path B: native SDL gamepad

Modern muOS (`SETUP_APP` in the launch script) exports
`SDL_GAMECONTROLLERCONFIG`, so SDL recognizes the built-in pad as a game
controller and Love2D delivers gamepad callbacks directly — no gptokeyb
involved:

```lua
function love.gamepadpressed(joystick, button)
    -- button: "dpleft", "dpright", "a", "b", "start", "back" (= SELECT), ...
end
```

Note: SELECT arrives as `"back"` in SDL naming.

## 2. Why You Must Listen to Both

We learned this the hard way — the app launched but was completely
uncontrollable, including the exit combo:

- If **gptokeyb isn't running** (wrong path for that build, died on a config
  it disliked, killed by a previous app), Path A is silent. An app that only
  implements `love.keypressed` hears *nothing*.
- If **SDL has no controller mapping** for the device (older builds, missing
  `SETUP_APP`), Path B is silent — the pad may not even register as a gamepad.
- When gptokeyb *is* running, it usually grabs the device exclusively, so
  Path B goes quiet and only keyboard events arrive. Which path is alive
  depends on muOS version and device — you can't know in advance.

**Conclusion: implement both, funnel them into shared actions, de-duplicate.**

## 3. The Dual-Source Pattern (used in this project)

All sources dispatch to a single `act()` with a short per-action cooldown, so
if both paths happen to deliver the same press you don't double-fire:

```lua
local Input = { held = {}, lastFire = {} }
local ACTION_COOLDOWN = 0.12

local function act(action, allowRepeat)
    local now = love.timer.getTime()
    if not allowRepeat then
        local last = Input.lastFire[action]
        if last and now - last < ACTION_COOLDOWN then return end
    end
    Input.lastFire[action] = now

    if action == "left" then ...
    elseif action == "launch" then ...
    elseif action == "quit" then love.event.quit() end
end

-- Path A: keyboard (gptokeyb on device, real keyboard on desktop)
function love.keypressed(key, _, isrepeat)
    if not isrepeat then Input.held[key] = true end
    if key == "left" then act("left", isrepeat)
    elseif key == "a" or key == "return" then
        if not isrepeat then act("launch") end
    end
end
function love.keyreleased(key) Input.held[key] = nil end

-- Path B: native gamepad
function love.gamepadpressed(js, button)
    Input.held["gp_" .. button] = true
    if button == "dpleft" then act("left")
    elseif button == "a" then act("launch") end
end
function love.gamepadreleased(js, button) Input.held["gp_" .. button] = nil end
```

### Button combos (e.g. hold L1+X+START to exit)

Track held state from both sources and check it in `love.update`. Remember
the SDL name for SELECT is `back`, and gptokeyb may deliver START as
"home"; check every alias a button can arrive under (this project's exit
combo accepts `pageup`/`l1`/`gp_leftshoulder` for L1, for example). For
destructive actions, prefer a hold-to-confirm timer over an instant
trigger so an accidental chord doesn't fire it.

### Auto-repeat for held directions

- Keyboard path: `love.keyboard.setKeyRepeat(true)` gives you repeats for
  free (`isrepeat` argument); pass that through as `allowRepeat`.
- Gamepad path: no built-in repeat — track the held direction and re-fire in
  `love.update` (this project: 0.35 s initial delay, then every 0.15 s).

### Raw joystick fallback

Pads that SDL doesn't recognize as gamepads (`js:isGamepad() == false`) still
send raw joystick events. Handle at least the hat (dpad):

```lua
function love.joystickhat(js, hat, dir)
    if js:isGamepad() then return end
    if dir == "l" then act("left")
    elseif dir == "r" then act("right")
    elseif dir == "c" then --[[ released ]] end
end
```

Raw button numbers vary per device, so log them rather than guessing.

## 4. Diagnosing Input Problems

Log the input landscape at startup — this line of output tells you almost
everything:

```lua
local joysticks = love.joystick.getJoysticks()
print("[Input] Joysticks detected: " .. #joysticks)
for i, js in ipairs(joysticks) do
    print(string.format("[Input] %d: %s (gamepad: %s, buttons: %d)",
        i, js:getName(), tostring(js:isGamepad()), js:getButtonCount()))
end
```

Then log every press with its source. Reading the log afterwards:

| Symptom in log | Meaning |
| --- | --- |
| Key events arrive (`keypressed left`) | gptokeyb path is alive |
| `gamepad: dpleft` lines | native SDL path is alive |
| `raw joystick button: N` lines | pad has no SDL mapping; extend the hat/button fallback |
| Joysticks detected: 0 and no key events | gptokeyb dead **and** no pad visible — check the launch script (was gptokeyb found? did `SETUP_APP` run?) |

Also make the launch script verify gptokeyb survived startup, and fall back
to launching it without a config (stock-app style) if it died:

```sh
"$GPTOKEYB" "love" -c "$APPDIR/yourapp.gptk" &
GPTOKEYB_PID="$!"
sleep 0.5 2>/dev/null || sleep 1
if ! kill -0 "$GPTOKEYB_PID" 2>/dev/null; then
    "$GPTOKEYB" "love" &
fi
```

## 5. Input Around External Processes

When you hand the screen to RetroArch/a game (see BUILDING-MUOS-APPS.md §6):

- **Kill gptokeyb first** — otherwise it keeps injecting keyboard events into
  the game on top of the game's own gamepad handling.
- **Debounce after returning**: when your app comes back, ignore input for
  ~0.4 s so the button press that closed the game doesn't leak into your UI.

```lua
ignoreInputUntil = love.timer.getTime() + 0.4
```

## 6. Desktop Testing Mappings

Keep a keyboard layer for local development — arrows for the dpad,
Enter/`a` for A, Escape for exit. Because Path A already speaks keyboard,
your device input code is mostly exercised for free on desktop; a USB
controller additionally exercises Path B.
