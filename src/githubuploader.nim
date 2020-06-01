import os, httpclient, distros, strutils, json, strformat, times
import nimarchive
import compressor,buildobj

let 
    config = paramStr(1)
    built = parseConfig(config)
    jsonData = parseJson(readFile(config))
    webClient = newHttpClient()
if(not jsonData.contains("github")): quit "Uploading to github failed no github settings"
let 
    token = jsonData["github"]["token"].getStr()
    url = jsonData["github"]["repo"].getStr()
    timeFormat = jsonData["github"]["tag-format"].getStr()
    tag = now().format(timeFormat)
    postData = %*{"tag_name" : tag,
                    "target_commitish" : built.branch,
                    "name" : "Automated Build",
                    }

webClient.headers = newHttpHeaders({"Authorization" : fmt"token {token}"})

let 
    res = webClient.post(url,$postData)
    resJson = res.body.parseJson()
var uploadUrl : string
if(resJson.contains("upload_url")): uploadUrl = resJson["upload_url"].getStr()
webClient.headers = newHttpHeaders({"Authorization" : fmt"token {token}","Content-Type" : "application/zip"})
var buildname = ""
for x in built.platforms:
    if(x == bpWin):
        buildname = "win-build"
    elif(x == bpLinux):
        buildname = "linux-build"
    elif(x == bpMac):
        buildname = "mac-build"
    compress(fmt"{buildName}.zip",@[buildName])
    
    let postUrl = uploadUrl.replace("{?name",fmt"?name={buildName}.zip").replace("label}","")
    var data = readFile(fmt"{buildName}.zip")
    echo &"Starting to Upload {x}\n"
    discard webClient.post(postUrl, data)
    echo &"Uploaded {x}\n"
    #removeFile(fmt"{buildName}.zip")