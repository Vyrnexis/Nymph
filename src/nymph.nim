## Nymph: Lightweight system summary and fetch tool with Kitty & iTerm2 graphics support.
import std/[os, terminal, math, strutils, strformat, random, sets, posix, json]
import kitty_proto, nymph_settings

type
  ThemePalette* = object
    ## ANSI escape sequences defining a color palette theme.
    rosewater*: string
    pink*: string
    mauve*: string
    maroon*: string
    yellow*: string
    green*: string
    sky*: string
    lavender*: string
    bold*: string
    reset*: string

  IconPack* = object
    ## Glyph symbols representing individual system information modules.
    title*: string
    os*: string
    host*: string
    kernel*: string
    cpu*: string
    gpu*: string
    resolution*: string
    pkgs*: string
    desktop*: string
    audio*: string
    shell*: string
    terminal*: string
    uptime*: string
    localip*: string
    memory*: string
    disk*: string
    battery*: string
    swatches*: seq[string]

  PackageSource* = object
    ## Package manager name and associated installed package count.
    name*: string
    count*: int

  PackageSummary* = object
    ## Aggregated package statistics across all detected package managers.
    total*: int
    sources*: seq[PackageSource]

  MemoryInfo* = object
    ## Physical RAM metrics and capacity utilization.
    text*: string
    usedKiB*: int
    totalKiB*: int
    percent*: float
    known*: bool

  DiskInfo* = object
    ## Root filesystem storage statistics.
    text*: string
    percent*: float
    known*: bool

  BatteryInfo* = object
    ## Battery state of charge and power supply status.
    text*: string
    percent*: float
    isCharging*: bool
    known*: bool

  ModuleKind* = enum
    ## Enumeration of all supported information modules.
    mkTitle,
    mkOS,
    mkHost,
    mkKernel,
    mkCPU,
    mkGPU,
    mkResolution,
    mkDesktop,
    mkAudio,
    mkPackages,
    mkShell,
    mkTerminal,
    mkUptime,
    mkLocalIP,
    mkMemory,
    mkDisk,
    mkBattery,
    mkFooter

  CliOptions* = object
    ## Parsed command-line flags and parameters.
    logo*: string
    theme*: string
    iconPack*: string
    layout*: string
    modules*: seq[string]
    battery*: string
    noColor*: bool
    jsonOutput*: bool
    doctor*: bool
    listThemes*: bool
    listIconPacks*: bool
    help*: bool

  SystemSnapshot* = object
    ## Complete captured snapshot of hardware, software, and runtime metrics.
    user*: string
    hostname*: string
    os*: string
    host*: string
    kernel*: string
    cpu*: string
    gpu*: string
    resolution*: string
    desktop*: string
    audio*: string
    shell*: string
    terminal*: string
    uptime*: string
    localip*: string
    memory*: MemoryInfo
    disk*: DiskInfo
    battery*: BatteryInfo
    packages*: PackageSummary

  LogoData* = object
    ## Raw image or text logo payload data and dimensions.
    bytes*: string
    width*: int
    height*: int
    isText*: bool
    textLines*: seq[string]

const
  DefaultLogoName* = "generic"
  sourceLogoDir = parentDir(currentSourcePath()) / "logos"
  projectLogoDir = parentDir(parentDir(currentSourcePath())) / ".config" / "nymph" / "logos"
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
  bytesPerGib = 1024.0 * 1024.0 * 1024.0

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
  title: "",
  os: "",
  host: "󰒋",
  kernel: "",
  cpu: "",
  gpu: "󰢮",
  resolution: "󰍹",
  pkgs: "󰏖",
  desktop: "󰇄",
  audio: "󰕾",
  shell: "",
  terminal: "",
  uptime: "",
  localip: "󰩟",
  memory: "󰍛",
  disk: "󰋊",
  battery: "",
  swatches: @NerdSwatchIcons
)

proc parseCsv*(raw: string): seq[string] =
  ## Splits a comma-separated string into a sequence of normalized lowercase tokens.
  for item in raw.split(','):
    let value = item.strip().toLowerAscii()
    if value.len > 0:
      result.add value

proc moduleName*(moduleKind: ModuleKind): string =
  ## Maps an internal ModuleKind enum identifier to its canonical string representation.
  case moduleKind
  of mkTitle: "title"
  of mkOS: "os"
  of mkHost: "host"
  of mkKernel: "kernel"
  of mkCPU: "cpu"
  of mkGPU: "gpu"
  of mkResolution: "resolution"
  of mkDesktop: "desktop"
  of mkAudio: "audio"
  of mkPackages: "packages"
  of mkShell: "shell"
  of mkTerminal: "terminal"
  of mkUptime: "uptime"
  of mkLocalIP: "localip"
  of mkMemory: "memory"
  of mkDisk: "disk"
  of mkBattery: "battery"
  of mkFooter: "footer"

proc parseModule*(name: string; moduleKind: var ModuleKind): bool =
  ## Parses a user-supplied module name string into its corresponding ModuleKind enum value.
  case name.strip().toLowerAscii()
  of "title", "user", "header":
    moduleKind = mkTitle
    true
  of "os":
    moduleKind = mkOS
    true
  of "host", "machine", "model":
    moduleKind = mkHost
    true
  of "kernel":
    moduleKind = mkKernel
    true
  of "cpu", "processor":
    moduleKind = mkCPU
    true
  of "gpu", "graphics", "vga":
    moduleKind = mkGPU
    true
  of "resolution", "display", "screen":
    moduleKind = mkResolution
    true
  of "desktop", "de", "wm", "dewm":
    moduleKind = mkDesktop
    true
  of "audio", "sound":
    moduleKind = mkAudio
    true
  of "packages", "package", "pkgs":
    moduleKind = mkPackages
    true
  of "shell":
    moduleKind = mkShell
    true
  of "terminal", "term":
    moduleKind = mkTerminal
    true
  of "uptime":
    moduleKind = mkUptime
    true
  of "localip", "ip", "network", "net":
    moduleKind = mkLocalIP
    true
  of "memory", "mem", "ram":
    moduleKind = mkMemory
    true
  of "disk", "storage":
    moduleKind = mkDisk
    true
  of "battery", "bat":
    moduleKind = mkBattery
    true
  of "footer", "colours", "colors", "palette":
    moduleKind = mkFooter
    true
  else:
    false

