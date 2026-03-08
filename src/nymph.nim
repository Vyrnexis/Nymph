import std/[os, terminal, math, strutils, strformat, random, sets, posix, json]
import kitty_proto, nymph_settings

type
  # Holds raw PNG bytes and dimensions so we can size the Kitty placement.
  LogoData = object
    bytes: string
    width: int
    height: int

  ThemePalette = object
    rosewater: string
    pink: string
    mauve: string
    maroon: string
    yellow: string
    green: string
    sky: string
    lavender: string
    bold: string
    reset: string

  IconPack = object
    os: string
    kernel: string
    pkgs: string
    desktop: string
    shell: string
    uptime: string
    memory: string
    swatches: seq[string]

  PackageSource = object
    name: string
    count: int

  PackageSummary = object
    total: int
    sources: seq[PackageSource]

  ModuleKind = enum
    mkOS,
    mkKernel,
    mkDesktop,
    mkPackages,
    mkShell,
    mkUptime,
    mkMemory,
    mkColours

  CliOptions = object
    logo: string
    theme: string
    iconPack: string
    layout: string
    modules: seq[string]
    noColor: bool
    jsonOutput: bool
    doctor: bool
    listThemes: bool
    listIconPacks: bool
    help: bool

  SystemSnapshot = object
    os: string
    kernel: string
    desktop: string
    shell: string
    uptime: string
    memory: string
    packages: PackageSummary

  StatEntry = object
    col: int
    row: int
    text: string

const
  DefaultLogoName = "generic"
  sourceLogoDir = parentDir(currentSourcePath()) / "logos"
  projectLogoDir = parentDir(parentDir(currentSourcePath())) / "logos"
  AsciiFallbackLogo = """  
      .---.   
      /     \    
      \.@-@./    
      /`\_/`\    
     //  _  \\    
    | \     )|_   
   /`\_`>  <_/ \_  
   \__/''---''\__/ 

""" & "\n"

  NerdSwatchIcons = ["", "", "", "", "󰯉", "", "", "󰞦", "󰄊", "󱖿", "", "󰌽", "", "", "", "", "", "", "", "", "", "", "", "󰢚", "󰆚", "󰩃", "󱔐", "󱕘", "󱜿", "󰻀", "󰳆", "󱗂"]
  AsciiSwatchIcons = ["[]", "##", "++", "==", "**", "@@"]

  osReleasePath = "/etc/os-release"
  versionFile = "/proc/version"
  uptimeFile = "/proc/uptime"
  meminfoPath = "/proc/meminfo"
  secsPerDay = 24 * 60 * 60
  gibDivisor = 1024.0 * 1024.0
  mibDivisor = 1024

var appConfig: RuntimeConfig = defaultConfig()
var disableColor = false
var metricsCached = false
var cachedMetrics: tuple[cellWidth, cellHeight: float]
var activeThemeName = "catppuccin"
var activeLayoutName = "full"
var activeIconPackName = "nerd"
var activePalette = ThemePalette(
  rosewater: "\x1b[38;2;245;224;220m",
  pink: "\x1b[38;2;245;194;231m",
  mauve: "\x1b[38;2;203;166;247m",
  maroon: "\x1b[38;2;235;160;172m",
  yellow: "\x1b[38;2;249;226;175m",
  green: "\x1b[38;2;166;227;161m",
  sky: "\x1b[38;2;137;220;235m",
  lavender: "\x1b[38;2;180;190;254m",
  bold: "\x1b[1m",
  reset: "\x1b[0m"
)
var activeIcons = IconPack(
  os: "",
  kernel: "",
  pkgs: "󰏖",
  desktop: "󰇄",
  shell: "",
  uptime: "",
  memory: "󰍛",
  swatches: @NerdSwatchIcons
)

proc parseCsv(raw: string): seq[string] =
  for item in raw.split(','):
    let value = item.strip().toLowerAscii()
    if value.len > 0:
      result.add value


proc moduleName(moduleKind: ModuleKind): string =
  case moduleKind
  of mkOS: "os"
  of mkKernel: "kernel"
  of mkDesktop: "desktop"
  of mkPackages: "packages"
  of mkShell: "shell"
  of mkUptime: "uptime"
  of mkMemory: "memory"
  of mkColours: "colours"


proc parseModule(name: string; moduleKind: var ModuleKind): bool =
  case name.strip().toLowerAscii()
  of "os":
    moduleKind = mkOS
    true
  of "kernel":
    moduleKind = mkKernel
    true
  of "desktop", "de", "wm", "dewm":
    moduleKind = mkDesktop
    true
  of "packages", "package", "pkgs":
    moduleKind = mkPackages
    true
  of "shell":
    moduleKind = mkShell
    true
  of "uptime":
    moduleKind = mkUptime
    true
  of "memory", "mem":
    moduleKind = mkMemory
    true
  of "colours", "colors", "palette":
    moduleKind = mkColours
    true
  else:
    false


