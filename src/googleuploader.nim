import buildobj
import googleapi/[storage, connection]
import std/[
  times,
  strutils,
  json,
  os,
  strformat,
  asyncdispatch
]
proc uploadGoogle*(archivePath, logPath: string, build: BuildObj, platform: BuildPlatforms) =
  if googleCloud in build.buildInfo:
    echo &"Start Uploading: {archivePath} to Google\n"
    let
      info = build.buildInfo[googleCloud]
      yourBucket = info["bucket"]
      name = info["name-format"].multiReplace(("$name", build.name), ("$os", $platform))
      ext = ArchiveExt[platform]
      objectId = info["path"] & "/" & name & ext
    var conn = waitFor newConnection(info["authpath"])
    var err = waitfor conn.upload(yourBucket, objectId, readFile(archivePath), NoCache)
    echo &"\nFinished Uploading: {archivePath} to Google\n"