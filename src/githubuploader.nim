import buildobj,
  httpclient,
  times,
  strutils,
  json,
  os,
  strformat
proc uploadGithub*(archivePath, logPath: string, build: BuildObj, platform: BuildPlatforms, uploadUrl: var string) =
  ## Uploads to github and sets  uploadUrl so we can upload multiple builds to a single source
  if(github in build.buildInfo):
    let
      token = build.buildInfo[github]["token"]
      url = build.buildInfo[github]["repo"]
      timeFormat = build.buildInfo[github]["time-format"]
      tagFormat = build.buildInfo[github]["tag-format"]
      time = now().format(timeFormat)
      tag = tagFormat.multiReplace(("$name", build.name), ("$time", time), ("$os", $platform))
      postData = %*{"tag_name": tag,
                      "target_commitish": build.branch,
                      "name": "Automated Build",
        }
    var webClient = newHttpClient()
    webClient.headers = newHttpHeaders({"Authorization": fmt"token {token}"})

    let
      res = webClient.post(url, $postData)
      resJson = res.body.parseJson()
    if(resJson.contains("upload_url") and uploadUrl == ""): uploadUrl = resJson["upload_url"].getStr()
    webClient.headers = newHttpHeaders({"Authorization": fmt"token {token}",
            "Content-Type": "application/zip"})
    
    let
      ext = ".tar.gz" #Figure out later based off OS
      fileName = build.buildInfo[github]["name-format"].multiReplace(("$name", build.name), ("$time", time), ("$os", $platform)) & ext
      logFile = logPath.splitPath.tail
      postUrl = uploadUrl.replace("{?name",
            fmt"?name={fileName}").replace("label}", "")
      logUrl = uploadUrl.replace("{?name",
            fmt"?name={logFile}").replace("label}", "")

    echo &"\nStarting to Upload {build.branch} {fileName} to Github\n"
    if fileExists(archivePath):
      discard webClient.post(postUrl, readFile(archivePath))
    if fileExists(logPath):
      discard webClient.post(logUrl, readFile(logFile))
    webClient.close()
    echo &"\n Uploaded {build.branch} {fileName} to Github\n"
    removeFile(archivePath)