proc normalizeLayoutName(name: string): string =
  case name.strip().toLowerAscii()
  of "compact": "compact"
  of "minimal": "minimal"
  else: "full"


proc defaultModules(layout: string): seq[ModuleKind] =
  case normalizeLayoutName(layout)
  of "minimal":
    @[mkOS, mkKernel, mkPackages, mkMemory]
  of "compact":
    @[mkOS, mkKernel, mkDesktop, mkPackages, mkMemory, mkUptime]
  else:
    @[mkOS, mkKernel, mkDesktop, mkPackages, mkShell, mkUptime, mkMemory, mkColours]


proc resolveModules(layout: string; names: seq[string]): seq[ModuleKind] =
  if names.len == 0:
    return defaultModules(layout)

  var seen = initHashSet[ModuleKind]()
  for raw in names:
    var moduleKind: ModuleKind
    if parseModule(raw, moduleKind) and not seen.contains(moduleKind):
      seen.incl(moduleKind)
      result.add moduleKind

  if result.len == 0:
    return defaultModules(layout)


proc modulesAsNames(modules: seq[ModuleKind]): seq[string] =
  for moduleKind in modules:
    result.add moduleName(moduleKind)


proc normalizeThemeName(name: string): string =
  case name.strip().toLowerAscii()
  of "nord": "nord"
  of "gruvbox": "gruvbox"
  of "plain": "plain"
  else: "catppuccin"


proc resolveTheme(name: string): ThemePalette =
  case normalizeThemeName(name)
  of "nord":
    ThemePalette(
      rosewater: "\x1b[38;2;216;222;233m",
      pink: "\x1b[38;2;180;142;173m",
      mauve: "\x1b[38;2;143;188;187m",
      maroon: "\x1b[38;2;191;97;106m",
      yellow: "\x1b[38;2;235;203;139m",
      green: "\x1b[38;2;163;190;140m",
      sky: "\x1b[38;2;136;192;208m",
      lavender: "\x1b[38;2;129;161;193m",
      bold: "\x1b[1m",
      reset: "\x1b[0m"
    )
  of "gruvbox":
    ThemePalette(
      rosewater: "\x1b[38;2;251;241;199m",
      pink: "\x1b[38;2;211;134;155m",
      mauve: "\x1b[38;2;184;187;38m",
      maroon: "\x1b[38;2;251;73;52m",
      yellow: "\x1b[38;2;250;189;47m",
      green: "\x1b[38;2;184;187;38m",
      sky: "\x1b[38;2;131;165;152m",
      lavender: "\x1b[38;2;142;192;124m",
      bold: "\x1b[1m",
      reset: "\x1b[0m"
    )
  of "plain":
    ThemePalette(
      rosewater: "",
      pink: "",
      mauve: "",
      maroon: "",
      yellow: "",
      green: "",
      sky: "",
      lavender: "",
      bold: "",
      reset: ""
    )
  else:
    ThemePalette(
      rosewater: "\x1b[38;2;245;224;220m",
      pink: "\x1b[38;2;245;194;231m",
      mauve: "\x1b[38;2;203;166;247m",
      maroon: "\x1b[38;2;235;160;172m",
      yellow: "\x1b[38;2;249;226;175m",
      green: "\x1b[38;2;166;227;161m",
      sky: "\x1b[38;2;137;220;235m",
      lavender: "\x1b[38;2;180;190;254m",
      bold: "\x1b[1m",
      reset: "\x1b[0m"
    )


proc normalizeIconPackName(name: string): string =
  case name.strip().toLowerAscii()
  of "ascii": "ascii"
  of "mono": "mono"
  else: "nerd"


proc resolveIconPack(name: string): IconPack =
  case normalizeIconPackName(name)
  of "ascii":
    IconPack(
      os: "OS",
      kernel: "KR",
      pkgs: "PK",
      desktop: "DE",
      shell: "SH",
      uptime: "UP",
      memory: "MM",
      swatches: @AsciiSwatchIcons
    )
  of "mono":
    IconPack(
      os: "#",
      kernel: "#",
      pkgs: "#",
      desktop: "#",
      shell: "#",
      uptime: "#",
      memory: "#",
      swatches: @["##", "##", "##"]
    )
  else:
    IconPack(
      os: "",
      kernel: "",
      pkgs: "󰏖",
      desktop: "󰇄",
      shell: "",
      uptime: "",
      memory: "󰍛",
      swatches: @NerdSwatchIcons
    )


