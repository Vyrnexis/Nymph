import std/[os, strutils, parsecfg]

type
  RuntimeConfig* = object
    maxLogoWidth*: int
    statsOffset*: int
    configLogoDir*: string
    customLogoFile*: string
    noColor*: bool
    theme*: string
    iconPack*: string
    layout*: string
    modules*: seq[string]
    jsonOutput*: bool
    loadedConfigPath*: string
    footerIcons*: string
    footerPadding*: int

const
  DefaultMaxLogoWidth* = 200
  DefaultStatsOffsetBase* = 22

proc normalizeDir*(path: string): string =
  if path.len == 0:
    return ""
  var expanded = path
  if expanded[0] == '~':
    let home = getHomeDir()
    if home.len > 0:
      if expanded.len == 1: expanded = home
      else:
        var suffix = expanded[1 .. expanded.high]
        if suffix.len > 0 and (suffix[0] == DirSep or suffix[0] == '/'):
          if suffix.len > 1: suffix = suffix[1 .. suffix.high]
          else: suffix = ""
        expanded = home / suffix
  if isAbsolute(expanded): expanded else: absolutePath(expanded)

proc defaultConfig*(): RuntimeConfig =
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

proc configPaths(): seq[string] =
  let envCfg = getEnv("NYMPH_CONFIG")
  if envCfg.len > 0: result.add envCfg
  let xdg = getEnv("XDG_CONFIG_HOME")
  if xdg.len > 0: result.add normalizeDir(xdg / "nymph" / "config.conf")
  else: result.add normalizeDir(getHomeDir() / ".config" / "nymph" / "config.conf")
  result.add "/etc/xdg/nymph/config.conf"

proc loadConfig*(): RuntimeConfig =
  result = defaultConfig()
  var found = false

  for path in configPaths():
    if not fileExists(path): continue
    try:
      let dict = loadConfig(path)
      # In parsecfg, values with commas must be quoted.
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
      break # Stop after finding the first valid config file
    except IOError, Exception:
      discard

  let homeCfg = normalizeDir(getHomeDir() / ".config" / "nymph")
  if not found:
    try:
      if not dirExists(homeCfg): createDir(homeCfg)
      let logoDir = homeCfg / "logos"
      if not dirExists(logoDir): createDir(logoDir)
      result.configLogoDir = logoDir
      let path = homeCfg / "config.conf"
      result.loadedConfigPath = path
      if not fileExists(path):
        let content = "# Nymph configuration\n" &
                      "maxwidth = " & $result.maxLogoWidth & "\n" &
                      "statsoffset = " & $result.statsOffset & "\n" &
                      "theme = " & result.theme & "\n" &
                      "iconpack = " & result.iconPack & "\n" &
                      "layout = " & result.layout & "\n" &
                      "modules = \"os,kernel,desktop,packages,shell,uptime,memory,colours\"\n" &
                      "json = false\n" &
                      "nocolor = false\n" &
                      "customlogo = \"\"\n" &
                      "footericons = \"\"\n" &
                      "footerpadding = 7\n"
        writeFile(path, content)
    except IOError:
      discard
  else:
    try:
      let logoDir = homeCfg / "logos"
      if not dirExists(logoDir): createDir(logoDir)
      if dirExists(logoDir): result.configLogoDir = logoDir
      if result.loadedConfigPath.len == 0:
        result.loadedConfigPath = homeCfg / "config.conf"
    except IOError:
      discard
