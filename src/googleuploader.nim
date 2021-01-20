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
proc uploadGoogle*(archivePath, logPath: string, build: BuildObj, platform: BuildPlatforms) {.async.} =
  echo &"\n Starting to upload: {archivePath}\n"
  let
    info = build.buildInfo["google-storage"]
    yourBucket = info["bucket"]
    name = info["name-format"].multiReplace(("$name", build.name), ("$os", $platform))
    ext = archivePath.splitFile.ext
    objectId = info["path"] & name & ext
  var conn = waitFor newConnection(info["authpath"])
  var err = waitfor conn.upload(yourBucket, objectId, readFile(archivePath))
  echo &"\n Finished Uploading: {archivePath}\n"