proc getLogoSearchDirs(): seq[string] =
  ## Assemble all directories we search for logos (env/app/source/project).
  let envDir = getEnv("NYMPH_LOGO_DIR")
  let appDir = getAppDir()
  var seen = initHashSet[string]()

  for dir in [sourceLogoDir, projectLogoDir]:
    let norm = normalizeDir(dir)
    if norm.len > 0 and not seen.contains(norm):
      seen.incl(norm)
      result.add norm

  if appConfig.configLogoDir.len > 0:
    let norm = normalizeDir(appConfig.configLogoDir)
    if norm.len > 0 and not seen.contains(norm):
      seen.incl(norm)
      result.add norm

  if envDir.len > 0:
    let norm = normalizeDir(envDir)
    if norm.len > 0 and not seen.contains(norm):
      seen.incl(norm)
      result.add norm

  if appDir.len > 0:
    let dir = normalizeDir(appDir / "logos")
    if dir.len > 0 and not seen.contains(dir):
      seen.incl(dir)
      result.add dir
    let sharedDir = normalizeDir(appDir / ".." / "share" / "nymph" / "logos")
    if sharedDir.len > 0 and not seen.contains(sharedDir):
      seen.incl(sharedDir)
      result.add sharedDir


proc locateLogoFile(name, ext: string): string =
  ## Return the first logo file that matches the provided name/extension.
  let fileName = name.toLowerAscii() & ext
  for dir in getLogoSearchDirs():
    let path = dir / fileName
    if fileExists(path):
      return path
  ""


proc parsePngDims(data: string): (int, int) =
  ## Read the PNG IHDR chunk to extract width/height.
  if data.len < 24:
    return (0, 0)
  if not data.startsWith("\x89PNG\x0d\x0a\x1a\x0a"):
    return (0, 0)
  let w = (ord(data[16]) shl 24) or (ord(data[17]) shl 16) or (ord(data[18]) shl 8) or ord(data[19])
  let h = (ord(data[20]) shl 24) or (ord(data[21]) shl 16) or (ord(data[22]) shl 8) or ord(data[23])
  (w, h)


proc loadLogo(name: string): LogoData =
  ## Load PNG bytes and dimensions for the given logo name.
  let path = locateLogoFile(name, ".png")
  if path.len == 0:
    return
  try:
    let raw = readFile(path)
    if raw.len == 0:
      return
    let (w, h) = parsePngDims(raw)
    if w <= 0 or h <= 0:
      return
    result.bytes = raw
    result.width = w
    result.height = h
  except IOError:
    discard


proc loadLogoFromPath(path: string): LogoData =
  ## Load a PNG from an explicit path.
  let norm = normalizeDir(path)
  if norm.len == 0 or not fileExists(norm):
    return
  try:
    let raw = readFile(norm)
    if raw.len == 0:
      return
    let (w, h) = parsePngDims(raw)
    if w <= 0 or h <= 0:
      return
    result.bytes = raw
    result.width = w
    result.height = h
  except IOError:
    discard


when defined(posix):
  type
    TermWinSize = object
      ws_row: cushort
      ws_col: cushort
      ws_xpixel: cushort
      ws_ypixel: cushort

  const ioctlWinSize = culong(0x5413)


proc getWindowPixels(): tuple[width, height: int] =
  ## Query the terminal window size in pixels (falls back to 0s).
  when defined(posix):
    var ws: TermWinSize
    if ioctl(STDOUT_FILENO, ioctlWinSize, addr ws) == 0:
      return (int(ws.ws_xpixel), int(ws.ws_ypixel))
  (0, 0)


proc getCellMetrics(): tuple[cellWidth, cellHeight: float] =
  ## Derive approximate cell width/height in pixels from window metrics (cached).
  if metricsCached:
    return cachedMetrics

  let cols = terminalWidth()
  let rows = terminalHeight()
  let winPixels = getWindowPixels()
  var cellWidth = 8.0
  var cellHeight = 16.0
  if winPixels.width > 0 and cols > 0:
    cellWidth = winPixels.width.float / cols.float
  if winPixels.height > 0 and rows > 0:
    cellHeight = winPixels.height.float / rows.float

  cachedMetrics = (cellWidth: cellWidth, cellHeight: cellHeight)
  metricsCached = true
  cachedMetrics


proc collectAvailableLogos(): seq[string] =
  ## Enumerate unique logo names detected across all search paths.
  var seen = initHashSet[string]()
  for dir in getLogoSearchDirs():
    try:
      for kind, path in walkDir(dir):
        if kind != pcFile:
          continue
        let ext = path.splitFile.ext.toLowerAscii()
        if ext == ".png":
          let name = path.splitFile.name.toLowerAscii()
          if not seen.contains(name):
            seen.incl(name)
            result.add name
    except OSError:
      discard


