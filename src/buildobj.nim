import std/[json, os, strutils, tables, strformat]
export tables

const
  repo = "repo"
  branch = "branch"
  unityPath = "unity-path"
  preBuild = "pre-compile-scripts"
  postBuild = "post-compile-scripts"
  platforms = "platforms"
  name = "name"
  subPath = "project-sub-path"
  github* = "github"
  googleCloud* = "google-storage"
  symLink = "use-symlink"

type
  BuildInfo* = Table[string, string]
  BuildPlatforms* {.size: sizeof(cint).} = enum
    bpWin = "win", bpLinux = "linux", bpMac = "mac", bpAndr, bpWeb, bpIos
  BuildObj* = object
    unityPath*, repo*, name*, subPath*, lastCommitBuilt*: string
    platforms*: set[BuildPlatforms]
    preBuild*, postBuild*: seq[string]
    branch*: string #used to store currently building branch
    buildInfo*: Table[string, BuildInfo]
    symlinked*: bool

const ArchiveExt* =
  [
    bpWin: ".zip",
    bpLinux: ".tar.gz",
    bpMac: ".tar.gz",
    bpAndr: ".tar.gz",
    bpWeb: ".zip",
    bpIos: ".tar.gz"
  ]

proc parseConfig*(path: string): BuildObj =
  ##Loads the file into a config
  result = BuildObj()
  let rootNode = parseJson(path.readFile())

  if(rootNode.contains(repo)):
    result.repo = rootNode[repo].getStr()
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
    let prebuildScripts = rootNode[preBuild]
    for pathNode in prebuildScripts:
      let path = pathNode.getStr()
      if(path.fileExists()): result.preBuild.add(path)

  if(rootNode.contains(postBuild)):
    let postBuildScripts = rootNode[postBuild]
    for pathNode in postBuildScripts:
      let path = pathNode.getStr()
      if(path.fileExists()): result.postBuild.add(path)
  if rootNode.contains(symLink):
    result.symlinked = rootNode[symLink].getBool

  echo fmt"Using symlinks: {result.symLinked}"

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

  if(rootNode.contains(github)):
    discard result.buildInfo.hasKeyOrPut(github, BuildInfo())
    for k, v in rootNode[github].pairs:
      result.buildInfo[github][k] = v.getStr
  if(rootNode.contains(googleCloud)):
    discard result.buildInfo.hasKeyOrPut(googleCloud, BuildInfo())
    for k, v in rootNode[googleCloud].pairs:
      result.buildInfo[googleCloud][k] = v.getStr
