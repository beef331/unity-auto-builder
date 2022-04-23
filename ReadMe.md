# Unity Auto Builder
A git based Unity Build System. It tracks git commits and automates desktop builds and uploads off them.
## How To Build

Clone the repo. Install [Nim](https://github.com/dom96/choosenim), then run `nimble install https://github.com/beef331/unity-auto-builder` inside the root directory of the cloned repo.

Requirements:
`libssl, git`
On Ubuntu: `sudo apt install libssl-dev git`


Optionally run `nimble install` to have it install and place it in your path, so it does not require navigating to the project directory.

Populate the config.json with actual data.

Finally run `./unity_auto_builder /path/to/config.json`

or if you used nimble install
`unity_auto_builder /path/to/config.json`

The builder will now pull the repo, setup the symlinks, build and upload(if you have it setup).
A new commit will cause it to pull again and build and upload.

## Pre/Post Scripts
These scripts can be any exectuable program. For post build scripts a path to the config jsonis passed, which you can reparse for your own needs.

The github time-format can be customized following [this parsing logic](https://nim-lang.org/docs/times.html#parsing-and-formatting-dates)