proc sanitizeLogoName(name: string): string =
  ## Strip non-alphanumeric characters before matching names.
  for ch in name.toLowerAscii():
    if ch.isAlphaNumeric:
      result.add(ch)


proc findBestLogoMatch(candidates: seq[string]): string =
  ## Pick the first candidate that matches an available logo.
  let available = collectAvailableLogos()
  if available.len == 0:
    return ""

  proc tryMatch(value: string): string =
    let sanitized = sanitizeLogoName(value)
    if sanitized.len == 0:
      return ""
    for avail in available:
      if avail == sanitized or avail.contains(sanitized) or sanitized.contains(avail):
        return avail
    ""

  for cand in candidates:
    let matched = tryMatch(cand)
    if matched.len > 0:
      return matched

  let genericMatch = tryMatch("generic")
  if genericMatch.len > 0:
    return genericMatch

  let defaultMatch = tryMatch(DefaultLogoName)
  if defaultMatch.len > 0:
    return defaultMatch

  available[0]


proc parseCliOptions(): CliOptions =
  ## Parse command-line flags.
  let params = commandLineParams()

  proc pullNext(idx: var int): string =
    if idx + 1 < params.len:
      inc idx
      return params[idx]
    ""

  var i = 0
  while i < params.len:
    let param = params[i]
    if param.startsWith("--logo=") or param.startsWith("-logo="):
      result.logo = param.split('=', 1)[1]
    elif param == "--logo" or param == "-logo":
      result.logo = pullNext(i)
    elif param == "--no-color" or param == "--no-colors":
      result.noColor = true
    elif param == "--json":
      result.jsonOutput = true
    elif param == "--doctor":
      result.doctor = true
    elif param == "--list-themes":
      result.listThemes = true
    elif param == "--list-icon-packs":
      result.listIconPacks = true
    elif param == "--help" or param == "-h":
      result.help = true
    elif param.startsWith("--theme="):
      result.theme = param.split('=', 1)[1]
    elif param == "--theme":
      result.theme = pullNext(i)
    elif param.startsWith("--icon-pack=") or param.startsWith("--iconpack="):
      result.iconPack = param.split('=', 1)[1]
    elif param == "--icon-pack" or param == "--iconpack":
      result.iconPack = pullNext(i)
    elif param.startsWith("--layout="):
      result.layout = param.split('=', 1)[1]
    elif param == "--layout":
      result.layout = pullNext(i)
    elif param.startsWith("--modules="):
      result.modules = parseCsv(param.split('=', 1)[1])
    elif param == "--modules":
      result.modules = parseCsv(pullNext(i))
    inc i


proc detectLogoName(cliLogo: string): string =
  ## Build a list of candidate names from CLI, env vars, and os-release.
  var candidates: seq[string] = @[]

  if cliLogo.len > 0:
    candidates.add cliLogo

  let envLogo = getEnv("NYMPH_LOGO")
  if envLogo.len > 0:
    candidates.add envLogo

  if fileExists(osReleasePath):
    var idValue = ""
    var idLikeValues: seq[string] = @[]
    var pretty = ""
    var nameValue = ""
    for line in lines(osReleasePath):
      if line.startsWith("ID="):
        idValue = line.split('=', 1)[1].strip(chars = {'"', '\''})
      elif line.startsWith("ID_LIKE="):
        let values = line.split('=', 1)[1].strip(chars = {'"', '\''}).splitWhitespace()
        for v in values:
          idLikeValues.add v
      elif line.startsWith("PRETTY_NAME="):
        pretty = line.split('=', 1)[1].strip(chars = {'"', '\''})
      elif line.startsWith("NAME="):
        nameValue = line.split('=', 1)[1].strip(chars = {'"', '\''})

    if idValue.len > 0:
      candidates.add idValue
    for v in idLikeValues:
      candidates.add v
    if nameValue.len > 0:
      candidates.add nameValue
    if pretty.len > 0:
      candidates.add pretty

  candidates.add DefaultLogoName
  findBestLogoMatch(candidates)


proc getOS(): string {.inline.} =
  ## Return PRETTY_NAME from /etc/os-release or fall back to NAME.
  var distroname = ""
  if fileExists(osReleasePath):
    for line in lines(osReleasePath):
      if line.startsWith("PRETTY_NAME="):
        return line.split('=', 1)[1].strip(chars = {'"', '\''})
      elif line.startsWith("NAME="):
        distroname = line.split('=', 1)[1].strip(chars = {'"', '\''})

  if distroname.len == 0:
    return "Unknown Linux Distribution"
  distroname