proc normalizeLayoutName*(name: string): string =
  ## Validates and normalizes layout string identifiers against supported layout presets.
  case name.strip().toLowerAscii()
  of "compact": "compact"
  of "minimal": "minimal"
  else: "full"

proc defaultModules*(layout: string): seq[ModuleKind] =
  ## Returns the predefined list of module identifiers associated with a given layout preset.
  case normalizeLayoutName(layout)
  of "minimal":
    @[mkTitle, mkOS, mkHost, mkKernel, mkUptime, mkPackages, mkMemory, mkDisk]
  of "compact":
    @[mkTitle, mkOS, mkHost, mkKernel, mkCPU, mkGPU, mkDesktop, mkPackages, mkMemory, mkUptime]
  else:
    @[mkTitle, mkOS, mkHost, mkKernel, mkCPU, mkGPU, mkResolution, mkDesktop, mkAudio, mkTerminal, mkShell, mkPackages, mkUptime, mkLocalIP, mkMemory, mkDisk, mkBattery, mkFooter]

proc resolveModules*(layout: string; names: seq[string]): seq[ModuleKind] =
  ## Resolves a validated, deduplicated sequence of active modules from names and layout fallback.
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

proc modulesAsNames*(modules: seq[ModuleKind]): seq[string] =
  ## Converts a sequence of ModuleKind enum values into a sequence of canonical name strings.
  for moduleKind in modules:
    result.add moduleName(moduleKind)

proc normalizeThemeName*(name: string): string =
  ## Validates and normalizes theme identifier strings to supported theme presets.
  case name.strip().toLowerAscii()
  of "nord": "nord"
  of "gruvbox": "gruvbox"
  of "plain": "plain"
  else: "catppuccin"

proc resolveTheme*(name: string): ThemePalette =
  ## Generates ANSI escape palettes matching the requested theme configuration.
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

proc normalizeIconPackName*(name: string): string =
  ## Validates and normalizes icon pack identifier strings to supported icon styles.
  case name.strip().toLowerAscii()
  of "ascii": "ascii"
  of "mono": "mono"
  else: "nerd"

proc resolveIconPack*(name: string): IconPack =
  ## Resolves glyph icon sets according to the specified icon pack profile.
  case normalizeIconPackName(name)
  of "ascii":
    IconPack(
      title: "US",
      os: "OS",
      host: "PC",
      kernel: "KR",
      cpu: "CP",
      gpu: "GP",
      resolution: "RS",
      pkgs: "PK",
      desktop: "DE",
      audio: "AU",
      shell: "SH",
      terminal: "TE",
      uptime: "UP",
      localip: "IP",
      memory: "MM",
      disk: "DK",
      battery: "BT",
      swatches: @AsciiSwatchIcons
    )
  of "mono":
    IconPack(
      title: "#",
      os: "#",
      host: "#",
      kernel: "#",
      cpu: "#",
      gpu: "#",
      resolution: "#",
      pkgs: "#",
      desktop: "#",
      audio: "#",
      shell: "#",
      terminal: "#",
      uptime: "#",
      localip: "#",
      memory: "#",
      disk: "#",
      battery: "#",
      swatches: @["##", "##", "##"]
    )
  else:
    IconPack(
      title: "",
      os: "",
      host: "󰒋",
      kernel: "",
      cpu: "",
      gpu: "󰢮",
      resolution: "󰍹",
      pkgs: "󰏖",
      desktop: "󰇄",
      audio: "󰕾",
      shell: "",
      terminal: "",
      uptime: "",
      localip: "󰩟",
      memory: "󰍛",
      disk: "󰋊",
      battery: "",
      swatches: @NerdSwatchIcons
    )

proc getLogoSearchDirs*(): seq[string] =
  ## Aggregates prioritized filesystem paths searched for distribution logo assets.
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

proc locateLogoFile*(name, ext: string): string =
  ## Searches registered logo directories for a file matching the target name and extension.
  let fileName = name.toLowerAscii() & ext
  for dir in getLogoSearchDirs():
    let path = dir / fileName
    if fileExists(path):
      return path
  ""

proc parsePngDims*(data: string): (int, int) =
  ## Extracts pixel dimensions from binary PNG header chunks.
  if data.len < 24:
    return (0, 0)
  if not data.startsWith("\x89PNG\x0d\x0a\x1a\x0a"):
    return (0, 0)
  let w = (ord(data[16]) shl 24) or (ord(data[17]) shl 16) or (ord(data[18]) shl 8) or ord(data[19])
  let h = (ord(data[20]) shl 24) or (ord(data[21]) shl 16) or (ord(data[22]) shl 8) or ord(data[23])
  (w, h)

proc loadLogo*(name: string): LogoData =
  ## Loads raw image bytes and dimensions for a given logo name identifier.
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

proc loadLogoFromPath*(path: string): LogoData =
  ## Reads an explicit file path as binary PNG or text-based ASCII art logo.
  let norm = normalizeDir(path)
  if norm.len == 0 or not fileExists(norm):
    return
  try:
    let ext = norm.splitFile.ext.toLowerAscii()
    if ext in [".txt", ".ascii"]:
      let lines = readFile(norm).splitLines()
      var textLines: seq[string] = @[]
      for line in lines:
        textLines.add(line.replace("\t", "    "))
      result.isText = true
      result.textLines = textLines
      return

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

proc getWindowPixels*(): tuple[width, height: int] =
  ## Queries the active terminal window size in physical pixels via POSIX ioctl.
  when defined(posix):
    var ws: TermWinSize
    if ioctl(STDOUT_FILENO, ioctlWinSize, addr ws) == 0:
      return (int(ws.ws_xpixel), int(ws.ws_ypixel))
  (0, 0)

