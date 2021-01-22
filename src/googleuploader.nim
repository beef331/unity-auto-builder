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
  echo &"\nStart Uploading: {archivePath} to Google\n\n"
  let
    info = build.buildInfo[googleCloud]
    yourBucket = info["bucket"]
    name = info["name-format"].multiReplace(("$name", build.name), ("$os", $platform))
    ext = ArchiveExt[platform]
    objectId = info["path"] & "/" & name & ext
  var conn = waitFor newConnection(info["authpath"])
  var err = waitfor conn.upload(yourBucket, objectId, readFile(archivePath))
  writeFile("err", err.pretty)
  echo &"\nFinished Uploading: {archivePath} to Google\n\n"