proc getKernel(): string {.inline.} =
  ## Read kernel version from /proc/version (fallback to last token).
  if fileExists(versionFile):
    let tokens = readFile(versionFile).splitWhitespace()
    if tokens.len >= 3:
      return tokens[2]
    elif tokens.len > 0:
      return tokens[^1]
  "Unknown Kernel Version"


proc countDirs(path: string): int =
  if not dirExists(path):
    return 0
  try:
    for kind, _ in walkDir(path):
      if kind == pcDir:
        inc result
  except OSError:
    discard


proc countDpkgInstalled(path: string): int =
  if not fileExists(path):
    return 0
  var seenPkg = false
  try:
    for line in lines(path):
      if line.startsWith("Package:"):
        seenPkg = true
      elif line.startsWith("Status:") and seenPkg:
        if "install ok installed" in line:
          inc result
        seenPkg = false
      elif line.len == 0:
        seenPkg = false
  except IOError:
    return 0


proc countApkInstalled(paths: openArray[string]): int =
  for path in paths:
    if not fileExists(path):
      continue
    var count = 0
    try:
      for line in lines(path):
        if line.startsWith("P:"):
          inc count
    except IOError:
      count = 0
    if count > 0:
      return count
  0


proc countSnapInstalled(path: string): int =
  if not dirExists(path):
    return 0
  try:
    for kind, item in walkDir(path):
      if kind == pcFile and item.endsWith(".snap"):
        inc result
  except OSError:
    discard


proc addPackageSource(summary: var PackageSummary; name: string; count: int) =
  if count <= 0:
    return
  summary.sources.add PackageSource(name: name, count: count)
  summary.total += count


proc detectPackageSummary(): PackageSummary =
  addPackageSource(result, "pacman", countDirs("/var/lib/pacman/local"))
  addPackageSource(result, "dpkg", countDpkgInstalled("/var/lib/dpkg/status"))
  addPackageSource(result, "apk", countApkInstalled(["/lib/apk/db/installed", "/var/lib/apk/db/installed"]))

  let flatpakSystem = countDirs("/var/lib/flatpak/app")
  let flatpakUser = countDirs(normalizeDir(getHomeDir() / ".local" / "share" / "flatpak" / "app"))
  addPackageSource(result, "flatpak", flatpakSystem + flatpakUser)

  addPackageSource(result, "snap", countSnapInstalled("/var/lib/snapd/snaps"))
  addPackageSource(result, "portage", countDirs("/var/db/pkg"))
  addPackageSource(result, "eopkg", countDirs("/var/lib/eopkg/package"))
  addPackageSource(result, "xbps", countDirs("/var/db/xbps"))
  addPackageSource(result, "homebrew", countDirs("/usr/local/opt"))


proc formatPackageSummary(summary: PackageSummary): string =
  if summary.total <= 0:
    return "0"
  if summary.sources.len == 1:
    return fmt"{summary.total} ({summary.sources[0].name})"

  var parts: seq[string] = @[]
  for source in summary.sources:
    parts.add(source.name & " " & $source.count)
  let details = parts.join(" + ")
  fmt"{summary.total} ({details})"


proc packageSummaryJson(summary: PackageSummary): JsonNode =
  var sourcesNode = newJObject()
  for source in summary.sources:
    sourcesNode[source.name] = %source.count

  result = newJObject()
  result["total"] = %summary.total
  result["sources"] = sourcesNode


proc getShell(): string {.inline.} =
  ## Resolve the current shell from SHELL/$USER’s /etc/passwd entry.
  let shellEnv = getEnv("SHELL")
  if shellEnv.len > 0:
    let basename = shellEnv.splitPath().tail
    if basename.len > 0:
      return basename

  let userName = getEnv("USER")
  try:
    for line in lines("/etc/passwd"):
      let parts = line.split(':')
      if parts.len >= 7 and parts[0] == userName:
        let shellPath = parts[6]
        if shellPath.len > 0:
          return shellPath.splitPath().tail
  except IOError:
    discard

  "Unknown"


proc getUptime(): string =
  ## Format /proc/uptime into "X days, HH:MM:SS".
  var uptime: float
  try:
    let parts = readFile(uptimeFile).splitWhitespace()
    if parts.len == 0:
      return "Unable to read uptime"
    uptime = parseFloat(parts[0])
  except IOError, ValueError:
    return "Unable to read uptime"

  let
    uptimeDays = int(uptime / secsPerDay)
    uptimeSeconds = int(uptime.mod(secsPerDay))
    hours = uptimeSeconds div 3600
    minutes = (uptimeSeconds mod 3600) div 60
    seconds = uptimeSeconds mod 60

  fmt"{uptimeDays} days, {hours:02d}:{minutes:02d}:{seconds:02d}"


