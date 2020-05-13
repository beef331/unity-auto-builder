import os, osproc, httpclient, json, strformat, strutils, nimarchive


type
    BuildPlatforms {.size: sizeof(cint).} = enum
        bpWin,bpLinux,bpMac,bpAndr,bpWeb,bpIos
    BuildObj = object
        unityPath, repo, branch, preBuild, postBuild, token, archiveUrl, name : string
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
var
    webClient : HttpClient

if(not fileExists(configPath)):
    quit(fmt"Config File not found at {configPath}")

proc fetchAndSetup(obj : BuildObj)=
    echo "Attempting to download source"
    try:
        webClient.downloadFile(obj.archiveUrl,"temp.tar.gz")
        extract("temp.tar.gz","temp")
        for x in obj.platforms:
            copyDir("temp",$x)
    except:
        echo "File cannot be found, check your repo, and branch"

proc cleanUp(obj : BuildObj)=
    for x in obj.platforms:
        try:
            removeDir($x)
        except: discard
    removeDir("temp")
    removeFile("temp.tar.gz")

proc buildProjects(obj :BuildObj)=
    try:
        var buildCommands : seq[string]
        if(obj.platforms.contains(bpWin)):
            buildCommands.add(fmt"{obj.unityPath} -projectPath '{getCurrentDir()}/bpWin' -batchmode -buildTarget win64 -nographics -buildWindows64Player {getCurrentDir()}/win-build/{obj.name}.exe -quit")
        if(obj.platforms.contains(bpLinux)):
            buildCommands.add(fmt"{obj.unityPath} -projectPath '{getCurrentDir()}/bpLinux' -batchmode -buildTarget linux64 -nographics -buildLinux64Player {getCurrentDir()}/linux-build/{obj.name}.x86_64 -quit")
        discard execProcesses(buildCommands)
    except: echo "Build Error"

proc parseConfig(path : string) : BuildObj=
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
        echo responseJson.pretty()
        #Get archiveUrl for downloading tarball/zipball
        result.archiveUrl = responseJson["archive_url"].getStr()
    else: quit "No repo in Json"

    if(rootNode.contains(unityPath)):
        result.unityPath = rootNode[unityPath].getStr()
    else: quit "No Unity path in config"

    if(rootNode.contains(name)):
        result.name = rootNode[name].getStr()
    else:
        quit "You need a license file go to X to get one"

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
        quit "No platforms found quitting"

    #Setup Archive URL
    result.archiveUrl = result.archiveUrl.replace("{archive_format}","tarball").replace("{/ref}",fmt"/{result.branch}")

let build = parseConfig(configPath)
cleanUp(build)
fetchAndSetup(build)
buildProjects(build)
cleanUp(build)