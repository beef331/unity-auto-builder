# Package

version       = "1.2.0"
author        = "Jason"
description   = "A batch Unity Engine builder, makes multiple build async to save time!"
license       = "MIT"
srcDir        = "src"
bin           = @["unity_auto_builder"]



# Dependencies

requires "nim >= 1.5.1"
requires "zippy == 0.5.2"
requires "https://github.com/beef331/googleapi == 0.1.3"