proc getMemory(): string =
  var memTotal, memAvailable: int

  proc parseMemField(value: string): int =
    let fields = value.strip.splitWhitespace()
    if fields.len > 0:
      try: return fields[0].parseInt()
      except ValueError: discard
    0

  if fileExists(meminfoPath):
    for line in lines(meminfoPath):
      let parts = line.split(":")
      if parts.len != 2: continue

      case parts[0].strip()
      of "MemTotal":
        memTotal = parseMemField(parts[1])
      of "MemAvailable":
        memAvailable = parseMemField(parts[1])
      else:
        discard

  if memTotal <= 0 or memAvailable <= 0:
    return "Unknown memory"

  let usedMem = memTotal - memAvailable

  if usedMem >= 1048576:
    return fmt"{usedMem.float / gibDivisor:0.2f}GiB / {memTotal.float / gibDivisor:0.2f}GiB"
  fmt"{usedMem div mibDivisor}MiB / {memTotal div mibDivisor}MiB"


proc getDE(): string =
  ## Try common desktop environment variables, fallback to WM name.
  result = getEnv("XDG_CURRENT_DESKTOP")
  if result == "":
    result = getEnv("DESKTOP_SESSION")
  if result == "":
    result = getEnv("GDMSESSION")
  if result == "":
    let wmName = getEnv("WINDOW_MANAGER")
    if wmName != "":
      result = wmName.splitPath().tail
  if result == "":
    result = "Unknown"


proc collectSnapshot(): SystemSnapshot =
  result.os = getOS()
  result.kernel = getKernel()
  result.desktop = getDE()
  result.shell = getShell()
  result.uptime = getUptime()
  result.memory = getMemory()
  result.packages = detectPackageSummary()


proc coloursLine(): string =
  ## Print a sequence of themed swatches.
  let token = if activeIcons.swatches.len > 0: activeIcons.swatches[rand(activeIcons.swatches.high)] else: "##"
  let palette = [activePalette.rosewater, activePalette.mauve, activePalette.pink, activePalette.maroon, activePalette.sky, activePalette.green, activePalette.lavender]

  for color in palette:
    if disableColor or color.len == 0:
      result.add token
    else:
      result.add color & token
    result.add " "

  if not disableColor and activePalette.reset.len > 0:
    result.add activePalette.reset


proc statLine(accent, iconValue, label, value: string): string =
  fmt"{accent}{iconValue}  {activePalette.yellow}{activePalette.bold}{label}:{activePalette.reset}  {value}"


proc buildStatsEntries(statsCol: int; snapshot: SystemSnapshot; modules: seq[ModuleKind]): seq[StatEntry] =
  var row = 1
  for moduleKind in modules:
    var line = ""
    case moduleKind
    of mkOS:
      line = statLine(activePalette.rosewater, activeIcons.os, "OS", snapshot.os)
    of mkKernel:
      line = statLine(activePalette.pink, activeIcons.kernel, "Kernel", snapshot.kernel)
    of mkDesktop:
      line = statLine(activePalette.mauve, activeIcons.desktop, "DE/WM", snapshot.desktop)
    of mkPackages:
      line = statLine(activePalette.maroon, activeIcons.pkgs, "Pkgs", formatPackageSummary(snapshot.packages))
    of mkShell:
      line = statLine(activePalette.sky, activeIcons.shell, "Shell", snapshot.shell)
    of mkUptime:
      line = statLine(activePalette.green, activeIcons.uptime, "Uptime", snapshot.uptime)
    of mkMemory:
      line = statLine(activePalette.lavender, activeIcons.memory, "Memory", snapshot.memory)
    of mkColours:
      line = "       " & coloursLine()

    result.add StatEntry(col: statsCol, row: row, text: line)
    inc row


proc computeLogoCells(logo: LogoData): tuple[cols, rows: int] =
  ## Convert PNG dimensions to terminal cell counts while preserving aspect ratio.
  let metrics = getCellMetrics()
  let cw = max(1.0, metrics.cellWidth)
  let ch = max(1.0, metrics.cellHeight)
  let targetWidth = min(logo.width, appConfig.maxLogoWidth)
  let scale = targetWidth.float / max(logo.width.float, 1.0)
  let targetHeight = logo.height.float * scale
  var cols = max(1, int(ceil(targetWidth.float / cw)))
  var rows = max(1, int(ceil(targetHeight / ch)))

  let maxCols = max(1, terminalWidth())
  let maxRows = max(1, terminalHeight())
  let halfCols = max(1, maxCols div 2)
  if cols > halfCols:
    let scaleDown = halfCols.float / cols.float
    cols = halfCols
    rows = max(1, int(ceil(rows.float * scaleDown)))
  elif cols >= maxCols:
    cols = max(1, maxCols - 1)

  if rows >= maxRows:
    rows = max(1, maxRows - 1)

  (cols, rows)