proc getCellMetrics*(): tuple[cellWidth, cellHeight: float] =
  ## Estimates individual character cell width and height in pixels from terminal metrics.
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

proc collectAvailableLogos*(): seq[string] =
  ## Scans search directories and returns all unique available PNG logo identifiers.
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

proc sanitizeLogoName*(name: string): string =
  ## Strips non-alphanumeric characters to allow fuzzy matching of logo filenames.
  for ch in name.toLowerAscii():
    if ch.isAlphaNumeric:
      result.add(ch)

proc findBestLogoMatch*(candidates: seq[string]): string =
  ## Selects the optimal matching logo filename from a prioritized list of candidate names.
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

proc parseCliOptions*(): CliOptions =
  ## Parses command line arguments and populates runtime CLI configuration flags.
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
    elif param.startsWith("--battery=") or param.startsWith("--fake-battery="):
      result.battery = param.split('=', 1)[1]
    elif param == "--battery" or param == "--fake-battery":
      result.battery = pullNext(i)
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

proc detectLogoName*(cliLogo: string): string =
  ## Inspects system release configurations and returns candidate logo identifiers.
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

proc getTitle*(): tuple[user, hostname: string] =
  ## Resolves current logged-in username and machine network hostname.
  var user = getEnv("USER")
  if user.len == 0:
    user = getEnv("LOGNAME")
  if user.len == 0:
    user = "user"

  var hostname = getEnv("HOSTNAME")
  if hostname.len == 0 and fileExists("/etc/hostname"):
    try: hostname = readFile("/etc/hostname").strip()
    except IOError: discard
  if hostname.len == 0 and fileExists("/proc/sys/kernel/hostname"):
    try: hostname = readFile("/proc/sys/kernel/hostname").strip()
    except IOError: discard
  if hostname.len == 0:
    var buf = newString(256)
    if posix.gethostname(cstring(buf), 256) == 0:
      hostname = ($cstring(buf)).strip()
  if hostname.len == 0:
    hostname = "localhost"

  (user, hostname)

proc getOS*(): string {.inline.} =
  ## Extracts the operating system distribution name from standard release files.
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

proc getKernel*(): string {.inline.} =
  ## Retrieves the current running Linux kernel version string.
  if fileExists(versionFile):
    let tokens = readFile(versionFile).splitWhitespace()
    if tokens.len >= 3:
      return tokens[2]
    elif tokens.len > 0:
      return tokens[^1]
  "Unknown Kernel Version"

proc getHost*(): string =
  ## Inspects DMI tables to determine machine hardware model and version.
  if fileExists("/sys/devices/virtual/dmi/id/product_name"):
    try:
      let name = readFile("/sys/devices/virtual/dmi/id/product_name").strip()
      let verPath = "/sys/devices/virtual/dmi/id/product_version"
      let ver = if fileExists(verPath): readFile(verPath).strip() else: ""
      if name.len > 0:
        if ver.len > 0 and ver != "None" and ver != name: return name & " " & ver
        return name
    except IOError:
      discard
  ""

proc getCPU*(): string =
  ## Reads and cleans processor model metadata across x86 and ARM architectures.
  if fileExists("/proc/cpuinfo"):
    try:
      var modelName = ""
      var hardwareName = ""
      for line in lines("/proc/cpuinfo"):
        if line.startsWith("model name") or line.startsWith("Processor"):
          let parts = line.split(":", 1)
          if parts.len == 2:
            modelName = parts[1].strip()
            break
        elif line.startsWith("Hardware") or line.startsWith("Model"):
          let parts = line.split(":", 1)
          if parts.len == 2 and hardwareName.len == 0:
            hardwareName = parts[1].strip()

      var cpu = if modelName.len > 0: modelName else: hardwareName
      if cpu.len > 0:
        cpu = cpu.replace("(R)", "").replace("(TM)", "").replace(" CPU", "")
        let atPos = cpu.find(" @")
        if atPos > 0: cpu = cpu[0 ..< atPos]
        return cpu.strip()
    except IOError:
      discard
  ""

proc getGPU*(): string =
  ## Scans PCI devices in sysfs and maps vendor and device identifiers to GPU models.
  const pciIdsPaths = [
    "/usr/share/hwdata/pci.ids",
    "/usr/share/misc/pci.ids",
    "/usr/share/pci.ids",
    "/var/lib/pci.ids"
  ]
  var pciIdsPath = ""
  for path in pciIdsPaths:
    if fileExists(path):
      pciIdsPath = path
      break

  var gpus: seq[string] = @[]
  const pciDevicesDir = "/sys/bus/pci/devices"

  if dirExists(pciDevicesDir):
    try:
      for kind, devPath in walkDir(pciDevicesDir):
        if kind != pcDir and kind != pcLinkToDir:
          continue
        let classFile = devPath / "class"
        if not fileExists(classFile):
          continue

        var classStr = ""
        try: classStr = readFile(classFile).strip()
        except IOError: continue

        if not classStr.startsWith("0x03"):
          continue

        var vendor = ""
        var device = ""
        try:
          if fileExists(devPath / "vendor"):
            vendor = readFile(devPath / "vendor").strip().toLowerAscii()
            if vendor.startsWith("0x"): vendor = vendor[2 .. ^1]
          if fileExists(devPath / "device"):
            device = readFile(devPath / "device").strip().toLowerAscii()
            if device.startsWith("0x"): device = device[2 .. ^1]
        except IOError:
          continue

        var gpuName = ""
        if pciIdsPath.len > 0 and vendor.len > 0 and device.len > 0:
          try:
            var inVendorBlock = false
            for line in lines(pciIdsPath):
              if line.len == 0 or line[0] == '#':
                continue
              if line[0] != '\t':
                let v = line[0 ..< min(line.len, 4)].toLowerAscii()
                inVendorBlock = (v == vendor)
              elif inVendorBlock and line.startsWith("\t" & device):
                let parts = line.strip().splitWhitespace()
                if parts.len >= 2:
                  gpuName = parts[1 .. ^1].join(" ")
                  break
          except IOError:
            discard

        if gpuName.len == 0:
          case vendor
          of "10de": gpuName = "NVIDIA Graphics"
          of "1002": gpuName = "AMD Radeon Graphics"
          of "8086": gpuName = "Intel Graphics"
          of "1af4": gpuName = "VirtIO GPU"
          of "15ad": gpuName = "VMware SVGA II"
          of "1ab8": gpuName = "Parallels Display"
          of "1234": gpuName = "QEMU Standard VGA"
          else:
            if vendor.len > 0 and device.len > 0:
              gpuName = "GPU [" & vendor & ":" & device & "]"

        if gpuName.len > 0:
          gpuName = gpuName.replace("Advanced Micro Devices, Inc. [AMD/ATI] ", "").replace("NVIDIA Corporation ", "")
          if not gpus.contains(gpuName):
            gpus.add gpuName
    except OSError:
      discard

  gpus.join(", ")

