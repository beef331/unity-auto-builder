import os,
      osproc,
      strformat,
      strutils,
      times,
      terminal,
      buildobj,
      zippy/[tarballs, ziparchives]
import githubuploader, googleuploader

if(paramCount() < 1):
  quit "Please supply a path to the config you wish to use"

proc getConfigPath(a: string): string =
  if(a.isAbsolute): result = a
  else: result = getCurrentDir() & DirSep & a

let configPath = getConfigPath(paramStr(1))

var
  building = false

if(not fileExists(configPath)):
  quit(fmt"Config File not found at {configPath}")

proc colourPrint(s: string, fg: ForegroundColor) = echo ansiForegroundColorCode(fg) & s & ansiResetCode

proc successWrite(s: string) = s.colourPrint(fgGreen)

proc errorWrite(s: string) = s.colourPrint(fgRed)

proc warnWrite(s: string) = s.colourPrint(fgYellow)

proc saveState(obj: BuildObj) =
  var file = open(fmt"last-run-{obj.branch}.txt", fmWrite)
  file.write(obj.lastCommitBuilt)
  file.close()

proc loadState(obj: var BuildObj) =
  if(fileExists(fmt"last-run-{obj.branch}.txt")):
    let
      file = open(fmt"last-run-{obj.branch}.txt", fmRead)
    obj.lastCommitBuilt = file.readLine()
    file.close()

proc resyncBuildFiles(obj: BuildObj) =
  discard execShellCmd(fmt"git -C ./{obj.branch} fetch origin")
  discard execShellCmd(fmt"git -C ./{obj.branch} reset --hard origin/master")
  discard execShellCmd(fmt"git -C ./{obj.branch} pull")
  template notExists(s: string): untyped =
    not fileExists(s) and not dirExists(s) and not symlinkExists(s)
  let projectPath = fmt"{obj.branch}/{obj.subPath}"
  for platform in obj.platforms:
    let path = fmt"{$platform}/{obj.branch}/{obj.subPath}"
    for dir in path.parentDirs(fromRoot = true):
      discard existsOrCreateDir(dir)
    for dir in walkDir(projectPath):
      let
        absDirPath = fmt"{getCurrentDir()}/{dir.path}"
        name = dir.path.splitPath().tail
        absSymPath = getCurrentDir() / path / name
      if name == "Packages":
        if dirExists(absSymPath): removeDir(absSymPath)
        copyDirWithPermissions(absDirPath, absSymPath)
      if name == "Assets":
        discard existsOrCreateDir(absSymPath)
        for path in walkDir(absDirPath):
          let symDir = fmt"{getCurrentDir()}/{$platform}/{obj.branch}/{obj.subPath}/Assets/{path.path.splitPath().tail}"
          if absSymPath.notExists: createSymlink(path.path, symDir)
      elif absSymPath.notExists:
        createSymlink(absDirPath, absSymPath)

proc cloneBuild(obj: BuildObj) =
  ##Clones repo
  let pathName = obj.branch
  if(not dirExists(pathName)):
    discard execShellCmd(fmt"git clone -b {obj.branch} {obj.repo} {obj.branch}")
    if(not dirExists(obj.branch)): quit "Repo not accessible or incorrect"
    resyncBuildFiles(obj)