proc computeStatsOffset(): int =
  ## Derive a stats start column based on logo width and cell metrics.
  let metrics = getCellMetrics()
  let cw = max(1.0, metrics.cellWidth)
  let colsFromLogo = int(ceil(appConfig.maxLogoWidth.float / cw)) + 2
  let base = max(appConfig.statsOffset, colsFromLogo)
  let maxCols = max(1, terminalWidth())
  min(base, maxCols div 2 + 2)


proc stripAnsi(text: string): string =
  ## Remove ANSI escape sequences for --no-color output.
  proc isAnsiFinalByte(ch: char): bool {.inline.} =
    ch >= '@' and ch <= '~'

  var i = 0
  while i < text.len:
    if text[i] == '\x1b' and i + 1 < text.len:
      let marker = text[i + 1]
      if marker == '[':
        var j = i + 2
        while j < text.len and not isAnsiFinalByte(text[j]):
          inc j
        if j < text.len:
          i = j + 1
          continue
      elif marker == ']':
        var j = i + 2
        var consumed = false
        while j < text.len:
          if text[j] == '\x07':
            i = j + 1
            consumed = true
            break
          if text[j] == '\x1b' and j + 1 < text.len and text[j + 1] == '\\':
            i = j + 2
            consumed = true
            break
          inc j
        if consumed:
          continue
      else:
        i += 2
        continue
    result.add(text[i])
    inc i


proc resolveLogo(logoOverride: string): tuple[logo: LogoData, name: string, path: string] =
  var overridePath = ""
  if logoOverride.len > 0:
    let candidatePath = normalizeDir(logoOverride)
    if fileExists(candidatePath):
      overridePath = candidatePath

  if overridePath.len > 0:
    result.logo = loadLogoFromPath(overridePath)
    result.path = overridePath
    result.name = overridePath.splitFile.name.toLowerAscii()

  if result.logo.bytes.len == 0 and appConfig.customLogoFile.len > 0:
    let customPath = normalizeDir(appConfig.customLogoFile)
    result.logo = loadLogoFromPath(customPath)
    if result.logo.bytes.len > 0:
      result.path = customPath
      result.name = customPath.splitFile.name.toLowerAscii()

  let detectedLogoName = detectLogoName(if overridePath.len == 0: logoOverride else: "")
  if result.logo.bytes.len == 0:
    result.logo = loadLogo(detectedLogoName)
    if result.logo.bytes.len > 0:
      result.name = detectedLogoName
      result.path = locateLogoFile(detectedLogoName, ".png")

  if result.logo.bytes.len == 0:
    result.logo = loadLogo(DefaultLogoName)
    if result.logo.bytes.len > 0:
      result.name = DefaultLogoName
      result.path = locateLogoFile(DefaultLogoName, ".png")

  if result.name.len == 0:
    result.name = DefaultLogoName


proc printHelp() =
  echo "Nymph - lightweight system summary"
  echo ""
  echo "Usage: nymph [options]"
  echo "  --logo <name|path>        Override logo by name or PNG path"
  echo "  --no-color                Disable ANSI colors"
  echo "  --json                    Print machine-readable JSON"
  echo "  --doctor                  Print diagnostics and exit"
  echo "  --theme <name>            Theme: catppuccin, nord, gruvbox, plain"
  echo "  --icon-pack <name>        Icon pack: nerd, ascii, mono"
  echo "  --layout <name>           Layout: full, compact, minimal"
  echo "  --modules <csv>           Explicit modules (os,kernel,packages,...)"
  echo "  --list-themes             List built-in themes"
  echo "  --list-icon-packs         List built-in icon packs"
  echo "  -h, --help                Show this help"


proc printThemeList() =
  echo "Themes: catppuccin, nord, gruvbox, plain"


proc printIconPackList() =
  echo "Icon packs: nerd, ascii, mono"


