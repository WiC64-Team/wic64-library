## Version 1.2.0

- Added the assembly time option `wic64_include_response_limit` and the macro
  `wic64_set_response_limit`
  - With a limit set, `wic64_execute` doesn't store a response that is larger
    than the limit: it receives the response without storing it and returns
    with carry set, so that memory after the response buffer stays intact
  - Responses over 64kb to "E" requests are refused and received completely
  - Example 09 tests the limit
  - Without the option, the assembled code is unchanged

## Version 1.1.0

Due to the renaming of WIC64_SET_TIMEOUT, this release constitutes a (minor)
breaking change, so if you use WIC64_SET_TIMEOUT in your program, you will
have to replace it with WIC64_SET_TRANSFER_TIMEOUT.

- Added new command id constant WIC64_SET_REMOTE_TIMEOUT ($32)
  - Also renamed WIC64_SET_TIMEOUT to WIC64_SET_TRANSFER_TIMEOUT

- Fixed a bug in wic64_detect that would sometimes cause timeouts to occur
  - wic64_detect sends a WIC64_VERSION_STRING request to determine whether a new
    firmware is running, and simply discards the response by sending the
    appropriate number of handshakes. A small delay is required between
    handshakes to give the ESP enough time to register each handshake.
  - This problem only occurs with certain mainboard/cia combinations

 - Improved wic64_load_and_run by clearing the keyboard buffer prior to running
   the received program. This fixes some instances of odd behaviour when
   returning to the WiC64 portal, e.g. stepping back one level immediately.

## Version 1.0.0

- Initial Release
