import os,
      osproc,
      strformat,
      strutils,
      times,
      terminal,
      buildobj,
      strscans,
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

proc getLastBuild(obj: BuildObj): string =
  if(fileExists(fmt"last-run-{obj.branch}.txt")):
    result = readFile(fmt"last-run-{obj.branch}.txt")

proc resyncBuildFiles(obj: BuildObj) =
  let dir = getCurrentDir() / obj.branch
  discard execShellCmd(fmt"git -C {dir} fetch origin")
  discard execShellCmd(fmt"git -C {dir} reset --hard origin/{obj.branch}")
  discard execShellCmd(fmt"git -C {dir} pull")
  proc removePath(s: string, kind: PathComponent) =
    if not s.symlinkExists:
      if fileExists(s):
        removeFile(s)
      elif dirExists(s):
        removeDir(s)

  let projectPath = fmt"{obj.branch}/{obj.subPath}"
  for platform in obj.platforms:
    let path = fmt"{$platform}/{obj.branch}/{obj.subPath}"
    if obj.symlinked:
      for dir in path.parentDirs(fromRoot = true):
        discard existsOrCreateDir(dir)
      for dir in walkDir(projectPath):
        let
          absDirPath = fmt"{getCurrentDir()}/{dir.path}"
          name = dir.path.splitPath().tail
          absSymPath = getCurrentDir() / path / name
        if name == "Packages":
          removePath(absSymPath, dir.kind)
          copyDir(absDirPath, absSymPath)
        if name == "Assets":
          discard existsOrCreateDir(absSymPath)
          for path in walkDir(absDirPath):
            let symDir = absSymPath / path.path.splitPath().tail
            removePath(symDir, path.kind)
            if not symDir.symlinkExists:
              createSymlink(path.path, symDir)
        else:
          absSymPath.removePath dir.kind
          if not absSymPath.symlinkExists:
            createSymlink(absDirPath, absSymPath)
    else:
      template proj(s: string): untyped = projectPath / s
      template dest(s: string): untyped = path / s
      let
        srcAssets = proj "Assets"
        srcPackages = proj "Packages"
        srcSettings = proj "ProjectSettings"
        destAssets = dest "Assets"
        destPackages = dest "Packages"
        destSettings = dest "ProjectSettings"
      try:
        removeDir(destAssets)
        removeDir(destPackages)
        removeDir(destSettings)
      except: discard
      copyDirWithPermissions(srcAssets, destAssets)
      copyDirWithPermissions(srcPackages, destPackages)
      copyDirWithPermissions(srcSettings, destSettings)

proc cloneBuild(obj: BuildObj) =
  ##Clones repo
  let pathName = obj.branch
  if(not dirExists(pathName)):
    discard execShellCmd(fmt"git clone -b {obj.branch} {obj.repo} {obj.branch}")
    for plat in obj.platforms:
      let dir = $obj.branch / $plat
      removedir(dir)
    if(not dirExists(obj.branch)): quit "Repo not accessible or incorrect"
    resyncBuildFiles(obj)

when defined linux:
  import posix

proc cleanupAllProcesses(s: string) =
  when defined linux:
    for dir in walkDir("/proc"):
      var pid: int
      if dir.path.scanf("/proc/$i", pid):
        let cmdLine = dir.path / "cmdline"
        if cmdLine.fileExists:
          if s == cmdLine:
            discard kill(pid.Pid, SigKill)


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
    cleanUpAllProcesses(buildCommands[id])
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
  const nulPath =
    when defined(windows):
      "NUL"
    else:
      "/dev/null"
  let dir = getCurrentDir() / obj.branch
  discard execCmd(fmt"git -C {dir} fetch --all >> {nulPath} && git -C {dir} reset --hard origin/{obj.branch} >> {nulPath}")
  discard execCmd(fmt"git -C {dir} pull >> {nulPath}")
  result = execCmdEx(fmt"git -C {dir} log -1 --format=%H").output.strip()

setCurrentDir(configPath.splitPath().head)

proc watchLogic(build: BuildObj) =
  var build = build
  var steps = 0
  echo "Last built commit, ", build.lastCommitBuilt, "\n"
  build.cloneBuild()
  while true:
    cursorUp()
    eraseLine()
    echo "Watching for a commit." & repeat('.', steps.mod(3))
    let sha = build.getSha()
    if(sha != build.getLastBuild()):
      build.lastCommitBuilt = sha
      buildProjects(build)
      build.saveState()
      steps = 0
    inc steps
    sleep(10000)
var build = parseConfig(configPath)

echo "Auto Builder Initalized"
build.watchLogic
