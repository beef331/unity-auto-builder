import os,
       osproc,
       json,
       strformat,
       strutils,
       times,
       locks,
       terminal,
       buildobj

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
  if(fileExists(fmt"lastRun{obj.branch}.txt")):
    let
      file = open(fmt"lastRun{obj.branch}.txt", fmRead)
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
    acquire L
    eraseLine(stdout)
    echo fmt"{buildAnim[tick]} Building {building} branches. Time Elapsed: {delta.inSeconds}"
    cursorUp(stdout, 1)
    tick = (tick + 1 + buildAnim.len).mod(buildAnim.len)
    release L

proc commitMessage(){.thread.} =
  let waitingAnim = ["", ".", "..", "...", ".. .", ". ..", " ..."]
  var tick = 0
  while(building <= 0):
    sleep(120)
    acquire L
    eraseLine(stdout)
    echo fmt"Watching for commits {waitingAnim[tick]}"
    cursorUp(stdout, 1)
    tick = (tick + 1 + waitingAnim.len).mod(waitingAnim.len)
    release L

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
        removeDir(absSymPath)
        copyDirWithPermissions(absDirPath, absSymPath)
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
  echo fmt"{time} Attempting to build {obj.branch} {obj.platforms}"
  inc building
  for preBuild in obj.preBuild:
    discard execShellCmd(fmt"{preBuild} {threadConfPath} {obj.branch}")
  try:
    let startTime = getTime()
    var buildCommands: seq[string]
    let buildCommand = fmt"{obj.unityPath} -batchmode -nographics -quit -accept-apiupdate "
    if(obj.platforms.contains(bpWin)):
      buildCommands.add(buildCommand &
              fmt"-projectPath 'bpWin/{obj.branch}/{obj.subPath}' -buildTarget win64 -buildWindows64Player {getCurrentDir()}/win-build/{obj.branch}/{obj.name}.exe -logFile {getCurrentDir()}/win-{obj.branch}.log")
    if(obj.platforms.contains(bpLinux)):
      buildCommands.add(buildCommand &
              fmt"-projectPath 'bpLinux/{obj.branch}/{obj.subPath}' -buildTarget linux64 -buildLinux64Player {getCurrentDir()}/linux-build/{obj.branch}/{obj.name}.x86_64 -logFile {getCurrentDir()}/linux-{obj.branch}.log")
    if(obj.platforms.contains(bpMac)):
      buildCommands.add(buildCommand &
              fmt"-projectPath 'bpMac/{obj.branch}/{obj.subPath}' -buildTarget mac -buildOSXUniversalPlayer {getCurrentDir()}/mac-build/{obj.branch}/{obj.name}.dmg -logFile {getCurrentDir()}/mac-{obj.branch}.log")
    discard execProcesses(buildCommands, {})
    let delta = (getTime() - startTime)
    time = now().format("yyyy-MM-dd   HH:mmtt")
    echo &"{time}\nBuilds finished \n"
    echo fmt"Commit: {obj.lastCommitBuilt}"
    echo &"Elapsed Time:{delta.inSeconds} seconds\n"
    for postBuild in obj.postBuild:
      echo "Running post build scripts"
      discard execShellCmd(fmt"{postBuild} {threadConfPath} {obj.branch}")
  except: echo "Build Error"
  dec building

proc getSha(obj: BuildObj): string =
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
    commitMessage()
  else:
    buildingMessage()