proc getResolution*(): string =
  ## Queries DRM display connectors for active resolutions and refresh rates.
  const drmDir = "/sys/class/drm"
  if not dirExists(drmDir):
    return ""

  var displays: seq[string] = @[]
  try:
    for kind, path in walkDir(drmDir):
      if kind != pcDir and kind != pcLinkToDir:
        continue
      let statusFile = path / "status"
      let modesFile = path / "modes"
      if fileExists(statusFile) and fileExists(modesFile):
        try:
          if readFile(statusFile).strip() == "connected":
            for mode in lines(modesFile):
              let m = mode.strip()
              if m.len > 0:
                if not displays.contains(m):
                  displays.add m
                break
        except IOError:
          discard
  except OSError:
    discard

  displays.join(", ")

proc getAudio*(): string =
  ## Detects active audio sound server daemon from runtime socket files.
  let xdgRuntime = getEnv("XDG_RUNTIME_DIR")
  if xdgRuntime.len > 0:
    if fileExists(xdgRuntime / "pipewire-0") or dirExists(xdgRuntime / "pipewire-0"):
      return "PipeWire"
    if fileExists(xdgRuntime / "pulse" / "native"):
      return "PulseAudio"

  if dirExists("/dev/snd"):
    return "ALSA"

  ""

proc getLocalIP*(): string =
  ## Determines the active local IPv4 routing interface address.
  try:
    let s = posix.socket(posix.AF_INET, posix.SOCK_DGRAM, 0)
    if s.cint >= 0:
      defer: discard posix.close(s)
      var target: posix.Sockaddr_in
      target.sin_family = posix.AF_INET.TSa_Family
      target.sin_port = posix.htons(53)
      target.sin_addr.s_addr = 0x08080808.uint32
      if posix.connect(s, cast[ptr posix.SockAddr](addr target), posix.SockLen(sizeof(target))) == 0:
        var localAddr: posix.Sockaddr_in
        var addrLen = posix.SockLen(sizeof(localAddr))
        if posix.getsockname(s, cast[ptr posix.SockAddr](addr localAddr), addr addrLen) == 0:
          let ipPtr = posix.inet_ntoa(localAddr.sin_addr)
          if ipPtr != nil:
            let ipStr = $ipPtr
            if ipStr != "0.0.0.0" and ipStr.len > 0:
              return ipStr
  except Exception:
    discard
  ""

proc countDirs*(path: string): int =
  ## Counts immediate child directories within a specified filesystem path.
  if not dirExists(path):
    return 0
  try:
    for kind, _ in walkDir(path):
      if kind == pcDir:
        inc result
  except OSError:
    discard

proc countNestedDirs*(path: string): int =
  ## Traverses two directory levels to count packages in multi-category repositories.
  if not dirExists(path):
    return 0
  try:
    for kind, category in walkDir(path):
      if kind == pcDir:
        for innerKind, _ in walkDir(category):
          if innerKind == pcDir:
            inc result
  except OSError:
    discard

proc countDpkgInstalled*(path: string): int =
  ## Parses dpkg status file entries to count installed Debian packages.
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

proc countApkInstalled*(paths: openArray[string]): int =
  ## Counts package database records from Alpine apk installed files.
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

proc countSnapInstalled*(path: string): int =
  ## Counts snap application bundle files in snap storage directories.
  if not dirExists(path):
    return 0
  try:
    for kind, item in walkDir(path):
      if kind == pcFile and item.endsWith(".snap"):
        inc result
  except OSError:
    discard

proc countRpmInstalled*(): int =
  ## Counts RPM packages by inspecting local rpmdb files and databases.
  const rpmDbPaths = ["/var/lib/rpm/rpmdb.sqlite", "/usr/lib/sysimage/rpm/rpmdb.sqlite"]
  for path in rpmDbPaths:
    if fileExists(path):
      try:
        let size = getFileSize(path)
        if size > 65536:
          return max(1, int(size div 40960))
      except OSError:
        discard
  0

proc addPackageSource*(summary: var PackageSummary; name: string; count: int) =
  ## Appends a package manager source entry to the aggregated summary record.
  if count <= 0:
    return
  summary.sources.add PackageSource(name: name, count: count)
  summary.total += count

proc detectPackageSummary*(): PackageSummary =
  ## Detects installed package counts across all supported system package managers.
  addPackageSource(result, "pacman", countDirs("/var/lib/pacman/local"))
  addPackageSource(result, "dpkg", countDpkgInstalled("/var/lib/dpkg/status"))
  addPackageSource(result, "apk", countApkInstalled(["/lib/apk/db/installed", "/var/lib/apk/db/installed"]))

  let flatpakSystem = countDirs("/var/lib/flatpak/app")
  let flatpakUser = countDirs(normalizeDir(getHomeDir() / ".local" / "share" / "flatpak" / "app"))
  addPackageSource(result, "flatpak", flatpakSystem + flatpakUser)

  addPackageSource(result, "snap", countSnapInstalled("/var/lib/snapd/snaps"))
  addPackageSource(result, "portage", countNestedDirs("/var/db/pkg"))
  addPackageSource(result, "eopkg", countDirs("/var/lib/eopkg/package"))
  addPackageSource(result, "xbps", countDirs("/var/db/xbps"))

  let brewDirs = [
    "/home/linuxbrew/.linuxbrew/Cellar",
    "/opt/homebrew/Cellar",
    "/usr/local/Cellar",
    "/usr/local/opt"
  ]
  var brewCount = 0
  for dir in brewDirs:
    if dirExists(dir):
      brewCount = countDirs(dir)
      if brewCount > 0:
        break
  addPackageSource(result, "homebrew", brewCount)
  addPackageSource(result, "rpm", countRpmInstalled())

