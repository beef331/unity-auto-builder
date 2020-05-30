# Unity Auto Build

## How To Build

Clone the repo. Install [Nim](https://github.com/dom96/choosenim), then run `nimble build` inside the root directory of the cloned repo.
Optionally run `nimble install` to have it install and place it in your path, so it does not require navigating to the project directory.

Populate the config.json with actual data.

Finally run `./unity_auto_builder /path/to/config.json`
or if you used nimble install
`unity_auto_builder /path/to/config.json`

The itch.io and Github uploaders require to be built with `-d:ssl` and have only been tested on linux.

To build them simply just 
`nim -c -d:ssl ./src/itchiouploader.nim`
`nim -c -d:ssl ./src/githubuploader.nim`