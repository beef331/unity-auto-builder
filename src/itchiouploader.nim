import os, httpclient, distros, strutils, json, tables, strformat
import nimarchive
import compressor, buildobj

let
  config = paramStr(1)
  built = parseConfig(config)
  jsonData = parseJson(readFile(config))
  webClient = newHttpClient()


if(not jsonData.contains("itch")): quit "Uploading to itch.io failed no itch settings"

var
  downloadURL = "https://broth.itch.ovh/butler/$1-amd64/LATEST/archive/default"
  butlerPath = "./butler/butler" #For adding extension to
if(detectOs(Linux)):
  downloadURL = downloadURL % "linux"
elif(detectOs(MacOSX)):
  downloadURL = downloadURL % "darwin"
elif(detectOs(Windows)):
  downloadURL = downloadURL % "windows"
  butlerPath &= ".exe"

else:
  quit "Os not supported"
#TODO-Support Non Linux
if(not dirExists("./butler")):
  webClient.downloadFile(downloadURL, "butler.zip")
  extract("butler.zip", "./butler")
  if(detectOs(Linux)): discard execShellCmd(fmt"chmod +x {butlerPath}")

discard execShellCmd(fmt"{butlerPath} login")


let
  channels = {bpWin: "win", bpLinux: "linux", bpMac: "mac"}.toTable()
  name = jsonData["itch"]["name"].getStr()
  gameName = jsonData["itch"]["game-name"].getStr()

#Compression is optional and butler can just take a directory and send it as a zip
if(built.platforms.contains(bpWin)):
  compress("win-build.zip", @["win-build"])
  discard execShellCmd(fmt"{butlerPath} push ./win-build.zip {name}/{gameName}:{channels[bpWin]}")
  removeFile("win-build.zip")
if(built.platforms.contains(bpLinux)):
  compress("linux-build.zip", @["linux-build"])
  discard execShellCmd(fmt"{butlerPath} push ./linux-build.zip {name}/{gameName}:{channels[bpLinux]}")
  removeFile("linux-build.zip")
if(built.platforms.contains(bpMac)):
  compress("mac-build.zip", @["mac-build"])
  discard execShellCmd(fmt"{butlerPath} push ./mac-build.zip {name}/{gameName}:{channels[bpMac]}")
  removeFile("mac-build.zip")