proc formatPackageSummary*(summary: PackageSummary): string =
  ## Formats package manager metrics into human-readable summary text.
  if summary.total <= 0:
    return "0"
  if summary.sources.len == 1:
    return fmt"{summary.total} ({summary.sources[0].name})"

  var parts: seq[string] = @[]
  for source in summary.sources:
    parts.add(source.name & " " & $source.count)
  let details = parts.join(" + ")
  fmt"{summary.total} ({details})"

proc packageSummaryJson*(summary: PackageSummary): JsonNode =
  ## Encodes package manager inspection metrics into a JSON data structure.
  var sourcesNode = newJObject()
  for source in summary.sources:
    sourcesNode[source.name] = %source.count

  result = newJObject()
  result["total"] = %summary.total
  result["sources"] = sourcesNode

proc getShell*(): string {.inline.} =
  ## Resolves the active login or interactive shell name.
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

proc getTerminal*(): string =
  ## Resolves the current terminal emulator identifier from environment variables.
  let termProg = getEnv("TERM_PROGRAM")
  if termProg.len > 0: return termProg

  if getEnv("KITTY_WINDOW_ID").len > 0: return "kitty"
  if getEnv("WEZTERM_VERSION").len > 0: return "wezterm"
  if getEnv("GHOSTTY_RESOURCES_DIR").len > 0: return "ghostty"
  if getEnv("KONSOLE_VERSION").len > 0: return "konsole"
  if getEnv("ALACRITTY_WINDOW_ID").len > 0: return "alacritty"
  if getEnv("FOOT_TERMINAL").len > 0: return "foot"

  let termEnv = getEnv("TERM")
  if termEnv.len > 0: return termEnv

  "Unknown"

proc getBattery*(overrideBat = ""): BatteryInfo =
  ## Inspects Linux sysfs power supplies to gather aggregate battery charge and status.
  var batInput = overrideBat
  if batInput.len == 0:
    batInput = getEnv("NYMPH_BATTERY")
  if batInput.len == 0:
    batInput = getEnv("NYMPH_FAKE_BATTERY")

  if batInput.len > 0:
    try:
      let parts = batInput.split(':')
      let pct = min(100.0, max(0.0, parts[0].strip().parseFloat()))
      result.percent = pct
      result.known = true
      if parts.len > 1 and parts[1].strip().toLowerAscii() in ["charging", "1", "true", "yes"]:
        result.isCharging = true
        result.text = $int(round(pct)) & "% (Charging)"
      else:
        result.text = $int(round(pct)) & "%"
      return
    except ValueError:
      discard

  const powerSupplyDir = "/sys/class/power_supply"
  if not dirExists(powerSupplyDir):
    return

  var totalPercent = 0.0
  var batCount = 0
  var anyCharging = false

  try:
    for kind, path in walkDir(powerSupplyDir):
      if kind != pcDir and kind != pcLinkToDir:
        continue
      let dirName = path.splitPath().tail
      let typePath = path / "type"
      var isBattery = dirName.startsWith("BAT") or dirName.startsWith("CMB") or dirName.startsWith("macsmc-battery")
      if fileExists(typePath):
        try:
          if readFile(typePath).strip().toLowerAscii() == "battery":
            isBattery = true
        except IOError:
          discard

      if not isBattery:
        continue

      let capPath = path / "capacity"
      let statusPath = path / "status"
      if fileExists(capPath):
        try:
          let cap = readFile(capPath).strip().parseFloat()
          totalPercent += cap
          inc batCount
          if fileExists(statusPath):
            let st = readFile(statusPath).strip().toLowerAscii()
            if st == "charging":
              anyCharging = true
        except IOError, ValueError:
          discard
  except OSError:
    discard

  if batCount > 0:
    result.percent = totalPercent / batCount.float
    result.isCharging = anyCharging
    result.known = true
    let intPct = int(round(result.percent))
    result.text = if anyCharging: $intPct & "% (Charging)" else: $intPct & "%"

proc getDisk*(): DiskInfo =
  ## Reads root filesystem storage statistics using POSIX statvfs.
  var stats: Statvfs
  if statvfs("/", stats) == 0:
    let total = stats.f_blocks * stats.f_frsize
    let free = stats.f_bfree * stats.f_frsize
    let used = total - free
    result.known = true
    result.percent = if total > 0: min(100.0, max(0.0, used.float / total.float * 100.0)) else: 0.0
    let gibUsed = formatFloat(used.float / bytesPerGib, ffDecimal, 2)
    result.text = fmt"{gibUsed}GiB"
  else:
    result.text = "Unknown disk"

proc getUptime*(): string =
  ## Reads and formats system uptime durations into day and timestamp components.
  var uptime: float
  try:
    let parts = readFile(uptimeFile).splitWhitespace()
    if parts.len == 0:
      return "Unable to read uptime"
    uptime = parseFloat(parts[0])
  except IOError, ValueError:
    return "Unable to read uptime"

  let
    uptimeDays = int(uptime / secsPerDay.float)
    uptimeSeconds = int(uptime.mod(secsPerDay.float))
    hours = uptimeSeconds div 3600
    minutes = (uptimeSeconds mod 3600) div 60
    seconds = uptimeSeconds mod 60

  fmt"{uptimeDays} days, {hours:02d}:{minutes:02d}:{seconds:02d}"

