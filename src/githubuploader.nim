import os, httpclient, distros, strutils, json, strformat, times
import nimarchive
import compressor, buildobj

let
  config = paramStr(1)
  branch = paramStr(2)
  built = parseConfig(config)
  jsonData = parseJson(readFile(config))
  webClient = newHttpClient()
config.splitFile.dir.setCurrentDir
if(not jsonData.contains("github")): quit "Uploading to github failed no github settings"
let
  token = jsonData["github"]["token"].getStr()
  url = jsonData["github"]["repo"].getStr()
  timeFormat = jsonData["github"]["time-format"].getStr()
  tagFormat = jsonData["github"]["tag-format"].getStr()
  time = now().format(timeFormat)
  tag = tagFormat.replace("$name", built.name).replace("$time", time)
  postData = %*{"tag_name": tag,
                  "target_commitish": branch,
                  "name": "Automated Build",
    }

webClient.headers = newHttpHeaders({"Authorization": fmt"token {token}"})

let
  res = webClient.post(url, $postData)
  resJson = res.body.parseJson()
var uploadUrl: string
if(resJson.contains("upload_url")): uploadUrl = resJson["upload_url"].getStr()
webClient.headers = newHttpHeaders({"Authorization": fmt"token {token}",
        "Content-Type": "application/zip"})
var 
  buildname = ""
  logName = ""
for x in built.platforms:
  if(x == bpWin):
    buildname = "win-build"
    logName = "win"
  elif(x == bpLinux):
    buildname = "linux-build"
    logName = "linux"
  elif(x == bpMac):
    buildname = "mac-build"
    logName = "mac"
  let 
    fileName = fmt"{buildName}-{branch}.zip"
    logFile = fmt"{logName}{branch}Log.txt"
  compress(fileName, @[fmt"{buildName}/{branch}"])

  let 
    postUrl = uploadUrl.replace("{?name",
          fmt"?name={fileName}").replace("label}", "")
    logUrl = uploadUrl.replace("{?name",
          fmt"?name={logFile}").replace("label}", "")

  echo &"Starting to Upload {branch} {buildName}\n"

  discard webClient.post(postUrl, readFile(fileName))
  discard webClient.post(logUrl, readFile(logFile))

  echo &"Uploaded {branch} {buildName}\n"
  #removeFile(fmt"{buildName}.zip")