proc doctorOutput(snapshot: SystemSnapshot; modules: seq[ModuleKind]; logoInfo: tuple[logo: LogoData, name: string, path: string]; kittyCapable: bool; jsonEnabled: bool) =
  echo "Nymph doctor"
  echo "config.path: " & (if appConfig.loadedConfigPath.len > 0: appConfig.loadedConfigPath else: "(none)")
  echo "config.theme: " & appConfig.theme
  echo "config.iconpack: " & appConfig.iconPack
  echo "config.layout: " & appConfig.layout
  echo "runtime.theme: " & activeThemeName
  echo "runtime.iconpack: " & activeIconPackName
  echo "runtime.layout: " & activeLayoutName
  echo "runtime.modules: " & modulesAsNames(modules).join(",")
  echo "runtime.nocolor: " & $disableColor
  echo "runtime.json: " & $jsonEnabled
  echo "terminal.kittyGraphics: " & $kittyCapable
  echo "terminal.TERM: " & getEnv("TERM")
  echo "terminal.TERM_PROGRAM: " & getEnv("TERM_PROGRAM")
  echo "terminal.TERMINAL_EMULATOR: " & getEnv("TERMINAL_EMULATOR")
  echo "logo.selected: " & logoInfo.name
  echo "logo.path: " & (if logoInfo.path.len > 0: logoInfo.path else: "(ascii fallback)")
  if logoInfo.logo.bytes.len > 0:
    echo fmt"logo.dimensions: {logoInfo.logo.width}x{logoInfo.logo.height}"
  else:
    echo "logo.dimensions: (none)"
  echo "logo.searchDirs:"
  for dir in getLogoSearchDirs():
    echo "  - " & dir
  echo "packages: " & formatPackageSummary(snapshot.packages)


proc outputJson(snapshot: SystemSnapshot; modules: seq[ModuleKind]; logoInfo: tuple[logo: LogoData, name: string, path: string]; kittyCapable: bool) =
  var root = newJObject()
  root["os"] = %snapshot.os
  root["kernel"] = %snapshot.kernel
  root["desktop"] = %snapshot.desktop
  root["shell"] = %snapshot.shell
  root["uptime"] = %snapshot.uptime
  root["memory"] = %snapshot.memory
  root["packages"] = packageSummaryJson(snapshot.packages)
  root["theme"] = %activeThemeName
  root["icon_pack"] = %activeIconPackName
  root["layout"] = %activeLayoutName
  root["modules"] = %modulesAsNames(modules)
  root["no_color"] = %disableColor
  root["kitty_graphics"] = %kittyCapable

  var logoNode = newJObject()
  logoNode["name"] = %logoInfo.name
  logoNode["path"] = %(if logoInfo.path.len > 0: logoInfo.path else: "")
  logoNode["width"] = %logoInfo.logo.width
  logoNode["height"] = %logoInfo.logo.height
  logoNode["ascii_fallback"] = % (logoInfo.logo.bytes.len == 0)
  root["logo"] = logoNode

  echo root.pretty()


when isMainModule:
  randomize()

  appConfig = loadConfig()
  let cli = parseCliOptions()

  if cli.help:
    printHelp()
    quit(0)
  if cli.listThemes:
    printThemeList()
    quit(0)
  if cli.listIconPacks:
    printIconPackList()
    quit(0)

  activeThemeName = normalizeThemeName(if cli.theme.len > 0: cli.theme else: appConfig.theme)
  activePalette = resolveTheme(activeThemeName)

  activeIconPackName = normalizeIconPackName(if cli.iconPack.len > 0: cli.iconPack else: appConfig.iconPack)
  activeIcons = resolveIconPack(activeIconPackName)

  activeLayoutName = normalizeLayoutName(if cli.layout.len > 0: cli.layout else: appConfig.layout)

  var requestedModules: seq[string] = @[]
  if cli.modules.len > 0:
    requestedModules = cli.modules
  elif appConfig.modules.len > 0:
    requestedModules = appConfig.modules
  let modules = resolveModules(activeLayoutName, requestedModules)

  disableColor = cli.noColor or appConfig.noColor or activeThemeName == "plain"
  let jsonEnabled = cli.jsonOutput or appConfig.jsonOutput

  let logoOverride = cli.logo.strip()
  let logoInfo = resolveLogo(logoOverride)
  let kittyCapable = supportsKittyGraphics()
  let snapshot = collectSnapshot()

  if cli.doctor:
    doctorOutput(snapshot, modules, logoInfo, kittyCapable, jsonEnabled)
    quit(0)

  if jsonEnabled:
    outputJson(snapshot, modules, logoInfo, kittyCapable)
    quit(0)

  stdout.eraseScreen()
  if kittyCapable and logoInfo.logo.bytes.len > 0:
    stdout.setCursorPos(1, 1)
    let placement = computeLogoCells(logoInfo.logo)
    displayKittyGraphics(logoInfo.logo.bytes, placement.cols, placement.rows)
  else:
    stdout.setCursorPos(1, 1)
    stdout.write(AsciiFallbackLogo)

  let statsCol = computeStatsOffset()
  for entry in buildStatsEntries(statsCol, snapshot, modules):
    stdout.setCursorPos(entry.col, entry.row)
    stdout.write(if disableColor: stripAnsi(entry.text) else: entry.text)

  stdout.write("\n\n")
  stdout.flushFile()
