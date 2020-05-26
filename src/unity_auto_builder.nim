import os, osproc, httpclient, json, strformat, strutils, nimarchive, times,
        locks, terminal

type
    BuildPlatforms {.size: sizeof(cint).} = enum
        bpWin, bpLinux, bpMac, bpAndr, bpWeb, bpIos
    BuildObj = object
        unityPath, repo, branch, preBuild, postBuild, token, archiveUrl,
         name, subPath, lastCommitBuilt, branchUrl: string
        platforms: set[BuildPlatforms]

if(paramCount() < 1):
    quit "Please supply a path to the config you wish to use"

let
    configPath = paramStr(1)

const
    token = "token"
    repo = "repo"
    branch = "branch"
    unityPath = "unity-path"
    preBuild = "pre-compile-script"
    postBuild = "post-compile-script"
    platforms = "platforms"
    name = "name"
    subPath = "project-sub-path"
var
    webClient: HttpClient
    building: bool = false
    writeThread: Thread[void]
    L: Lock
initLock(L)

if(not fileExists(configPath)):
    quit(fmt"Config File not found at {configPath}")

proc saveState(obj: BuildObj) =
    var file = open("lastRun.txt", fmWrite)
    file.writeLine(obj.branch)
    file.writeLine(obj.lastCommitBuilt)
    file.close()

proc loadState(obj: var BuildObj) =
    var lastBranch: string
    if(fileExists("lastRun.txt")):
        let
            file = open("lastRun.txt", fmRead)
            splitFile = file.readAll.split("\n")
        if(splitFile.len >= 2):
            lastBranch = splitFile[0]
            obj.lastCommitBuilt = splitFile[1]
        file.close()

    saveState(obj)

    for x in obj.platforms:
        if(obj.branch != lastBranch and dirExists($x)):
            removeDir($x)

proc buildingMessage(){.thread.} =
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
    while(building):
        sleep(60)
        let delta = (getTime() - startTime)
        acquire L
        eraseLine(stdout)
        echo fmt"{buildAnim[tick]} Building. Time Elapsed: {delta.seconds}"
        cursorUp(stdout, 1)
        tick = (tick + 1 + buildAnim.len).mod(buildAnim.len)
        release L

proc commitMessage(){.thread.}=
    let waitingAnim = ["", ".", "..", "...", ".. .", ". ..", " ..."]
    var tick = 0
    while(not building):
        sleep(120)
        acquire L
        eraseLine(stdout)
        echo fmt"Watching for commits {waitingAnim[tick]}"
        cursorUp(stdout, 1)
        tick = (tick + 1 + waitingAnim.len).mod(waitingAnim.len)
        release L

proc resyncBuildFiles(obj : BuildObj)= 

    let pathName = obj.repo[(obj.repo.rfind('/')+1)..obj.repo.high]

    let previousDir = getCurrentDir()
    setCurrentDir(previousDir & "/" & pathName)
    discard execShellCmd(fmt"git checkout {obj.repo}")
    discard execShellCmd(fmt"git pull")
    setCurrentDir(previousDir)

    for platform in obj.platforms:
        if(not dirExists($platform)): createDir($platform)
        for dir in walkDir(pathName):
            let 
                absDirPath = fmt"{getCurrentDir()}/{dir.path}"
                name = dir.path.splitPath().tail
                absSymPath = fmt"{getCurrentDir()}/{$platform}/{name}"
            if(dirExists(absSymPath) or fileExists(absSymPath)): continue
            createSymlink(absDirPath,absSymPath)

proc cloneBuild(obj: BuildObj) =
    ##Downloads the archive, extracts it and copies it
    let pathName = obj.repo[(obj.repo.rfind('/')+1)..obj.repo.high]
    if(not dirExists(pathName)):
        discard execShellCmd(fmt"git clone {obj.repo}")
        if(not dirExists(pathName)): quit "Repo not accessible or incorrect"
        resyncBuildFiles(obj)

proc cleanUp(obj: BuildObj) =
    #Clean up clean up, everyone everywhere
    removeDir("temp")
    removeFile("temp.tar.gz")

