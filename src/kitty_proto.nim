import std/[os, strutils, base64]

type
  GraphicsProtocol* = enum
    gpNone,
    gpKitty,
    gpIterm

const kittyChunkSize = 4096

# Detects whether the active terminal emulator supports the Kitty graphics protocol.
proc supportsKittyGraphics*(): bool =
  const candidates = ["kitty", "wezterm", "ghostty", "konsole", "foot", "rio"]
  let termVars = [getEnv("TERM"), getEnv("TERM_PROGRAM"), getEnv("TERMINAL_EMULATOR")]
  for v in termVars:
    let low = v.toLowerAscii()
    for name in candidates:
      if low.contains(name): return true
  if getEnv("KITTY_WINDOW_ID").len > 0: return true
  if getEnv("WEZTERM_VERSION").len > 0 or getEnv("WEZTERM_EXECUTABLE").len > 0: return true
  if getEnv("GHOSTTY_RESOURCES_DIR").len > 0: return true
  if getEnv("KONSOLE_VERSION").len > 0 or getEnv("KONSOLE_DBUS_SESSION").len > 0: return true
  if getEnv("FOOT_TERMINAL").len > 0: return true
  false

# Detects whether the active terminal emulator supports the iTerm2 inline images protocol.
proc supportsItermGraphics*(): bool =
  let termProg = getEnv("TERM_PROGRAM").toLowerAscii()
  if termProg in ["iterm.app", "wezterm", "vscode", "tabby", "contour"]:
    return true
  if getEnv("LC_TERMINAL").toLowerAscii() in ["iterm2", "wezterm"]:
    return true
  if getEnv("VSCODE_INJECTION").len > 0:
    return true
  false

# Detects the highest priority terminal graphics protocol available in the current session.
proc detectGraphicsProtocol*(): GraphicsProtocol =
  if supportsKittyGraphics():
    return gpKitty
  if supportsItermGraphics():
    return gpIterm
  gpNone

# Transmits image payload bytes using Kitty graphics escape sequences.
proc displayKittyGraphics*(logoBytes: string; columns, rows: int) =
  if logoBytes.len == 0: return
  let encoded = encode(logoBytes)
  var offset = 0
  var first = true
  while offset < encoded.len:
    let chunkEnd = min(offset + kittyChunkSize, encoded.len)
    let chunk = encoded[offset ..< chunkEnd]
    var ctrl: seq[string] = @[]
    if first:
      ctrl.add("a=T")
      ctrl.add("f=100")
      ctrl.add("t=d")
      ctrl.add("q=2")
      ctrl.add("C=1")
      if columns > 0: ctrl.add("c=" & $columns)
      if rows > 0: ctrl.add("r=" & $rows)
    ctrl.add("m=" & (if chunkEnd < encoded.len: "1" else: "0"))

    var buf = "\x1b_G"
    if ctrl.len > 0:
      buf.add ctrl.join(",")
    if chunk.len > 0:
      buf.add ";"
      buf.add chunk
    buf.add "\x1b\\"
    stdout.write(buf)

    offset = chunkEnd
    first = false

# Transmits image payload bytes using iTerm2 OSC 1337 inline image escape sequences.
proc displayItermGraphics*(logoBytes: string; columns, rows: int) =
  if logoBytes.len == 0: return
  let encoded = encode(logoBytes)
  var buf = "\x1b]1337;File=inline=1"
  if columns > 0:
    buf.add ";width=" & $columns
  if rows > 0:
    buf.add ";height=" & $rows
  buf.add ";preserveAspectRatio=1:"
  buf.add encoded
  buf.add "\x07"
  stdout.write(buf)
