import os, osproc, httpclient, json, strformat, strutils, nimarchive, times,locks, terminal


type
    BuildPlatforms {.size: sizeof(cint).} = enum
        bpWin,bpLinux,bpMac,bpAndr,bpWeb,bpIos
    BuildObj = object
        unityPath, repo, branch, preBuild, postBuild, token, archiveUrl,
         name, subPath,lastCommitBuilt, branchUrl : string
        platforms : set[BuildPlatforms]
        

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
    webClient : HttpClient
    building : bool = false
    writeThread : Thread[void]
    L: Lock
initLock(L)

if(not fileExists(configPath)):
    quit(fmt"Config File not found at {configPath}")

proc saveState(obj : BuildObj)=
    var file = open("lastRun.txt",fmWrite)
    file.writeLine(obj.branch)
    file.writeLine(obj.lastCommitBuilt)
    file.close()

proc loadState(obj : var BuildObj)=
    var lastBranch : string
    if(fileExists("lastRun.txt")):
        let 
            file = open("lastRun.txt",fmRead)
            splitFile = file.readAll.split("\n")
        if(splitFile.len >= 2):
            lastBranch = splitFile[0]
            obj.lastCommitBuilt = splitFile[1]
        file.close()

    saveState(obj)

    for x in obj.platforms:
        if(obj.branch != lastBranch and dirExists($x)):
            removeDir($x)


proc buildingWriter(){.thread.}=
    let 
        buildChars = ["|","/","-","\\","|","/","-","\\"]
        startTime = getTime()
    var tick = 0
    while(building):
        sleep(60)
        let delta = (getTime() - startTime)
        acquire L
        eraseLine(stdout)
        echo fmt"Building {buildChars[tick]} Time Elapsed: {delta.seconds}"
        cursorUp(stdout,1)
        tick = (tick + 1 + buildChars.len).mod(buildChars.len)
        release L



proc fetchAndSetup(obj : BuildObj)=
    ##Downloads the archive, extracts it and copies it
    try:
        webClient.downloadFile(obj.archiveUrl,"temp.tar.gz")
        extract("temp.tar.gz","temp")
        #Duplicate so we can run the Unity editor in async to build multiple at once
        for x in obj.platforms:
            copyDir("temp",$x)
    except:
        echo "File cannot be found, check your repo, and branch"

proc cleanUp(obj : BuildObj)=
    #Clean up clean up, everyone everywhere
    removeDir("temp")
    removeFile("temp.tar.gz")

proc buildProjects(obj :BuildObj)=
    ##Build each platform async to build many at once
    fetchAndSetup(obj)
    var time = now().format("yyyy-MM-dd   HH:mtt")
    echo fmt"{time} Attempting to build {obj.platforms}"
    building = true
    if(not obj.preBuild.isEmptyOrWhitespace):
        discard execShellCmd(obj.preBuild)
    try:
        let startTime = getTime()
        var buildCommands : seq[string]
        let buildCommand = fmt"{obj.unityPath} -batchmode -nographics -quit "
        if(obj.platforms.contains(bpWin)):
            buildCommands.add(buildCommand & fmt"-projectPath '{getCurrentDir()}/bpWin{obj.subPath}' -buildTarget win64 -buildWindows64Player {getCurrentDir()}/win-build/{obj.name}.exe -logFile {getCurrentDir()}/winLog.txt")
        if(obj.platforms.contains(bpLinux)):
            buildCommands.add(buildCommand & fmt"-projectPath '{getCurrentDir()}/bpLinux{obj.subPath}' -buildTarget linux64 -buildLinux64Player {getCurrentDir()}/linux-build/{obj.name}.x86_64 -logFile {getCurrentDir()}/linuxLog.txt")
        if(obj.platforms.contains(bpMac)):
            buildCommands.add(buildCommand & fmt"-projectPath '{getCurrentDir()}/bpMac{obj.subPath}' -buildTarget mac -buildOSXUniversalPlayer {getCurrentDir()}/mac-build/{obj.name}.dmg -logFile {getCurrentDir()}/macLog.txt")


        createThread(writeThread, buildingWriter)
        discard execProcesses(buildCommands,{})
        building = false

        joinThread(writeThread)
        let delta = (getTime() - startTime)
        time = now().format("yyyy-MM-dd   HH:mtt")
        echo fmt"{time} Builds on commit {obj.lastCommitBuilt} done. It took {delta.seconds} seconds."
        discard execShellCmd(obj.postBuild)
    except: echo "Build Error"

proc parseConfig(path : string) : BuildObj=
    ##Loads the file into a config
    result = BuildObj()
    let rootNode = parseJson(path.readFile())

    if(rootNode.contains(token)):
        result.token = rootNode[token].getStr()
        webClient = newHttpClient()
        webClient.headers = newHttpHeaders({"Authorization" : fmt"token {result.token}" })
    else:
        echo "No token found, ignore issue if public repo"

    if(rootNode.contains(repo)):
        result.repo = rootNode[repo].getStr()
        let response = webClient.request(result.repo)
        if(response.code != Http200):
            quit "Repo not accesible, check token and url."
        let responseJson = response.bodyStream.parseJson()
        #Get archiveUrl for downloading tarball/zipball
        result.archiveUrl = responseJson["archive_url"].getStr()
        result.branchUrl = responseJson["branches_url"].getStr()
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
            of "windows", "win" : result.platforms = result.platforms + {bpWin}
            of "linux", "winux", "lin" : result.platforms = result.platforms + {bpLinux}
            of "mac", "macos" : result.platforms = result.platforms + {bpMac}
            of "android", "droid", "apk" : result.platforms = result.platforms + {bpAndr}
            of "ios", "iphone" : result.platforms = result.platforms + {bpIos}
            of "web", "webgl" : result.platforms = result.platforms + {bpWeb}
    else:
        quit "No platforms found, quitting"

    #Setup Archive URL
    result.archiveUrl = result.archiveUrl.replace("{archive_format}","tarball").replace("{/ref}",fmt"/{result.branch}")
    result.branchUrl = result.branchUrl.replace("{/branch}", fmt"/{result.branch}")


setCurrentDir(configPath.splitPath().head)

var build = parseConfig(configPath)
build.loadState()
echo "Auto Builder Initalized"

var tick = 0
let waitingAnim = ["",".","..","...",".. .",". .."," ..."]
while true:
    let res = webClient.request(build.branchUrl)
    let resJson = res.body.parseJson()
    let sha = resJson["commit"]["sha"].getStr()
    if(sha != build.lastCommitBuilt):
        build.lastCommitBuilt = sha
        cleanUp(build)
        buildProjects(build)
        cleanUp(build)
        build.saveState
    else:
        
        echo fmt"Watching for commit differences {waitingAnim[tick]}"
        cursorUp(stdout,1)
        eraseLine()
        tick = (tick + 1 + waitingAnim.len).mod(waitingAnim.len)

    sleep(10000)