proc buildProjects(obj: BuildObj) =
    ##Build each platform async to build many at once
    obj.resyncBuildFiles()

    var time = now().format("yyyy-MM-dd   HH:mmtt")
    echo fmt"{time} Attempting to build {obj.platforms}"
    building = true
    if(not obj.preBuild.isEmptyOrWhitespace):
        discard execShellCmd(obj.preBuild)
    try:
        let startTime = getTime()
        var buildCommands: seq[string]
        let buildCommand = fmt"{obj.unityPath} -batchmode -nographics -quit "
        if(obj.platforms.contains(bpWin)):
            buildCommands.add(buildCommand &
                    fmt"-projectPath '{getCurrentDir()}/bpWin{obj.subPath}' -buildTarget win64 -buildWindows64Player {getCurrentDir()}/win-build/{obj.name}.exe -logFile {getCurrentDir()}/winLog.txt")
        if(obj.platforms.contains(bpLinux)):
            buildCommands.add(buildCommand &
                    fmt"-projectPath '{getCurrentDir()}/bpLinux{obj.subPath}' -buildTarget linux64 -buildLinux64Player {getCurrentDir()}/linux-build/{obj.name}.x86_64 -logFile {getCurrentDir()}/linuxLog.txt")
        if(obj.platforms.contains(bpMac)):
            buildCommands.add(buildCommand &
                    fmt"-projectPath '{getCurrentDir()}/bpMac{obj.subPath}' -buildTarget mac -buildOSXUniversalPlayer {getCurrentDir()}/mac-build/{obj.name}.dmg -logFile {getCurrentDir()}/macLog.txt")


        createThread(writeThread, buildingMessage)
        discard execProcesses(buildCommands, {})
        building = false

        joinThread(writeThread)
        eraseLine(stdout)
        let delta = (getTime() - startTime)
        time = now().format("yyyy-MM-dd   HH:mmtt")
        echo &"{time}\nBuilds finished \n" 
        echo fmt"Commit: {obj.lastCommitBuilt}"
        echo &"Elapsed Time:{delta.seconds} seconds\n"
        createThread(writeThread,commitMessage)
        discard execShellCmd(obj.postBuild)
    except: echo "Build Error"

proc parseConfig(path: string): BuildObj =
    ##Loads the file into a config
    result = BuildObj()
    let rootNode = parseJson(path.readFile())

    if(rootNode.contains(token)):
        result.token = rootNode[token].getStr()
        webClient = newHttpClient()
        webClient.headers = newHttpHeaders({
                "Authorization": fmt"token {result.token}"})
    else:
        echo "No token found, ignore issue if public repo"

    if(rootNode.contains(repo)):
        result.repo = rootNode[repo].getStr()
        #[
        let response = webClient.request(result.repo)
        if(response.code != Http200):
            quit "Repo not accesible, check token and url."
        let responseJson = response.bodyStream.parseJson()
        #Get archiveUrl for downloading tarball/zipball
        result.archiveUrl = responseJson["archive_url"].getStr()
        result.branchUrl = responseJson["branches_url"].getStr()
        ]#
    else: quit "No repo in Json"


    if(rootNode.contains(unityPath)):
        result.unityPath = rootNode[unityPath].getStr()
    else: quit "No Unity path in config"

    if(rootNode.contains(subPath)):
        result.subPath = rootNode[subPath].getStr()
    else: echo "No subpath found, assuming root project folder."

    if(rootNode.contains(name)):
        result.name = rootNode[name].getStr()
    else:
        echo "Name not found using untitled"
        result.name = "untitled"

    if(rootNode.contains(branch)):
        result.branch = rootNode[branch].getStr()
    else:
        echo "No branch in json, using master"
        result.branch = "master"

    if(rootNode.contains(preBuild)):
        let path = rootNode[preBuild].getStr()
        if(path.fileExists()): result.preBuild = path
        else: echo "Pre-Build file not found"

    if(rootNode.contains(postBuild)):
        let path = rootNode[postBuild].getStr()
        if(path.fileExists()): result.postBuild = path
        else: echo "Post-Build file not found"

    if(rootNode.contains(platforms)):
        for platform in rootNode[platforms]:
            case platform.getStr().toLower():
            of "windows", "win": result.platforms = result.platforms + {bpWin}
            of "linux", "winux", "lin": result.platforms = result.platforms + {bpLinux}
            of "mac", "macos": result.platforms = result.platforms + {bpMac}
            of "android", "droid", "apk": result.platforms = result.platforms +
                    {bpAndr}
            of "ios", "iphone": result.platforms = result.platforms + {bpIos}
            of "web", "webgl": result.platforms = result.platforms + {bpWeb}
    else:
        quit "No platforms found, quitting"

    #Setup Archive URL
    result.archiveUrl = result.archiveUrl.replace("{archive_format}",
            "tarball").replace("{/ref}", fmt"/{result.branch}")
    result.branchUrl = result.branchUrl.replace("{/branch}",
            fmt"/{result.branch}")

proc getSha(obj : BuildObj):string=
    let pathName = obj.repo[(obj.repo.rfind('/')+1)..obj.repo.high]
    let previousDir = getCurrentDir()
    setCurrentDir(previousDir & "/" & pathName)
    discard execCmd("git fetch")
    result = execCmdEx("git show-ref HEAD -s").output.strip()
    setCurrentDir(previousDir)

setCurrentDir(configPath.splitPath().head)

var build = parseConfig(configPath)
build.loadState()
build.cloneBuild()
echo "Auto Builder Initalized"

createThread(writeThread, commitMessage)

while true:
    let sha = build.getSha()
    if(sha != build.lastCommitBuilt):
        building = true
        joinThread(writeThread)
        build.lastCommitBuilt = sha
        cleanUp(build)
        buildProjects(build)
        cleanUp(build)
        build.saveState

    sleep(10000)
