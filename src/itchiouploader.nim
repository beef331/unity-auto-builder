import buildobj, os, httpclient, distros, strutils, strformat
import nimarchive,nimarchive/archive

let 
    config = paramStr(1)
    built = parseConfig(config)
    webClient = newHttpClient()

var downloadURL = "https://broth.itch.ovh/butler/$1-amd64/LATEST/archive/default"

if detectOs(Linux):
    downloadURL = downloadURL % "linux"
elif(detectOs(MacOSX)):
    downloadURL = downloadURL % "darwin"
elif(detectOs(Windows)):
    downloadURL = downloadURL % "windows"
else:
    quit "Os not supported"

if(not dirExists("./butler")):
    webClient.downloadFile(downloadURL,"butler.zip")
    extract("butler.zip", "./butler")
