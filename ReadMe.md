# Unity Auto Builder

## How To Build

Clone the repo. Install [Nim](https://github.com/dom96/choosenim), then run `nimble build` inside the root directory of the cloned repo.
Optionally run `nimble install` to have it install and place it in your path, so it does not require navigating to the project directory.

Populate the config.json with actual data.

Finally run `./unity_auto_builder /path/to/config.json`

or if you used nimble install
`unity_auto_builder /path/to/config.json`

## Pre/Post Scripts
These scripts can be any exectuable program. For post build scripts a path to the config jsonis passed, which you can reparse for your own needs.

The itch.io and Github uploaders require to be built with `-d:ssl` and have only been tested on linux.

To build them simply `nimble install nimarchive`

then

`nim c ./src/itchiouploader.nim`

`nim c ./src/githubuploader.nim`

The github tag-format can be customized following [this parsing logic](https://nim-lang.org/docs/times.html#parsing-and-formatting-dates)

