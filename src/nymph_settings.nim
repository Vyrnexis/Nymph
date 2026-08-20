## Configuration loading, INI parsing, and XDG directory management for Nymph.
import std/[os, strutils, parsecfg]

type
  RuntimeConfig* = object
    ## Global configuration object loaded from disk or default presets.
    maxLogoWidth*: int        ## Maximum rendered logo width in terminal cells.
    statsOffset*: int         ## Starting horizontal column for stats text.
    configLogoDir*: string    ## User logo search directory path.
    customLogoFile*: string   ## Explicit override logo file path.
    noColor*: bool            ## True if ANSI color output is disabled.
    theme*: string            ## Active theme name.
    iconPack*: string         ## Active icon pack name.
    layout*: string           ## Active layout name.
    modules*: seq[string]     ## Ordered list of module names to display.
    jsonOutput*: bool         ## True if machine-readable JSON output is requested.
    loadedConfigPath*: string ## Filesystem path of the loaded configuration file.
    footerIcons*: string      ## Custom footer block symbol string.
    footerPadding*: int       ## Left-padding offset for the footer blocks.

const
  DefaultMaxLogoWidth* = 200      ## Default upper bound for logo width in pixels.
  DefaultStatsOffsetBase* = 22    ## Default horizontal margin between logo and stats.

proc normalizeDir*(path: string): string =
  ## Expands home directory tildes and resolves absolute directory paths.
  if path.len == 0:
    return ""
  var expanded = path
  if expanded[0] == '~':
    let home = getHomeDir()
    if home.len > 0:
      if expanded.len == 1:
        expanded = home
      else:
        var suffix = expanded[1 .. expanded.high]
        if suffix.len > 0 and (suffix[0] == DirSep or suffix[0] == '/'):
          suffix = if suffix.len > 1: suffix[1 .. suffix.high] else: ""
        expanded = home / suffix
  if isAbsolute(expanded): expanded else: absolutePath(expanded)

proc defaultConfig*(): RuntimeConfig =
  ## Constructs a default RuntimeConfig record initialized with standard presets.
  RuntimeConfig(
    maxLogoWidth: DefaultMaxLogoWidth,
    statsOffset: DefaultStatsOffsetBase,
    configLogoDir: "",
    customLogoFile: "",
    noColor: false,
    theme: "catppuccin",
    iconPack: "nerd",
    layout: "full",
    modules: @[],
    jsonOutput: false,
    loadedConfigPath: "",
    footerIcons: "",
    footerPadding: 7
  )

proc getDefaultConfigDir(): string =
  ## Resolves the base configuration directory adhering to XDG specifications.
  let xdg = getEnv("XDG_CONFIG_HOME")
  if xdg.len > 0:
    normalizeDir(xdg / "nymph")
  else:
    normalizeDir(getHomeDir() / ".config" / "nymph")

proc configPaths(): seq[string] =
  ## Assembles the ordered search paths for configuration files.
  let envCfg = getEnv("NYMPH_CONFIG")
  if envCfg.len > 0:
    result.add normalizeDir(envCfg)
  result.add normalizeDir(getDefaultConfigDir() / "config.conf")
  result.add "/etc/xdg/nymph/config.conf"

proc loadConfig*(): RuntimeConfig =
  ## Loads application settings from configuration files or provisions defaults if missing.
  result = defaultConfig()
  var found = false

  for path in configPaths():
    if not fileExists(path):
      continue
    try:
      let dict = loadConfig(path)
      let maxwidth = dict.getSectionValue("", "maxwidth")
      if maxwidth.len > 0:
        try: result.maxLogoWidth = maxwidth.parseInt()
        except ValueError: discard

      let statsoffset = dict.getSectionValue("", "statsoffset")
      if statsoffset.len > 0:
        try: result.statsOffset = statsoffset.parseInt()
        except ValueError: discard

      let customlogo = dict.getSectionValue("", "customlogo")
      if customlogo.len > 0: result.customLogoFile = customlogo

      let nocolor = dict.getSectionValue("", "nocolor")
      if nocolor.len > 0: result.noColor = nocolor.toLowerAscii() in ["1", "true", "yes", "on"]

      let theme = dict.getSectionValue("", "theme")
      if theme.len > 0: result.theme = theme.toLowerAscii()

      let iconpack = dict.getSectionValue("", "iconpack")
      if iconpack.len > 0: result.iconPack = iconpack.toLowerAscii()

      let layout = dict.getSectionValue("", "layout")
      if layout.len > 0: result.layout = layout.toLowerAscii()

      let modules = dict.getSectionValue("", "modules")
      if modules.len > 0:
        result.modules = @[]
        for rawMod in modules.split(','):
          let modName = rawMod.strip().toLowerAscii()
          if modName.len > 0: result.modules.add modName

      let jsonOutput = dict.getSectionValue("", "json")
      if jsonOutput.len > 0: result.jsonOutput = jsonOutput.toLowerAscii() in ["1", "true", "yes", "on"]

      let footerIcons = dict.getSectionValue("", "footericons")
      if footerIcons.len > 0: result.footerIcons = footerIcons

      let footerPadding = dict.getSectionValue("", "footerpadding")
      if footerPadding.len > 0:
        try: result.footerPadding = footerPadding.parseInt()
        except ValueError: discard

      result.loadedConfigPath = path
      found = true
      break
    except IOError, Exception:
      discard

  let baseDir = getDefaultConfigDir()
  let logoDir = baseDir / "logos"
  try:
    if not dirExists(baseDir): createDir(baseDir)
    if not dirExists(logoDir): createDir(logoDir)
    if dirExists(logoDir): result.configLogoDir = logoDir
  except IOError, OSError:
    discard

  if not found:
    let path = baseDir / "config.conf"
    result.loadedConfigPath = path
    try:
      if not fileExists(path):
        let content = "# Nymph configuration\n" &
                      "maxwidth = " & $result.maxLogoWidth & "\n" &
                      "statsoffset = " & $result.statsOffset & "\n" &
                      "theme = " & result.theme & "\n" &
                      "iconpack = " & result.iconPack & "\n" &
                      "layout = " & result.layout & "\n" &
                      "modules = \"title,os,host,kernel,cpu,gpu,resolution,desktop,audio,terminal,shell,packages,uptime,localip,memory,disk,battery,footer\"\n" &
                      "json = false\n" &
                      "nocolor = false\n" &
                      "customlogo = \"\"\n" &
                      "footericons = \"\"\n" &
                      "footerpadding = 7\n"
        writeFile(path, content)
    except IOError:
      discard