proc buildProjects(obj: BuildObj) =
  ## Build each platform async to build many at once
  obj.resyncBuildFiles()
  var time = now().format("yyyy-MM-dd   HH:mmtt")
  echo fmt"{time} Starting to build {obj.branch} {obj.platforms}"
  building = true
  for preBuild in obj.preBuild:
    discard execShellCmd(fmt"{preBuild} {configPath} {obj.branch}")
  let startTime = getTime()
  var
    buildCommands: seq[string]
    built: seq[BuildPlatforms]
  let buildCommand = fmt"{obj.unityPath} -batchmode -nographics -quit -accept-apiupdate "
  if(obj.platforms.contains(bpWin)):
    built.add bpWin
    buildCommands.add(buildCommand &
            fmt"-projectPath '{bpWin}/{obj.branch}/{obj.subPath}' -buildTarget win64 -buildWindows64Player {getCurrentDir()}/win-build/{obj.branch}/{obj.name}.exe -logFile {getCurrentDir()}/win-{obj.branch}.log")
  if(obj.platforms.contains(bpLinux)):
    built.add bpLinux
    buildCommands.add(buildCommand &
            fmt"-projectPath '{bpLinux}/{obj.branch}/{obj.subPath}' -buildTarget linux64 -buildLinux64Player {getCurrentDir()}/linux-build/{obj.branch}/{obj.name}.x86_64 -logFile {getCurrentDir()}/linux-{obj.branch}.log")
  if(obj.platforms.contains(bpMac)):
    built.add bpMac
    buildCommands.add(buildCommand &
            fmt"-projectPath '{bpMac}/{obj.branch}/{obj.subPath}' -buildTarget mac -buildOSXUniversalPlayer {getCurrentDir()}/mac-build/{obj.branch}/{obj.name}.dmg -logFile {getCurrentDir()}/mac-{obj.branch}.log")
  var
    githubUrl = ""
  discard execProcesses(buildCommands, {}, afterRunEvent = proc(id: int, p: Process) =
    if p.peekExitCode == 0:
      let
        platform = built[id]
        (folderPath, archivePath) = case platform:
        of bpWin: (fmt"win-build/{obj.branch}/", fmt"win-build/{obj.branch}{ArchiveExt[platform]}")
        of bpLinux: (fmt"linux-build/{obj.branch}/",
            fmt"linux-build/{obj.branch}{ArchiveExt[platform]}")
        of bpMac: (fmt"mac-build/{obj.branch}/", fmt"mac-build/{obj.branch}{ArchiveExt[platform]}")
        else: ("", "")
        logPath = case platform:
        of bpWin: fmt"{getCurrentDir()}/win-{obj.branch}.log"
        of bpLinux: fmt"{getCurrentDir()}/linux-{obj.branch}.log"
        of bpMac: fmt"{getCurrentDir()}/mac-{obj.branch}.log"
        else: ""
      successWrite fmt"{platform} build finished."
      if dirExists(folderPath):
        discard tryRemoveFile(archivePath)
        echo "Creating archive for ", platform, "\n"
        case platform:
        of {bpMac, bpLinux}:
          try:
            createTarball(folderPath, archivePath)
          except ZippyError as e:
            echo e.msg
        else:
          createZipArchive(folderPath, archivePath)
        if fileExists archivePath:
          uploadGithub(archivePath, logPath, obj, platform, githubUrl)
          uploadGoogle(archivePath, logPath, obj, platform)
    else:
      errorWrite fmt"{built[id]} build failed."
  )
  let delta = (getTime() - startTime)
  time = now().format("yyyy-MM-dd   HH:mmtt")
  echo &"{time}\nBuilds finished \n"
  echo fmt"Commit: {obj.lastCommitBuilt}"
  echo &"Elapsed Time:{delta.inSeconds} seconds\n"
  for postBuild in obj.postBuild:
    echo "Running post build scripts"
    discard execShellCmd(fmt"{postBuild} {configPath} {obj.branch}")
  building = false

proc getSha(obj: BuildObj): string =
  discard execCmd(fmt"git -C ./{obj.branch} fetch --all >> /dev/null && git -C ./{obj.branch} reset --hard origin/{obj.branch} >> /dev/null")
  discard execCmd(fmt"git -C ./{obj.branch} pull >> /dev/null")
  result = execCmdEx(fmt"git -C ./{obj.branch} log -1 --format=%H").output.strip()

setCurrentDir(configPath.splitPath().head)

proc watchLogic(build: BuildObj) =
  var build = build
  build.loadState()
  var steps = 0
  echo "Last built commit, ", build.lastCommitBuilt, "\n"
  build.cloneBuild()
  while true:
    cursorUp()
    eraseLine()
    echo "Watching for a commit." & repeat('.', steps.mod(3))
    let sha = build.getSha()
    if(sha != build.lastCommitBuilt):
      build.lastCommitBuilt = sha
      buildProjects(build)
      build.saveState()
      steps = 0
    inc steps
    sleep(10000)
var build = parseConfig(configPath)

echo "Auto Builder Initalized"
build.watchLogic
