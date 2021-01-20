import os,
      osproc,
      json,
      strformat,
      strutils,
      times,
      locks,
      terminal,
      buildobj,
      zippy/[tarballs, ziparchives],
      asyncdispatch
import githubuploader, googleuploader

if(paramCount() < 1):
  quit "Please supply a path to the config you wish to use"

proc getConfigPath(a: string): string =
  if(a.isAbsolute): result = a
  else: result = getCurrentDir() & DirSep & a


let configPath = getConfigPath(paramStr(1))

var
  building = 0
  buildThreads: seq[Thread[BuildObj]]
  threadConfPath{.threadvar.}: string
  googleQueue: seq[(string, string, BuildObj, BuildPlatforms)]
  L: Lock
initLock(L)

if(not fileExists(configPath)):
  quit(fmt"Config File not found at {configPath}")

proc saveState(obj: BuildObj) =
  acquire L
  var file = open(fmt"lastRun{obj.branch}.txt", fmWrite)
  file.writeLine(obj.lastCommitBuilt)
  file.close()
  release L

proc loadState(obj: var BuildObj) =
  if(fileExists(fmt"last-run-{obj.branch}.txt")):
    let
      file = open(fmt"last-run-{obj.branch}.txt", fmRead)
    obj.lastCommitBuilt = file.readLine()
    file.close()
  saveState(obj)


proc buildingMessage() =
  let startTime = getTime()
  var tick = 0
  let buildAnim = ["⢀⠀",
               "⡀⠀",
               "⠄⠀",
               "⢂⠀",
               "⡂⠀",
               "⠅⠀",
               "⢃⠀",
               "⡃⠀",
               "⠍⠀",
               "⢋⠀",
               "⡋⠀",
               "⠍⠁",
               "⢋⠁",
               "⡋⠁",
               "⠍⠉",
               "⠋⠉",
               "⠋⠉",
               "⠉⠙",
               "⠉⠙",
               "⠉⠩",
               "⠈⢙",
               "⠈⡙",
               "⢈⠩",
               "⡀⢙",
               "⠄⡙",
               "⢂⠩",
               "⡂⢘",
               "⠅⡘",
               "⢃⠨",
               "⡃⢐",
               "⠍⡐",
               "⢋⠠",
               "⡋⢀",
               "⠍⡁",
               "⢋⠁",
               "⡋⠁",
               "⠍⠉",
               "⠋⠉",
               "⠋⠉",
               "⠉⠙",
               "⠉⠙",
               "⠉⠩",
               "⠈⢙",
               "⠈⡙",
               "⠈⠩",
               "⠀⢙",
               "⠀⡙",
               "⠀⠩",
               "⠀⢘",
               "⠀⡘",
               "⠀⠨",
               "⠀⢐",
               "⠀⡐",
               "⠀⠠",
               "⠀⢀",
               "⠀⡀"]
  while(building > 0):
    sleep(60)
    let delta = (getTime() - startTime)
    withLock(L):
      eraseLine(stdout)
      echo fmt"{buildAnim[tick]} Building {building} branches. Time Elapsed: {delta.inSeconds}"
      cursorUp(stdout, 1)
      tick = (tick + 1 + buildAnim.len).mod(buildAnim.len)

proc commitMessage(){.thread.} =
  let waitingAnim = ["", ".", "..", "...", ".. .", ". ..", " ..."]
  var tick = 0
  while(building <= 0):
    sleep(120)
    withlock(L):
      eraseLine(stdout)
      echo fmt"Watching for commits {waitingAnim[tick]}"
      cursorUp(stdout, 1)
      tick = (tick + 1 + waitingAnim.len).mod(waitingAnim.len)

proc uploadGoogle(){.async.} =
  echo &"\n\n{googleQueue}\n\n"
  for (arch, log, build, plat) in googleQueue:
    await uploadGoogle(arch, log, build, plat)
  googleQueue.setLen(0)

proc resyncBuildFiles(obj: BuildObj) =
  discard execShellCmd(fmt"git -C ./{obj.branch} pull")

  for platform in obj.platforms:
    discard existsOrCreateDir($platform)
    discard existsOrCreateDir(fmt"{$platform}/{obj.branch}")
    discard existsOrCreateDir(fmt"{$platform}/{obj.branch}/{obj.subPath}")
    for dir in walkDir(obj.branch & DirSep & obj.subPath):
      let
        absDirPath = fmt"{getCurrentDir()}/{dir.path}"
        name = dir.path.splitPath().tail
        absSymPath = fmt"{getCurrentDir()}/{$platform}/{obj.branch}/{obj.subPath}/{name}"
      if name == "Packages":
        if dirExists(absSymPath): removeDir(absSymPath)
        copyDirWithPermissions(absDirPath, absSymPath)
      if name == "Assets":
        discard existsOrCreateDir(absSymPath)
        for path in walkDir(absDirPath):
          let symDir = fmt"{getCurrentDir()}/{$platform}/{obj.branch}/{obj.subPath}/Assets/{path.path.splitPath().tail}"
          if not fileExists(symDir) and not dirExists(symDir): createSymlink(path.path, symDir)
      elif not fileExists(absSymPath) and not dirExists(absSymPath):
        createSymlink(absDirPath, absSymPath)

