-- Vitro Launcher - Love2D configuration
-- Target: muOS handhelds (640x480, 720x480) - responsive

function love.conf(t)
    -- conf.lua runs before love modules load; use LuaJIT to detect the OS.
    -- Device (muOS/Linux) needs conservative window flags: MSAA or resizable
    -- can make SDL window creation fail on the Mali/KMSDRM stack.
    local onDesktop = jit and (jit.os == "OSX" or jit.os == "Windows")

    t.identity = "VitroLauncher"
    t.version = "11.5"
    t.console = false

    t.window.title = "Vitro Launcher"
    t.window.width = 640
    t.window.height = 480
    t.window.fullscreen = false
    t.window.resizable = onDesktop -- resizable only for local testing
    t.window.minwidth = 320
    t.window.minheight = 240
    -- GL_NOVSYNC=1: automated local testing (vsync blocks forever if the
    -- display is asleep, which stalls timed test hooks)
    t.window.vsync = os.getenv("GL_NOVSYNC") and 0 or 1
    t.window.msaa = 0

    t.modules.audio = true
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = true -- required for gptokeyb
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = false
    t.modules.physics = false
    t.modules.sound = true
    t.modules.system = true
    t.modules.thread = false
    t.modules.timer = true
    t.modules.touch = false
    t.modules.video = false
    t.modules.window = true
end