proc getMemory*(): MemoryInfo =
  ## Reads system memory consumption metrics from /proc/meminfo with fallback calculations.
  var memTotal, memAvailable, memFree, memBuffers, memCached, memSReclaimable, memShmem: int

  proc parseMemField(value: string): int =
    let fields = value.strip.splitWhitespace()
    if fields.len > 0:
      try: return fields[0].parseInt()
      except ValueError: discard
    0

  result.text = "Unknown memory"

  if fileExists(meminfoPath):
    for line in lines(meminfoPath):
      let parts = line.split(":")
      if parts.len != 2: continue

      case parts[0].strip()
      of "MemTotal":
        memTotal = parseMemField(parts[1])
      of "MemAvailable":
        memAvailable = parseMemField(parts[1])
      of "MemFree":
        memFree = parseMemField(parts[1])
      of "Buffers":
        memBuffers = parseMemField(parts[1])
      of "Cached":
        memCached = parseMemField(parts[1])
      of "SReclaimable":
        memSReclaimable = parseMemField(parts[1])
      of "Shmem":
        memShmem = parseMemField(parts[1])
      else:
        discard

  if memTotal <= 0:
    return

  if memAvailable <= 0:
    memAvailable = memFree + memBuffers + memCached + memSReclaimable - memShmem

  let usedMem = max(0, memTotal - memAvailable)
  result.usedKiB = usedMem
  result.totalKiB = memTotal
  result.percent = min(100.0, max(0.0, usedMem.float / memTotal.float * 100.0))
  result.known = true

  if usedMem >= 1048576:
    result.text = formatFloat(usedMem.float / gibDivisor, ffDecimal, 2) & "GiB"
  else:
    result.text = intToStr(usedMem div mibDivisor) & "MiB"

proc getDE*(): string =
  ## Resolves the active desktop environment or window manager from environment state.
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

proc collectSnapshot*(overrideBat = ""): SystemSnapshot =
  ## Queries all hardware, software, and runtime metrics to build a complete system snapshot.
  let (u, h) = getTitle()
  result.user = u
  result.hostname = h
  result.os = getOS()
  result.host = getHost()
  result.kernel = getKernel()
  result.cpu = getCPU()
  result.gpu = getGPU()
  result.resolution = getResolution()
  result.desktop = getDE()
  result.audio = getAudio()
  result.shell = getShell()
  result.terminal = getTerminal()
  result.uptime = getUptime()
  result.localip = getLocalIP()
  result.memory = getMemory()
  result.disk = getDisk()
  result.battery = getBattery(overrideBat)
  result.packages = detectPackageSummary()

proc footerLine*(): string =
  ## Constructs the colored footer palette line with configured swatch symbols.
  let palette = [activePalette.rosewater, activePalette.mauve, activePalette.pink, activePalette.maroon, activePalette.sky, activePalette.green, activePalette.lavender]
  var tokens: seq[string] = @[]

  if appConfig.footerIcons.len > 0:
    for raw in appConfig.footerIcons.split(','):
      let t = raw.strip()
      if t.len > 0: tokens.add(t)

  var useTokens = tokens
  if useTokens.len == 0:
    let r = if activeIcons.swatches.len > 0: activeIcons.swatches[rand(activeIcons.swatches.high)] else: "##"
    useTokens.add r

  for i in 0 ..< palette.len:
    let color = palette[i]
    let token = useTokens[i mod useTokens.len]
    if disableColor or color.len == 0:
      result.add token
    else:
      result.add color & token
    result.add " "

  if not disableColor and activePalette.reset.len > 0:
    result.add activePalette.reset

proc levelBar*(percent: float; useSquares: bool; width = 10; reverseColor = false): string =
  ## Renders a progress level bar using configured glyph or ASCII cell characters.
  let filled = int(round(percent / 100.0 * width.float))
  let fillColor = if reverseColor:
                    if percent <= 20.0: activePalette.maroon elif percent <= 60.0: activePalette.yellow else: activePalette.green
                  else:
                    if percent >= 80.0: activePalette.maroon elif percent >= 60.0: activePalette.yellow else: activePalette.green
  let useGlyphBar = activeIconPackName == "nerd" and not disableColor

  var fullCell, emptyCell, openCap, closeCap: string
  if useGlyphBar:
    if useSquares:
      fullCell = "■"
      emptyCell = "□"
    else:
      fullCell = "█"
      emptyCell = "░"
    openCap = ""
    closeCap = ""
  else:
    fullCell = "="
    emptyCell = "-"
    openCap = "["
    closeCap = "]"

  result.add openCap
  if not disableColor and fillColor.len > 0:
    result.add fillColor
  result.add repeat(fullCell, filled)
  if not disableColor and activePalette.reset.len > 0:
    result.add activePalette.reset
  result.add repeat(emptyCell, max(0, width - filled))
  result.add closeCap & " "
  result.add intToStr(int(round(percent))) & "%"

proc formatMemory*(memory: MemoryInfo): string =
  ## Formats memory usage metrics with an inline progress visual bar.
  if not memory.known:
    return memory.text
  levelBar(memory.percent, false) & " " & memory.text

proc formatDisk*(disk: DiskInfo): string =
  ## Formats filesystem disk metrics with an inline square progress bar.
  if not disk.known:
    return disk.text
  levelBar(disk.percent, true) & " " & disk.text

proc formatBattery*(battery: BatteryInfo): string =
  ## Formats battery metrics with status indicators and charging annotations.
  if not battery.known:
    return battery.text
  let bar = levelBar(battery.percent, true, 10, true)
  if battery.isCharging:
    return bar & " (Charging)"
  return bar

proc memoryInfoJson*(memory: MemoryInfo): JsonNode =
  ## Encodes memory metrics into a structured JSON dictionary node.
  result = newJObject()
  result["known"] = %memory.known
  result["used_kib"] = %memory.usedKiB
  result["total_kib"] = %memory.totalKiB
  result["percent"] = %memory.percent