proc cloneBuild(obj: BuildObj) =
  ##Clones repo
  let pathName = obj.branch
  if(not dirExists(pathName)):
    discard execShellCmd(fmt"git clone -b {obj.branch} {obj.repo} {obj.branch}")
    if(not dirExists(obj.branch)): quit "Repo not accessible or incorrect"
    resyncBuildFiles(obj)

proc buildProjects(obj: BuildObj){.thread.} =
  ##Build each platform async to build many at once
  obj.resyncBuildFiles()
  {.cast(gcsafe).}:#Copies from global
    deepCopy(threadConfPath, configPath)

  var time = now().format("yyyy-MM-dd   HH:mmtt")
  withLock(L):
    echo fmt"{time} Attempting to build {obj.branch} {obj.platforms}"
  inc building
  for preBuild in obj.preBuild:
    discard execShellCmd(fmt"{preBuild} {threadConfPath} {obj.branch}")
  try:
    let startTime = getTime()
    var 
      buildCommands: seq[string]
      built: seq[BuildPlatforms]
    let buildCommand = fmt"{obj.unityPath} -batchmode -nographics -quit -accept-apiupdate "
    if(obj.platforms.contains(bpWin)):
      built.add bpWin
      buildCommands.add(buildCommand &
              fmt"-projectPath 'bpWin/{obj.branch}/{obj.subPath}' -buildTarget win64 -buildWindows64Player {getCurrentDir()}/win-build/{obj.branch}/{obj.name}.exe -logFile {getCurrentDir()}/win-{obj.branch}.log")
    if(obj.platforms.contains(bpLinux)):
      built.add bpLinux
      buildCommands.add(buildCommand &
              fmt"-projectPath 'bpLinux/{obj.branch}/{obj.subPath}' -buildTarget linux64 -buildLinux64Player {getCurrentDir()}/linux-build/{obj.branch}/{obj.name}.x86_64 -logFile {getCurrentDir()}/linux-{obj.branch}.log")
    if(obj.platforms.contains(bpMac)):
      built.add bpMac
      buildCommands.add(buildCommand &
              fmt"-projectPath 'bpMac/{obj.branch}/{obj.subPath}' -buildTarget mac -buildOSXUniversalPlayer {getCurrentDir()}/mac-build/{obj.branch}/{obj.name}.dmg -logFile {getCurrentDir()}/mac-{obj.branch}.log")
    var githubUrl = ""
    discard execProcesses(buildCommands, {}, afterRunEvent = proc(id: int, _: Process) =
      let 
        platform = built[id]
        (folderPath, archivePath) = case platform:
        of bpWin: (fmt"win-build/{obj.branch}/", fmt"win-build/{obj.branch}.zip")
        of bpLinux: (fmt"linux-build/{obj.branch}/", fmt"linux-build/{obj.branch}.tar.gz")
        of bpMac: (fmt"mac-build/{obj.branch}/", fmt"mac-build/{obj.branch}.tar.gz")
        else: ("", "")
        logPath = case platform:
        of bpWin: fmt"{getCurrentDir()}/win-{obj.branch}.log"
        of bpLinux: fmt"{getCurrentDir()}/linux-{obj.branch}.log"
        of bpMac: fmt"{getCurrentDir()}/mac-{obj.branch}.log"
        else: ""
      if dirExists(folderPath):
        case platform:
        of {bpMac, bpLinux}:
          createTarball(folderPath, archivePath)
        else:
          createZipArchive(folderPath, archivePath)
 
      if obj.buildinfo["github"].len > 0:
        uploadGithub(archivePath, logPath, obj, platform, githubUrl)
      if obj.buildinfo["google-storage"].len > 0:
        {.cast(gcsafe).}:
          withLock(L):
            googleQueue.add (archivePath, logPath, obj, platform)
    )
    let delta = (getTime() - startTime)
    time = now().format("yyyy-MM-dd   HH:mmtt")
    withLock(L):
      echo &"{time}\nBuilds finished \n"
      echo fmt"Commit: {obj.lastCommitBuilt}"
      echo &"Elapsed Time:{delta.inSeconds} seconds\n"
    for postBuild in obj.postBuild:
      withLock(L):
        echo "Running post build scripts"
      discard execShellCmd(fmt"{postBuild} {threadConfPath} {obj.branch}")
  except: discard
  dec building

proc getSha(obj: BuildObj): string =
  discard execCmd(fmt"git -C ./{obj.branch} fetch --all >> /dev/null && git -C ./{obj.branch} reset --hard origin/{obj.branch} >> /dev/null")
  discard execCmd(fmt"git -C ./{obj.branch} pull >> /dev/null")
  result = execCmdEx(fmt"git -C ./{obj.branch} log -1 --format=%H").output.strip()

setCurrentDir(configPath.splitPath().head)

proc watchLogic(build: BuildObj){.thread.} =
  var build = build
  build.loadState()
  build.cloneBuild()
  while true:
    let sha = build.getSha()
    if(sha != build.lastCommitBuilt):
      build.lastCommitBuilt = sha
      buildProjects(build)
      build.saveState()
    sleep(10000)

var build = parseConfig(configPath)
for branch in build.branches:
  var build = build
  build.branch = branch
  buildThreads.setLen(buildThreads.len + 1)
  buildThreads[buildThreads.high].createThread(watchLogic, build)

echo "Auto Builder Initalized"
while true:
  if(building <= 0):
    waitfor uploadGoogle()
    commitMessage()
  else:
    buildingMessage()