proc statLine*(accent, iconValue, label, value: string): string =
  ## Builds an aligned statistics line with palette styling, glyphs, and labels.
  const labelWidth = 6
  let valuePad = repeat(" ", max(2, labelWidth - label.len + 2))
  fmt"{accent}{iconValue}  {activePalette.yellow}{activePalette.bold}{label}:{activePalette.reset}{valuePad}{value}"

proc buildStatsEntries*(snapshot: SystemSnapshot; modules: seq[ModuleKind]): seq[string] =
  ## Generates rendered text stat lines for all requested active modules.
  for moduleKind in modules:
    var line = ""
    case moduleKind
    of mkTitle:
      let titleLen = max(10, snapshot.user.len + 1 + snapshot.hostname.len)
      let titleHeader = fmt"{activePalette.pink}{activePalette.bold}{snapshot.user}{activePalette.reset}{activePalette.rosewater}@{activePalette.yellow}{activePalette.bold}{snapshot.hostname}{activePalette.reset}"
      let divLine = repeat("─", titleLen)
      let divider = activePalette.lavender & divLine & activePalette.reset
      result.add titleHeader
      result.add divider
      continue
    of mkOS:
      line = statLine(activePalette.rosewater, activeIcons.os, "OS", snapshot.os)
    of mkHost:
      if snapshot.host.len > 0:
        line = statLine(activePalette.mauve, activeIcons.host, "Host", snapshot.host)
    of mkKernel:
      line = statLine(activePalette.pink, activeIcons.kernel, "Kernel", snapshot.kernel)
    of mkCPU:
      if snapshot.cpu.len > 0:
        line = statLine(activePalette.green, activeIcons.cpu, "CPU", snapshot.cpu)
    of mkGPU:
      if snapshot.gpu.len > 0:
        line = statLine(activePalette.sky, activeIcons.gpu, "GPU", snapshot.gpu)
    of mkResolution:
      if snapshot.resolution.len > 0:
        line = statLine(activePalette.mauve, activeIcons.resolution, "Display", snapshot.resolution)
    of mkDesktop:
      line = statLine(activePalette.mauve, activeIcons.desktop, "DE/WM", snapshot.desktop)
    of mkAudio:
      if snapshot.audio.len > 0:
        line = statLine(activePalette.rosewater, activeIcons.audio, "Audio", snapshot.audio)
    of mkPackages:
      line = statLine(activePalette.maroon, activeIcons.pkgs, "Pkgs", formatPackageSummary(snapshot.packages))
    of mkShell:
      line = statLine(activePalette.sky, activeIcons.shell, "Shell", snapshot.shell)
    of mkTerminal:
      line = statLine(activePalette.pink, activeIcons.terminal, "Term", snapshot.terminal)
    of mkUptime:
      line = statLine(activePalette.green, activeIcons.uptime, "Uptime", snapshot.uptime)
    of mkLocalIP:
      if snapshot.localip.len > 0:
        line = statLine(activePalette.lavender, activeIcons.localip, "Local IP", snapshot.localip)
    of mkMemory:
      line = statLine(activePalette.lavender, activeIcons.memory, "Memory", formatMemory(snapshot.memory))
    of mkDisk:
      if snapshot.disk.known:
        line = statLine(activePalette.sky, activeIcons.disk, "Disk", formatDisk(snapshot.disk))
    of mkBattery:
      if snapshot.battery.known:
        let p = snapshot.battery.percent
        let batColor = if p <= 20.0: activePalette.maroon elif p <= 60.0: activePalette.yellow else: activePalette.green
        var icon = activeIcons.battery
        if activeIconPackName == "nerd" and snapshot.battery.isCharging:
          icon = "󰂄"
        line = statLine(batColor, icon, "Batt", formatBattery(snapshot.battery))
    of mkFooter:
      let pad = max(0, appConfig.footerPadding)
      line = repeat(" ", pad) & footerLine()

    if line.len > 0:
      result.add line

proc computeLogoCells*(logo: LogoData): tuple[cols, rows: int] =
  ## Converts image dimensions to terminal column and row cell counts while preserving aspect ratio.
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

proc computeStatsOffset*(): int =
  ## Derives the horizontal column offset for aligning statistics text alongside logos.
  let metrics = getCellMetrics()
  let cw = max(1.0, metrics.cellWidth)
  let colsFromLogo = int(ceil(appConfig.maxLogoWidth.float / cw)) + 2
  let base = max(appConfig.statsOffset, colsFromLogo)
  let maxCols = max(1, terminalWidth())
  min(base, maxCols div 2 + 2)

proc stripAnsi*(text: string): string =
  ## Strips ANSI escape code sequences from text for clean monochrome presentation.
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

proc resolveLogo*(logoOverride: string): tuple[logo: LogoData, name: string, path: string] =
  ## Resolves logo asset binary data from command line overrides, configurations, or auto-detection.
  var overridePath = ""
  if logoOverride.len > 0:
    let candidatePath = normalizeDir(logoOverride)
    if fileExists(candidatePath):
      overridePath = candidatePath

  if overridePath.len > 0:
    result.logo = loadLogoFromPath(overridePath)
    result.path = overridePath
    result.name = overridePath.splitFile.name.toLowerAscii()

  if result.logo.bytes.len == 0 and not result.logo.isText and appConfig.customLogoFile.len > 0:
    let customPath = normalizeDir(appConfig.customLogoFile)
    result.logo = loadLogoFromPath(customPath)
    if result.logo.bytes.len > 0 or result.logo.isText:
      result.path = customPath
      result.name = customPath.splitFile.name.toLowerAscii()

  let detectedLogoName = detectLogoName(if overridePath.len == 0: logoOverride else: "")
  if result.logo.bytes.len == 0 and not result.logo.isText:
    result.logo = loadLogo(detectedLogoName)
    if result.logo.bytes.len > 0:
      result.name = detectedLogoName
      result.path = locateLogoFile(detectedLogoName, ".png")

  if result.logo.bytes.len == 0 and not result.logo.isText:
    result.logo = loadLogo(DefaultLogoName)
    if result.logo.bytes.len > 0:
      result.name = DefaultLogoName
      result.path = locateLogoFile(DefaultLogoName, ".png")

  if result.name.len == 0:
    result.name = DefaultLogoName

proc printHelp*() =
  ## Displays command line usage instructions and flag options.
  echo "Nymph - lightweight system summary"
  echo ""
  echo "Usage: nymph [options]"
  echo "  --logo <name|path>        Override logo by name or PNG path"
  echo "  --battery <pct[:status]>  Override battery percentage (e.g. 85 or 85:charging)"
  echo "  --no-color                Disable ANSI colors"
  echo "  --json                    Print machine-readable JSON"
  echo "  --doctor                  Print diagnostics and exit"
  echo "  --theme <name>            Theme: catppuccin, nord, gruvbox, plain"
  echo "  --icon-pack <name>        Icon pack: nerd, ascii, mono"
  echo "  --layout <name>           Layout: full, compact, minimal"
  echo "  --modules <csv>           Explicit modules (title,os,cpu,gpu,packages,...)"
  echo "  --list-themes             List built-in themes"
  echo "  --list-icon-packs         List built-in icon packs"
  echo "  -h, --help                Show this help"

proc printThemeList*() =
  ## Lists built-in theme presets available to the user.
  echo "Themes: catppuccin, nord, gruvbox, plain"

proc printIconPackList*() =
  ## Lists built-in icon pack presets available to the user.
  echo "Icon packs: nerd, ascii, mono"

proc doctorOutput*(snapshot: SystemSnapshot; modules: seq[ModuleKind]; logoInfo: tuple[logo: LogoData, name: string, path: string]; proto: GraphicsProtocol; jsonEnabled: bool) =
  ## Prints detailed system, configuration, and terminal diagnostics for debugging.
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
  echo "terminal.graphicsProtocol: " & $proto
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

proc outputJson*(snapshot: SystemSnapshot; modules: seq[ModuleKind]; logoInfo: tuple[logo: LogoData, name: string, path: string]; proto: GraphicsProtocol) =
  ## Outputs gathered metrics as formatted JSON for external scripting integration.
  var root = newJObject()
  root["user"] = %snapshot.user
  root["hostname"] = %snapshot.hostname
  root["os"] = %snapshot.os
  root["host"] = %snapshot.host
  root["kernel"] = %snapshot.kernel
  root["cpu"] = %snapshot.cpu
  root["gpu"] = %snapshot.gpu
  root["resolution"] = %snapshot.resolution
  root["desktop"] = %snapshot.desktop
  root["audio"] = %snapshot.audio
  root["shell"] = %snapshot.shell
  root["terminal"] = %snapshot.terminal
  root["uptime"] = %snapshot.uptime
  root["local_ip"] = %snapshot.localip
  root["memory"] = %snapshot.memory.text

  if snapshot.disk.known:
    root["disk"] = %snapshot.disk.text
    var diskNode = newJObject()
    diskNode["known"] = %true
    diskNode["percent"] = %snapshot.disk.percent
    root["disk_info"] = diskNode

  if snapshot.battery.known:
    root["battery"] = %snapshot.battery.text
  root["memory_info"] = memoryInfoJson(snapshot.memory)
  root["packages"] = packageSummaryJson(snapshot.packages)
  root["theme"] = %activeThemeName
  root["icon_pack"] = %activeIconPackName
  root["layout"] = %activeLayoutName
  root["modules"] = %modulesAsNames(modules)
  root["no_color"] = %disableColor
  root["graphics_protocol"] = % $proto

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
  let graphicsProto = detectGraphicsProtocol()
  let snapshot = collectSnapshot(cli.battery)

  if cli.doctor:
    doctorOutput(snapshot, modules, logoInfo, graphicsProto, jsonEnabled)
    quit(0)

  if jsonEnabled:
    outputJson(snapshot, modules, logoInfo, graphicsProto)
    quit(0)

  let statsCol = computeStatsOffset()
  let stats = buildStatsEntries(snapshot, modules)

  let renderImage = graphicsProto != gpNone and logoInfo.logo.bytes.len > 0
  var logoLines: seq[string] = @[]
  var logoRows = 0
  var placement: tuple[cols, rows: int]

  if renderImage:
    placement = computeLogoCells(logoInfo.logo)
    logoRows = placement.rows
  else:
    if logoInfo.logo.isText and logoInfo.logo.textLines.len > 0:
      logoLines = logoInfo.logo.textLines
    else:
      logoLines = AsciiFallbackLogo.split("\n")

    while logoLines.len > 0 and logoLines[^1] == "":
      logoLines.del(logoLines.high)
    logoRows = logoLines.len

  let totalRows = max(logoRows, stats.len)

  if renderImage:
    for i in 0 ..< totalRows: stdout.write("\n")
    if totalRows > 0: cursorUp(totalRows)

    if graphicsProto == gpKitty:
      displayKittyGraphics(logoInfo.logo.bytes, placement.cols, placement.rows)
    elif graphicsProto == gpIterm:
      displayItermGraphics(logoInfo.logo.bytes, placement.cols, placement.rows)

    for i in 0 ..< totalRows:
      if i < stats.len:
        setCursorXPos(statsCol)
        stdout.write(if disableColor: stripAnsi(stats[i]) else: stats[i])
      stdout.write("\n")
  else:
    for i in 0 ..< totalRows:
      var lineStr = ""
      if i < logoLines.len:
        let rawLine = logoLines[i]
        lineStr = if disableColor or activePalette.pink.len == 0: rawLine else: activePalette.pink & rawLine & activePalette.reset

      let lineLen = if i < logoLines.len: logoLines[i].len else: 0
      let padLen = max(0, statsCol - 1 - lineLen)
      lineStr &= repeat(" ", padLen)

      if i < stats.len:
        lineStr &= (if disableColor: stripAnsi(stats[i]) else: stats[i])

      stdout.write(lineStr & "\n")

  stdout.write("\n")
  stdout.flushFile()
