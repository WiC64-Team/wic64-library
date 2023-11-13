# wic64-library

Commodore 64 assembly language library for the WiC64 WiFi adapter, written in
acme cross assembler.

The WiC64 is an ESP32 based userport adapter that allows the Commodore 64 to
send and receive HTTP requests and to communicate with remote hosts via TCP
connections. This library abstracts the low level communication protocol between
the C64 and the WiC64 to provide a simple macro based interface for sending
commands to the WiC64 and receiving the response to C64 memory or processing it
on the fly.

> [!NOTE] 
> This library supports WiC64 adapters running firmware version 2.0.0 or later.
> Older firmware versions using the legacy command protocol are not supported.
> Note that firmware versions beyond 2.0.0 still support the legacy command
> protocol, so that older programs that do not use this library will still work
> with the new firmware.

## Overview

This sections provides a brief overview of the main API functions and features.
Each API function will be described in detail in the [API](#api) section of this
document.

**These high-level functions should already cover the most common use cases:**

  - [`wic64_detect`](#wic64_detect) - Detects whether a WiC64 module is present
    and is running firmware version 2.0.0 or later
  - [`wic64_execute`](#wic64_execute) - Sends a command request and receives the
    response in a single step

See section [Commands](#Commands) for the supported commands

**Programs that need to run other programs or need to return to the WiC64 portal
can optionally use the following convenience functions:**

  - [`wic64_load_and_run`](#wic64_load_and_run) - Loads a new program and runs
    it, replacing the current program
  - [`wic64_return_to_portal`](#wic64_return_to_portal) - Returns to the WiC64
    portal

Since not every program will need these functions, they are not included by
default. To include them, use the assembly time options
[`wic64_include_load_and_run`](#wic64_include_load_and_run) and
[`wic64_include_return_to_portal`](#wic64_include_return_to_portal).

**For more advanced use cases, these low-level functions can perform transfers
in smaller steps, providing more fine-grained control:**

  - [`wic64_initialize`](#wic64_initialize) - Initializes the userport and
    initiates the transfer session
  - [`wic64_send_header`](#wic64_send_header) - Sends the header part of the
    command request
  - [`wic64_send`](#wic64_send) - Sends the command payload (if any)
  - [`wic64_receive_header`](#wic64_receive_header) - Receives the reponse
    header
  - [`wic64_receive`](#wic64_receive) - Receives the response payload (if any)
  - [`wic64_finalize`](#wic64_finalize) - Finalizes the transfer session and
    resets the userport

The high level functions mentioned in the previous sections are implemented
using these low-level functions, so they are included in the library by default.

### Features

- All data transfer routines perform timeout detection by default. Execution is
  automatically and cleanly aborted if no activity is registered on the userport
  for a certain amount of time. If a timeout condition occurs, it is indicated
  to the caller by setting the carry flag.

- The new standard and extended command protocols include a qualified status
  code in the response header. In addition, a human readable error message of
  the last failed command can be requested from the WiC64, allowing programs to
  clearly communicate problems to the user. The API functions in this library
  load the status code into the accumulator before returning.

- Global handlers for timeout and error conditions can optionally be registered
  with the library, avoiding the need to explicitly test for those conditions
  after every invocation of the respective API functions.

 - The code is optimized for speed. Data transfer rates close to 42kb/s are
   possible under optimal conditions (interrupts and screen disabled). With the
   screen enabled and some moderate irq usage, transfer speeds around 36kb/s can
   still be achieved. 

- If code size is more important than raw speed, the library can also be
  optimized for size at assembly time.

- The API macros do not insert any more code than absolutely necessary to set up
  and call the actual implementation routines. They simply serve as a convenient
  frontend to the implementation.

- Global labels defined by this library are prefixed with either `wic64` or
  `WIC64` in order to keep your projects namespace clean.

- No zeropage locations are used by this library

## Getting started

### Obtaining the source code

Either clone this repository using

`$ git clone https://github.com/WiC64-Team/wic64-library.git` 

or download and extract the latest [release archive](https://github.com/WiC64-Team/wic64-library/releases/latest).

### Recommended directory structure

It is recommended to place the `wic64-library` directory alongside your project
directory, for example:

```
workspace
├── wic64-library
│   ├── wic64.asm
│   └── wic64.h
└── wic64-project
    └── wic64-project.asm
```

This way you can update to a newer version simply by running `git pull` from the
`wic64-library` directory or by downloading and extracting a new release
archive.

To assemble your project, you can then call acme from within your project
directory using its library path option `-I`:

`$ acme -I ../wic64-library wic64-project.asm`

This way you can source the library header and implementaton from your code
without having to specify an absolute or relative path:

```6502
!source "wic64.h"
!source "wic64.asm"
```

## Example

This example demonstrates basic usage of the library, including timeout and
error handling.

The function [`wic64_detect`](#wic64_detect) is called first to test whether a
wic64 is present at all, and also to confirm that it is running a firmware
version supported by this library. 

If this initial test is successful, the current IP address is requested by
calling [`wic64_execute`](#wic64_execute) with the corresponding request.

If the ip address request is successful, the current IP address is reported. 

If the request times out, a timeout error is reported to the user. 

If the transfer itself has been successful but the WiC64 has responded with a
non-zero status code indicating an error, the corresponding error message is
received from the server and reported to the user. For more details see 
section [Timeout and error handling](#timeout-and-error-handling). 

```asm
; include the wic64 header file containing the macro definitions
!source "wic64.h"                           

; just a simple macro to print a string
!macro print .string {                      
    lda #<.string
    ldx #>.string
    jsr $ab1e
}

* = $1000

main:
    +wic64_detect                           ; detect wic64 device and firmware
    bcs device_not_present                  ; carry set => wic64 not present or unresponsive
    bne legacy_firmware                     ; zero flag clear => legacy firmware detected

    +wic64_execute request, response        ; send request and receive the response
    bcs timeout                             ; carry set => timeout occurred
    bne error                               ; zero flag clear => error status code in accumulator
                                            
    +print response                         ; print the response and exit 
    rts

device_not_present:                         ; print appropriate error message...
    +print device_error
    rts

legacy_firmware:
    +print firmware_error
    rts

timeout:                                    
    +print timeout_error
    rts

error:
    ; get the error message of the last request
    +wic64_execute status_request, status_response  
    bcs timeout
    
    +print status_response
    rts

; define request to get the current ip address
request !byte "R", WIC64_GET_IP, $00, $00      

; reserve 16 bytes of memory for the response
response: !fill 16, 0                          

; define the request for the status message
status_request: !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $01  

; reserve 40 bytes of memory for the status message
status_response: !fill 40, 0  

device_error: !pet "?device not present or unresponsive error", $00
firmware_error: !pet "?legacy firmware error", $00
timeout_error: !pet "?timeout error", $00   

; include the actual wic64 routines
!source "wic64.asm"                         
```

More examples can be found in the directory `./examples`.

## Assembly time options

These options can be set by defining assembler symbols before including
`wic64.h`. They control certain aspects of the assembly, such optimization type
and inclusion of additional API functions. 

For example, to optimize the library for size, set the corresponding symbol like
this:

```6502
wic64_optimize_for_size = 1
!src "wic64.h"
```
> [!NOTE] 
> Defining these symbols after including `wic64.h` causes errors during
> assembly.

***

### `wic64_include_load_and_run` 
*(default: 0)*

If set to a non-zero value, the macro `wic64_load_and_run` and the corresponding
subroutine will be included in the assembly.

***

### `wic64_include_return_to_portal` 
*(default: 0)*

If set to a non-zero value, the convenience macro
[`wic64_return_to_portal`](#wic64_return_to_portal) and the corresponding
subroutine will be included in the assembly. Note that setting this option will
also set [`wic64_include_load_and_run`](#wic64_include_load_and_run)
automatically.

***

### `wic64_optimize_for_size` 
*(default: 0)*

If set to a non-zero value, this option will optimize the code for size rather
than speed. Note that this will result in a significant decrease in transfer
speed of about 30%.

<details>
    
> When optimizing for size, the code sections dealing with handshake and timeout
> detection will be moved to a subroutine instead of being included directly in
> the code. While this measure reduces code size, it will add additional jsr/rts
> overhead of 12 cycles for every byte transferred.

</details>

***

### `wic64_build_report` 
*(default: 0)*

If set to a nonzero value, the assembler will output additional information
after assembly. 

Most notably, the locations of the time critical sections in
[`wic64_send`](#wic64_send) and [`wic64_receive`](#wic64_receive) are reported.
If a critical section cross a page boundary, the transfer speed will decrease by
about 2kb/s, so an additional warning will be issued.

***

## API

### Timeout and Error Handling

#### Timeouts

Transfers between the C64 and the WiC64 may time out when either the client
(C64) or the server (WiC64) fail to continue the transfer for a certain amount
of time. As this is always possible, timeout conditions should be detected and
handled by an application.

For example, when requesting data from a remote URL, the remote server may
simply take additional time to respond, either because the network is slow, the
server is under increased load, or the server simply needs some time to generate
the response. In this case, you can either generally increase the client side
timeout using [`wic64_set_timeout`](#wic64_set_timeout), or use the three
argument form of [`wic64_execute`](#wic64_execute) to increase the timeout for a
specific request only. This will grant the WiC64 more time to generate the
response before the C64 concludes that the request has timed out. The default
value for the client side timeout is two seconds, which has been proven to be
sufficient for most cases.

Likewise, if you use the low level functions to send a request payload, and you
need some time to generate the data (e.g. when POSTing a disk image using
multiple calls to [`wic64_send`](#wic64_send)), you can increase the server-side
timeout of the WiC64 by using the [`WIC64_SET_TIMEOUT`](#WIC64_SET_TIMEOUT)
command, which increases the time the WiC64 waits for the C64 to continue the
current transfer.

If a timeout occurs, all api functions that send or receive data automatically
call [`wic64_finalize`](#wic64_finalize) first to make sure the request is
cleanly aborted, and then return with the carry flag set. Thus you should always
test the carry flag after calling these functions. How to handle a timeout
condition largely depends on the application. You may simply retry the request
silently for a few times, or have the user decide whether to retry or abort.

#### Errors

A successful transfer of data between the C64 and the WiC64 does not
automatically mean that no errors occured. You might have send a malformed
request, the URL you send to an HTTP or TCP command may point to a non-existent
resource, the WiFi connection may be down, etc.

To communicate errors to the client, the WiC64 always sends a general status
code in the response header. This value is available at the memory location
labeled `wic64_status` after [`wic64_receive_header`](#wic64_receive_header) has
completed successfully. In addition, it will be loaded into the accumulator
right before returning from [`wic64_receive_header`](#wic64_receive_header), and
once again before returning from [`wic64_finalize`](#wic64_finalize). Thus the
zero flag and accumulator value can be checked after both the low level function
[`wic64_receive_header`](#wic64_receive_header) and any highlevel function
(which always ends with [`wic64_finalize`](#wic64_finalize)) returns. 

The possible status codes are:

```
0 = SUCCESS: No errors occurred, request has been handled successfully
1 = INTERNAL_ERROR: Something unexpected happened (possible firmware bug)
2 = CLIENT_ERROR: The client has send a malformed request
3 = CONNECTION_ERROR: No WiFi connection available (remote requests)
4 = NETWORK_ERROR: A remote request has failed on the transport level
5 = SERVER_ERROR: A remote server has reported an error
```

These codes thus describe the general category of the error. The ESP log will
usually provide more detailed information. 

In addition, the command [`WIC64_GET_STATUS_MESSAGE`](#WIC64_GET_STATUS_MESSAGE)
can be used to request a more specific, human-readable error message which can
be displayed to the end user.

These messages depend on the command being executed. For example, a SERVER_ERROR
might provide a message like "404 not found", "501 Not Implemented", etc. A
CONNECTION_ERROR can either report "WiFi not connected" or "No IP address
assigned". A NETWORK_ERROR might report things like "Could not open connection"
or "Connection closed". A CLIENT_ERROR may read "Argument missing", "Malformed
URL", etc.

It is up to the application to decide how to handle error conditions. It may be
sufficient to simply test for a non-zero value, or look at the error code itself
for more detailed error handling, and/or use the WIC64_GET_STATUS_MESSAGE
command to retrieve and communicate the error message to the end user.

Note that the status code is only valid if no timeout occurred in the first
place. Thus code should always check for a timeout first before handling
potential errors, as in

```asm
  +wic64_execute request, response
  bcs handle_timeout
  bne handle_error
```

#### Semi-automatic timeout and error handling

Instead of testing for a timeout or error condition after each API call, general
timeout and error handling routines may be registered via
[`wic64_set_timeout_handler`](#wic64_set_timeout_handler) and
[`wic64_set_error_handler`](#wic64_set_error_handler). If present, the
respective handler address will be called via an indirect ``jmp``, with the
stack pointer reset to the value that was present when the handler was
registered. This allows returning control back to a defined stacklevel,
regardless of how deeply the subroutines that perform the actual API calls
happen to be nested.

### High level functions

***

#### `wic64_detect`
`+wic64_detect`

Detects if a WiC64 is present and whether it runs firmware version 2.0.0 or
later. This function should be called at least once at the start of a program.
Note again that this library only supports firmware versions above 2.0.0.

The carry flag will be set if a timeout occurs, which indicates that either no
WiC64 is present at the userport, or that it is present but unresponsive. In any
case, the WiC64 can be assumed not to be in a usable state.

The zero flag will be set if a WiC64 is present and runs firmware 2.0.0 or
later.

<details>
  <summary>Example</summary>
  
```asm
+wic64_detect
bcs device_not_preset
bne legacy_firmware_detected

; wic64 is present and runs a recent firmware...
```
</details>

***

#### `wic64_execute`
`+wic64_execute <request>, <response>`

`+wic64_execute <request>, <response>, <timeout>`

Executes the request at the address specified by `<request>` and receives the
response payload to the memory address specified by `<response>`. The optional
`<timeout>` argument specifies the client side [timeout](#wic64_timeout) to use
while executing this request. If no timeout argument is specified, the value of
`wic64_timeout` is used by default.

> [!NOTE] 
> The response will simply be received to the area starting at `<response>` in
> its entirety, using the current memory configuration, without doing any checks
> for plausibility. For example, if the destination address moves beyond $ffff,
> writing will simply continue at $0000. Likewise, no precautions are taken to
> prevent writing into the IO area. If you want to check the response size
> before storing the response, you will have to use the low level functions and
> conduct the transfer yourself.

***

#### `wic64_load_and_run`

`+wic64_load_and_run <request>`

Expects the response of the specified `<request>` to contain a standard CBM
program file, i.e. a file that contains the load address in the first two bytes.
Regardless of the load address in this file, the program is always loaded to the
standard load address $0801, i.e. this function mimics the behavior of the BASIC
command `LOAD"FILE.PRG",8`.

If the file is loaded successfully, the equivalent of the BASIC `RUN` command is
performed.

> [!NOTE] 
> In order to load the new program, the code to receive the response is copied
> to the free memory area at $0334 (tapebuffer). The size of the tapebuffer code
> is reported during assembly if the assembly time option [`wic64_build_report`](#wic64_build_report)
> is set to a non-zero value.

This function is only available if the assembly time option
[`wic64_include_load_and_run`](#wic64_include_load_and_run) is set to a non-zero
value.

***

#### `wic64_return_to_portal`

`+wic64_return_to_portal`

Loads and runs the WiC64 portal program using
[`wic64_load_and_run`](#wic64_load_and_run). 

Programs that run from the WiC64 portal should allow the end user to return to
the portal by pressing the back-arrow key.

This function is only vailable if the assembly time option
[`wic64_include_return_to_portal`](#wic64_include_return_to_portal) is set to a
non-zero value.

***

### Low level functions

The high level functions described above are implemented using these low level
functions. While [`wic64_execute`](#wic64_execute) should be sufficient for
simple use cases, these functions allow more fine grained control over the
transfer process. For example, payloads might be send or received from or to
multiple different memory areas. Also when using the extended protocol for
payloads exceeding 64kb, those payloads can not simply be read from or written
to C64 memory in one go, but must be handled in discrete chunks.

Here is a short example illustrating the equivalent of using
[`wic64_execute`](#wic64_execute), including manual timeout and error handling.
In general, every function that performs a send or receive may time out, while
[`wic64_receive_header`](#wic64_receive_header) will additionally receive the
status code from the WiC64 in the response header and load it into the
accumulator before returning, so that you can check the zero-flag to detect an
error condition. For semi-automated timeout and error handling, see
[`wic64_set_timeout_handler`](#wic64_set_timeout_handler) and
[`wic64_set_error_handler`](#wic64_set_error_handler).

```asm
[...]

  +wic64_initialize              ; initialize the userport and prepare transfer session

  +wic64_set_request request     ; set the source address of the request header and payload in memory
  +wic64_send_header             ; send the request header from `<request>`
  bcs timeout                    ; abort on timeout 

  +wic64_send                    ; send the request payload, if any
  bcs timeout                    ; abort on timeout 

  +wic64_receive_header          ; receive the request header, including status code and payload size
  bcs timeout                    ; abort on timeout 
  bne error                      ; status code has been loaded into accumulator, non-zero => error

  +wic64_set_response response   ; set the destination address to store the response payload to
  +wic64_receive                 ; receive the request payload, if any 
  bcs timeout

  +wic64_finalize                ; finalize transfer session and reset userport to input

[...]
```

For a (rather pointless but hopefully still informative) example of handling
transfers in discrete steps, see `./examples/06-transfer-in-discrete-steps`.

***

#### `wic64_initialize`
`+wic64_initialize`

This function must be called before sending a request using
[`wic64_send_header`](#wic64_send_header). It initializes the userport, makes
sure that the value of `wic64_timeout` is at least $01 and sets the interrupt
flag unless `wic64_dont_disable_irqs` is set.

***

#### `wic64_set_request`
`+wic64_set_request <request>`

Sets the address from where the request should read.

*** 

#### `wic64_send_header`
`+wic64_send_header`

`+wic64_send_header <request>` 

Sends the request header from the memory location specified by `<request>`. If
the request address is not specified, it needs to be set using
[`wic64_set_request`](#wic64_set_request) before calling this function. 

The WiC64 will then expect to receive the amount of data specfified in the
request header before it executes the request and sends the response.

Sets the carry flag if the transfer times out.

***

#### `wic64_send`

`+wic64_send`

`+wic64_send <source>`

`+wic64_send <source>, <size>`

Sends the request payload. The total payload size is determined by the
corresponding bytes in the request header previously send by
[`wic64_send_header`](#wic64_send_header). 

If this function is called without arguments directly after
[`wic64_send_header`](#wic64_send_header), it is assumed that the payload data
immediately follows the request header in memory. The amount of data send by a
single invocation is the total payload size minus the amount of data already
sent by previous invocations of this function, if any.

If this function is called with a `<source>` argument, the payload data is read
from the corresponding memory address, sending all remaining payload bytes.

If this function is called with both `<source>` and `<size>` arguments, then
`<size>` bytes of payload data are sent from the specified `<source>` address.
If the specified size exceeds the total number of remaining payload bytes, only
the remaining bytes are sent.

Note that if the C64 requires processing time to generate the payload in between
discrete transfer steps, the WiC64 transfer timeout may need to be increased
using [`WIC64_SET_TIMEOUT`](#WIC64_SET_TIMEOUT) before starting the transfer
session.

If the request times out, the carry flag will be set.

***

#### `wic64_set_response`
`+wic64_set_response <response>`

Sets the address to which the response should be received.

***

#### `wic64_receive_header`

`+wic64_receive_header`

Receives the response header from the WiC64. 

The response size will be stored to the address labeled `wic64_response_size`.

The command status code will be stored to the address labeled `wic64_status` and
will also be loaded into the accumulator immediately before returning. A
non-zero status code indicates an error. For other possible values, see section
[Errors](#errors).

If the response times out, the carry flag will be set.

***

#### `wic64_receive`

`+wic64_receive` 

`+wic64_receive <destination>`

`+wic64_receive <destination>, <size>`

Receives the response payload. The total payload size is determined by the
corresponding bytes in the response header previously received by
[`wic64_receive_header`](#wic64_receive_header). 

If this function is called without arguments, the destination address needs to
be set via [`wic64_set_response`](#wic64_set_response) before calling this
function. The amount of data received by this invocation is the total payload
size minus the amount of data already received by previous invocations of this
function, if any.

If this function is called with a `<destination>` argument, the payload data is
received to the corresponding memory address, receiving all remaining payload
bytes.

If this function is called with both `<destination>` and `<size>` arguments,
then `<size>` bytes of payload data are received to the specified
`<destination>` address. If the specified size exceeds the total number of
remaining payload bytes, only the remaining bytes are received.

Note that if the C64 requires processing time to handle the payload data in
between discrete transfer steps, the WiC64 transfer timeout may need to be
increased using the command [`WIC64_SET_TIMEOUT`](#WIC64_SET_TIMEOUT).

If the request times out, the carry flag will be set.

***

#### `wic64_finalize`

`wic64_finalize`

This function must be calledd after the response has been received. It sets the
userport back to input mode and restores the interrupt flag to the state it was
in before the transfer session has been started via
[`wic64_initialize`](#wic64_initialize). Finally the status code received form
the WiC64 in [`wic64_receive_header`](#wic64_receive_header) is loaded into the
accumulator immediately before returning.

This function will be called automatically if a timeout condition is detected or
a non-zero status code is received in the response header.  

***

### Configuration functions

***

#### `wic64_set_timeout`

`+wic64_set_timeout <timeout>`
*(default: $02, about two seconds)*

Sets the maximum time to wait for a handshake from the WiC64 before assuming
that the transfer has timed out.

The minimum value is $01, which corresponds to a timeout of approximately one
second. Setting this value to zero sets the value to $01.

If a timeout occurs, the carry flag will be set to signal a timeout to the
calling routine.

> [!NOTE] 
>This includes the time waiting for the WiC64 to process the request before
> sending a response, so this value may need to be adjusted, e.g. when a HTTP
> request is sent to a server that is slow to respond.

***

#### `wic64_set_timeout_handler`

`+wic64_set_timeout_handler <address>`

Sets up a global timeout handler at the specified `<address>` and saves the
current stackpointer.

If a timeout occurs and a global timeout handler is set, the stackpointer will
first be reset to the saved value and then an indirect jump to the specified
address will be performed.

***

#### `wic64_unset_timeout_handler`

`+wic64_unset_timeout_handler`

Removes any previously installed timeout handler.

***

#### `wic64_set_error_handler`

`+wic64_set_error_handler <address>`

Sets up a global error handler at the specified `<address>` and saves the
current stackpointer.

If a non-zero status code is received from the WiC64 in
[`wic64_receive_header`](#wic64_receive_header), the stackpointer will first be
reset to the saved value and then an indirect jump to the specified address will
be performed. 

***

#### `wic64_unset_error_handler`

`+wic64_unset_error_handler`

Removed a previously installed error handler.

***

#### `wic64_set_fetch_instruction` 

`wic64_set_fetch_instuction <address>`

Modifies the fetch instruction `lda $xxxx,y` in [`wic64_send`](#wic64_send) and
replaces it with the three-byte instruction copied from `<address>`, most likely
a `jsr` instruction. The resulting accumulator value will be send to the WiC64.

Note that any code injected here needs to preserve the X and Y registers to
prevent disrupting the current send transfer.

***

#### `wic64_reset_fetch_instruction` 

`wic64_reset_fetch_instruction` 

Resets the fetch instruction to the default `lda $xxxx,y`.

***

#### `wic64_set_store_instruction` 

`wic64_set_store_instruction <address>`

Modifies the store instruction `sta $xxxx,y` in
[`wic64_receive`](#wic64_receive) and replaces it with the three-byte
instruction copied from `<address>`, most likely a `jsr` instruction. The
accumulator will contain the value received from WiC64.

Note that any code injected here needs to preserve the X and Y registers to
avoid disrupting the current receive transfer.

***

#### `wic64_reset_store_instruction` 

`wic64_reset_store_instruction` 

Resets the store instruction to the default `sta $xxxx,y`.

***

#### `wic64_dont_disable_irqs` 
`+wic64_dont_disable_irqs`
*(default: disable irqs during transfer)*

Prevents disabling of IRQs during transfers.

Note that in general, after a transfer session is either completed or aborted
due to a timeout or error condition, the interrupt flag is always reset to the
state that it was in before the transfer session was initialized.

This option merely controls the state of the interrupt flag during transfers.
The default is to set the flag and thus prevent interrupts from being serviced
during transfers.

The flag can be reset by calling [`wic64_disable_irqs`](#wic64_disable_irqs),
which is the default behaviour.

***

#### `wic64_disable_irqs`

`+wic64_disable_irqs`

*(default: disable irqs during transfers)*

Disables IRQs during transfers.

***

## Commands

### Firmware Version information

The firmware versioning follows the semantic versioning scheme, consisting of
major, minor, patch and development version numbers.

The **major version number** will only be increased when the firmware is
substantially redesigned and/or rewritten, which may introduce breaking changes.

The **minor version number** will only be increased when substantial new features
are implemented. Programs relying on specific features not present in earlier
minor versions can thus test for the minor version.

The **patchlevel version number** is increased when bugfixes, corrections, and 
non-breaking, minor feature additions and/or improvements are added.

The **development version number** is only used for intermittent unstable 
releases, which will be made available to developers and/or betatesters 
if the need arises. This number actually denotes the number of commits made 
in the git repository since the last stable release.

***

#### `WIC64_GET_VERSION_STRING` 

`!byte "R", WIC64_GET_VERSION_STRING, $00, $00`

Returns the firmware version string in ASCII format, including a terminating
nullbyte. 

The firmware version is derived from `git describe --tags --dirty`, i.e. in the
format

`<major>.<minor>.<patchlevel>[-<development>-<commit-id>][-dirty]`

For stable versions, only the major, minor and patchlevel numbers are contained
in the string, e.g. `2.0.0`.

For unstable versions, the develoment version number (which is equivalent to the
number of git commits since the last stable version) and the corresponding git
commit-id are appended, e.g. the version string `2.0.0-23-38f7e763` denotes the
23rd commit with id `38f7e763` since the previous stable `2.0.0` release.

For versions compiled with local changes not committed to the git repository,
the string is additionally suffixed with `-dirty`. Such versions should not be 
distributed in binary form since they are not reproducible.

***

#### `WIC64_GET_VERSION_NUMBERS` 

`!byte "R", WIC64_GET_VERSION_NUMBERS, $00, $00`

Returns four bytes denoting the major, minor, patch and unstable version
numbers. For stable versions, the unstable version number will be zero.

You can use this command to test for a specific firmware version.

***

### Error handling

#### `WIC64_GET_STATUS_MESSAGE` 

`!byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, <case>`

Returns the status message of the last executed command as a null-terminated
upper- or lowercase PETSCII string. If the single payload byte `<case>` is set
to a non-zero value, the string will be formated in uppercase.

The response will be limited to 40 bytes, including the terminating null byte.

This means an error message will always fit on a single line on the C64 and a
newline can be printed after the message by default, since the actual message 
never exceeds 39 characters.

***

### HTTP

****

#### `WIC64_HTTP_GET`          

`!byte "R", WIC64_HTTP_GET, <url-size-l>, <url-size-h>, <url>...`

`!byte "E", WIC64_HTTP_GET, <url-size-ll>, <url-size-lh>, <url-size-hl>, <url-size-hh>, <url>...`

Performs an HTTP GET request for the specified `<url>`.

If the url contains the string `%mac`, this string will be replaced by the mac
address of the WiC64 sending the request, where any colons in the standard MAC
address representation will be removed.

If the url begins with `!` or contains the string `%ser`, the respective
string(s) will be replaced by the server string configured via
[`WIC64_SET_SERVER`](#WIC64_SET_SERVER).

The length of the resulting URL must not exceed 2000 characters, as various
servers restrict the total length of an URL. See
https://stackoverflow.com/a/417184 for the rationale behind this limit.

***

#### `WIC64_HTTP_GET_ENCODED`  

`!byte "R", WIC64_HTTP_GET_ENCODED, <url-size-l>, <url-size-h>, <url>...`

`!byte "E", WIC64_HTTP_GET_ENCODED, <url-size-ll>, <url-size-lh>, <url-size-hl>, <url-size-hh>, <url>...`

This is a variant of [`WIC64_HTTP_GET`](#WIC64_HTTP_GET) that additionally
allows encoding of limited amounts of binary data directly in the URL.

Binary data is marked by the string `<$`, followed by two bytes specifiying the
length of the binary data as an unsigned 16bit value in little-endian
byte-order, followed by the actual binary data to encode. The marker string,
size specification and binary data will be replaced by a string of uppercase
hexadecimal digits encoding the binary data.

> [!NOTE] 
> This variant is provided for backwards compatibility and should only be used
> to encode small amounts of binary data, if at all. HTTP POST requests should
> be the preferred for this purpose.

<details>
  <summary>Example</summary>
  
The following URL contains four bytes of binary data:

```asm
!text "http://www.foo.org?data=<$"
!byte $04, $00, $de, $ad, $be, $ef
```

This URL will be converted to `http://www.foo.org?data=DEADBEEF` before
performing the request.
</details>

***

#### `WIC64_HTTP_POST_URL` 

`!byte "R", WIC64_HTTP_POST_URL, <url-size-l>, <url-size-h>, <url>...`

`!byte "E", WIC64_HTTP_POST_URL, <url-size-ll>, <url-size-lh>, <url-size-hl>, <url-size-hh>, <url>...`

Sets the URL to POST to using [`WIC64_HTTP_POST_DATA`](#WIC64_HTTP_POST_DATA).
Subsequent calls of [`WIC64_HTTP_POST_DATA`](#WIC64_HTTP_POST_DATA) will post to
this URL.

The URL is expanded in the same way as described above for the
[`WIC64_HTTP_GET`](#WIC64_HTTP_GET) command.

***

#### `WIC64_HTTP_POST_DATA`

`!byte "R", WIC64_HTTP_POST_DATA, <data-size-l>, <data-size-h>, <data>...`

`!byte "E", WIC64_HTTP_POST_DATA, <url-size-ll>, <url-size-lh>, <url-size-hl>, <url-size-hh>, <url>...`

Posts `<data>` to the URL previously set via
[`WIC64_HTTP_POST_URL`](#WIC64_HTTP_POST_URL).

The data will be POSTed with `Content-Type: application/octet-stream` and can be
accessed on the server side using the HTTP POST variable `data` by default, e.g.
when using PHP, the data will be accessible via `$_POST["data"]`.

***

### TCP

***

#### `WIC64_TCP_OPEN`

`!byte "R", WIC64_TCP_OPEN, <size-l>, <size-h>, <host>:<port>`

Opens a TCP connection to the specfied `<host>` using the specified `<port>`.

<details>
  <summary>Example</summary>

```asm
!byte "R", WIC64_TCP_OPEN, <url_size, >url_size
url: !text "rapidfire.hopto.org:64128"
url_size = * - url
```
</details>

***

#### `WIC64_TCP_READ`  

`!byte "R", WIC64_TCP_READ, $00, $00`

Reads the currently available data from the TCP connection previously opened by
[`WIC64_TCP_OPEN`](#WIC64_TCP_OPEN).

***

#### `WIC64_TCP_WRITE` 

`!byte "R", WIC64_TCP_WRITE, <data-size-l>, <data-size-h>, <data>...`

Writes the specified `<data>` to the TCP connection previously opened by
[`WIC64_TCP_OPEN`](#WIC64_TCP_OPEN).

***

#### `WIC64_TCP_CLOSE`
`!byte "R", WIC64_TCP_READ, $00, $00`

Closes the TCP connection previously opened by
[`WIC64_TCP_OPEN`](#WIC64_TCP_OPEN).

***

### WiFi

***

#### `WIC64_SCAN_WIFI_NETWORKS`      

`!byte "R", WIC64_SCAN_WIFI_NETWORKS, $00, $00`

Scans for WiFi networks in the vicinity and returns a list of up to 15 
WiFi networks in the following format:

`[<index> 0x01 <ssid> 0x01 <rssi> 0x01]...]`

Where `<index>` is the index of the entry in the network list as an ASCII
decimal literal, `<ssid>` is the SSID, and `<rssi>` is the networks signal
strength as an ASCII decimal literal. Each field is followed by a separator byte
with the value `0x01`.

If a WiFi connection is already established when calling this command, it will
be closed before performing the scan and reconnected once the scan has finished.

If no networks are discovered, status code 1 (`NETWORK_ERROR`) is reported.

***

#### `WIC64_CONNECT_WITH_SSID_INDEX`  

`!byte "R", WIC64_CONNECT_WITH_SSID_INDEX, <size-l>, <size-h>, <index>, $01, <passphrase>, $01, $01`

Attempts to connect to the WiFi network specified by its `<index>` (as an ASCII
decimal literal) in the list of networks returned by the previous invocation of
[`WIC64_SCAN_WIFI_NETWORKS`](#WIC64_SCAN_WIFI_NETWORKS), using the literal ASCII
`<passphrase>`.

If the passphrase contains substrings in the format
`<ascii-tilde><hex-digit><hex-digit>` then these strings are interpreted as a
hexadecimal value in the range `0x00-0xff` and are replaced by the corresponding
byte value. The ASCII tilde character corresponds to the PETSCII up-arrow
character, so special chars in the passphrase can be entered on the C64 by using
`↑hh`, e.g. `↑5f` will encode the value `0x5f`,  which corresponds to the ASCII
underscore character.

***

#### `WIC64_CONNECT_WITH_SSID_STRING` 

`!byte "R", WIC64_CONNECT_WITH_SSID_STRING, <size-l>, <size-h>, <ssid>, $01, <passphrase>, $01, $01`

Connect to the network specified by `<ssid>` using the spefified `<passphrase`.

Special characters in the passphrase can be encoded in the same manner as
described for [`WIC64_CONNECT_WITH_SSID_INDEX`](#WIC64_CONNECT_WITH_SSID_INDEX).

***

#### `WIC64_IS_CONNECTED`            

`!byte "R", WIC64_IS_CONNECTED, $01, $00, <seconds>`

Asks the WiC64 to wait for a WiFi connection to be established for the specified
number of `<seconds>`.

Returns immediately with a successful status code once the connection is
established during this timeframe.

If no connection has been established after the specified number of seconds,
returns status code 3 (`CONNECTION_ERROR`). The status message will either read
"WiFi not connected" if no connection was established at all, or "No IP address
assigned" if a connection was established but no IP address has (yet) been
assigned by the DHCP server.

> [!NOTE] 
> Make sure the client side timeout is set to a larger value than the specified
> number of seconds to avoid running into a client-side timeout.

<details>
  <summary>Example</summary>

```asm
+wic64_execute is_connected, no_response_expected, $06 ; C64 waits one second longer than the WiC64
bcs timeout
bne not_connected

; WiFi connection is established

[...]

is_connected: !byte "R", WIC64_IS_CONNECTED, $01, $00, $05
no_response_expected:

```
</details>

***

#### `WIC64_GET_MAC`  

`!byte "R", WIC64_GET_MAC, $00, $00`

Returns the MAC address of the WiC64 as a null-terminated ASCII string.

The response will always be 19 bytes in size (18 characters + nullbyte).

***

#### `WIC64_GET_SSID` 
`!byte "R", WIC64_GET_SSID, $00, $00`

Returns the configured SSID as a null-terminated ASCII string.

The response will not exceed 33 bytes (up to 32 characters + nullbyte)

***

#### `WIC64_GET_RSSI` 
`!byte "R", WIC64_GET_RSSI, $00, $00`

Returns the current RSSI (WiFi signal strength) as a null-terminated ASCII
string in the format `<+|-><rssi>dBm`.

The response will not exceed 9 bytes (8 characters + nullbyte).

***

#### `WIC64_GET_IP`   

`!byte "R", WIC64_GET_RSSI, $00, $00`

Returns the current local IPv4 address as a null-terminated ASCII string.

Returns `0.0.0.0\0` if no WiFi connection is present or no IP address has been
assigned by DHCP.

The response will not exceed 16 bytes (15 characters + nullbyte).

***

### Configuration

***

#### `WIC64_SET_TIMEOUT` 

`!byte "R", WIC64_SET_TIMEOUT, $01, $00, <seconds>`

This command sets the *server-side* timeout to use for the next request, i.e. it
sets the number of seconds the WiC64 will wait for the C64 to continue a
transfer before assuming that the transfer has timed out.

The server-side timeout value will be reset to the default value of one second
after the request following this request has been served, regardless of whether
it was served successfully. This means that the server-side timeout needs to be
set before each request that requires a custom setting.

This is only required in case you are sending a request payload in discrete
chunks and need more time on the C64 side to prepare the next chunk of data, for
example when reading the data from disk or generating it programatically.

***

#### `WIC64_SET_SERVER` 

`!byte "R", WIC64_SET_SERVER, <string-size-l>, <string-size-h>, <string>...`

Sets the default server string (URL prefix) that is used to replace either a
leading `!` or the string `%ser` in URLs used with HTTP commands to the
specified `<string>`.

If an empty `<string>` is set, the string will be reset to the default value
`http://x.wic64.net/prg/`.

***

#### `WIC64_GET_SERVER`

`!byte "R", WIC64_GET_SERVER, $00, $00`

Returns the server string set by [`WIC64_SET_SERVER`](#WIC64_SET_SERVER) as a
null-terminated ascii string. If no server string is set, the default value
`http:/x.wic64.net/prg/` is returned.

***

### Time and date

***

#### `WIC64_SET_TIMEZONE`

`!byte "R", WIC64_SET_TIMEZONE, $02, $00, <index-low-ascii-decimal-digit>, <index-low-ascii-decimal-digit>`

Sets the WiC64 timezone. The payload constitutes the index into the timezone
array, which contains the GMT offset in seconds for the respective timezone, as
defined in the firmware:

```c
const int32_t Timezone::timezones[32] = {
    0, 0, 3600, 7200, 7200, 10800, 12600, 14400,
    18000, 19800, 21600, 25200, 28800, 32400, 34200, 36000,
    39600, 43200, -39600, -36000, -32400, -28800, -25200,
    -25200, -21600, -18000, -18000, -14400, -12600, -10800,
    -10800, -3600,
};
```

The index itself needs to be sent in "little-endian ascii-coded decimal" format,
i.e. first byte contains the low ASCII decimal digit character and the second
byte contains the high ASCII decimal digit character, e.g. index `4` is encoded
as the ASCII string `"40"` = `0x34 0x30`.

*DISCLAIMER*: I did not come up with this, this is the way it was done in the
legacy firmware, kept for backwards-compatibility with existing programs.

***

#### `WIC64_GET_TIMEZONE`   
`!byte "R", WIC64_GET_TIMEZONE, $00, $00`

Returns the current timezone, i.e. the gmt offset in seconds of the currently
configured timezone as a null-terminated ASCII string containing the decimal
literal value, e.g. for timezone GMT+1 this will return the string `3600\0`, for
GMT-2 this will return `-7200\0`.

*DISCLAIMER*: I did not come up with this, this is the way it is done in the
legacy firmware, kept for backwards-compatibility with existing programs.

***

#### `WIC64_GET_LOCAL_TIME`

`!byte "R", WIC64_GET_LOCAL_TIME, $00, $00`

Returns the current local time (i.e. the time in the configured timezone) as a
null-terminated ASCII string in strftime(3) format `%H:%M:%S %d-%m-%Y`, e.g.
`15:23:03 31-12-2023`.

The response will always be 20 bytes (19 characters + nullbyte).

***

### Firmware update

***

#### `WIC64_UPDATE_FIRMWARE` 

`!byte "R", WIC64_UPDATE_FIRMWARE, <url-size-l>, <url-size-h>, <url>...`

Performs an OTA update of the firmware using the binary firmware image pointed
to by `<url>`.

If the OTA update fails, status code 1 (`INTERNAL_ERROR`) is returned. The
status message will then contain the textual representation of the error code
returned by `esp_https_ota()`.

This command can only be used with URLs referring to firmware images hosted on
`wic64.net`.

***

#### `WIC64_REBOOT` 

`!byte "R", WIC64_GET_LOCAL_TIME, $00, $00`

Reboots the WiC64. Upon successful reboot, the WiC64 sends a single handshake
signal to the C64. 

This command is primarily intended to be used by the firmware update program to
reboot into the newly installed firmware. The handshake allows the program to
wait until the reboot is complete before sending the next request to confirm the
version of the newly installed firmware.

<details>
  <summary>Example from wic64-update/update.asm:</summary>

```asm
+wic64_set_timeout $10
+wic64_initialize
+wic64_send_header reboot_request
+wic64_wait_for_handshake
+wic64_finalize
+wic64_set_timeout $02

[...]

reboot_request: !byte "R", WIC64_REBOOT, $00, $00
```
</details>

***

### Testing

***

#### `WIC64_ECHO` 

`!byte "R", WIC64_ECHO, <data-size-l>, <data-size-h>, <data>...`

This command echoes the received payload data back to the client.

***

## Protocols

The term protocol is used to refer to the format of the request and response
header. Each protocol is identified by a magic byte send as the first byte of
the request header. Thus, to choose the protocol you wish to use, start your
request with the corresponding magic byte.

### Standard protocol "R"

This is the standard protocol for payload sizes up to 64kb. It is a revised
version of the legacy command protocol. The payload size is specified as an
unsigned 16bit value in little-endian byte-order. The reponse header contains an
additional status code.

#### Request Header

`!byte "R", <command>, <payload-size-low>, <payload-size-high>`

#### Response Header

`!byte <status>, <payload-size-low>, <payload-size-high>`

### Extended protocol "E"

This is the extended protocol for payload sizes up to 4gb. The payload size is
specified as an unsigned 32bit value in little-endian byte-order.

So far this protocol is only supported by the HTTP commands
[`WIC64_HTTP_POST_DATA`](#WIC64_HTTP_POST_DATA),
[`WIC64_HTTP_GET`](#WIC64_HTTP_GET) and
[`WIC64_HTTP_GET_ENCODED`](#WIC64_HTTP_GET_ENCODED). These commands support
response payloads of up to 4gb, but only
[`WIC64_HTTP_POST_DATA`](#WIC64_HTTP_POST_DATA) supports sending request
payloads above 64kb, as the URL length of the HTTP_GET commands is limited to
2000 characters.

Since the high level functions only support payloads up to 64kb, requests send
using the extended protocol need to be handled using the low level functions.

#### Request Header

`!byte "E", <command>, <payload-size-low-low>, <payload-size-low-high>, <payload-size-high-low>, <payload-size-high-high>`

#### Response Header

`!byte <status>, <payload-size-low-low>, <payload-size-low-high>, <payload-size-high-low>, <payload-size-high-high>`

## Appendix

### Legacy command protocol "W"

Although the legacy command protocol is not supported by this library, it is
documented here for reference, along with its peculiarities and pitfalls that
developers (myself included) have been known to stumble over in the past.

Note that firmware versions beyond 2.0.0 still support the legacy protocol to
maintain backwards-compatibility with older programs.

#### Request Header

`!byte "W", <total-request-size-lowbyte>, <total-request-size-highbyte>, <command-id>`

- The size specified in the request header does not refer to the size of the
  *payload* but rather to the size of the *entire request*, including the
  request header itself. This means that even for requests without payload,
  the size had to be specified as four rather than zero.
- The command id is placed after the total request size

#### Response Header

`!byte <payload-size-high>, <payload-size-low>`

- In contrast to the request header, the response payload size is sent in
  big-endian byte order for unknown reasons.
- No error or status code is sent in the response header. For some commands,
  error codes in various inconsistent formats are instead sent in the response
  payload, making it impossible to determine with certainty whether an actual
  error has occurred or the payload only accidently contains data that resembles
  such an error code.

#### Special handling of URLs ending in `.prg`

When sending a HTTP request for a URL that ends with `.prg`, the legacy firmware
sends the entire payload, but reports two bytes *less* than it actually sends.
Note that the new firmware still implements this behaviour to maintain
backwards-compatibility with older programs, but does so *only* if the request
is sent using the legacy protocol.

### Commands deprecated with Firmware version 2.0.0

The legacy commands described in this section have been deprecated as of version
2.0.0, either because they are no longer required, have been replaced by
alternative commands or have never worked or been documented properly.

When a deprecated command is requested, a corresponding log message is issued
that states the specific reason for the deprecation and possible alternatives.
In addition, the message is send as the response of the command. This means that
older/obsolete programs might happen to display this message on screen,
hopefully giving the end user a hint that the program is obsolete. This will
mainly happen with the original utility programs distributed with the legacy
firmware.

#### Legacy firmware version
*0x07*

This command was used to get the build date and time of the currently running
firmware, which was used in place of a proper versioning scheme.

Since the firmware is now properly versioned, this command has become obsolete.

#### Legacy firmware update
*0x03, 0x04, 0x05, $0x18*

These commands were used to perform firmware updates. Since the firmware update
mechanism has been reimplemented, these commands have become obsolete.

The old update program(s) may still appear to be working, but will actually no
longer install any updates.

#### Logging to serial console
*0x09*

We currently see no reason to log to the esp console from the c64. If you
*really* need this, please open a feature request issue.

#### UDP commands
*0x0a, 0x0b, 0x0e, 0x1e, 0x1f*

The UPD commands have always been marked as "work in progress" and have never
been used by any programms as far as we are aware of. We may implement UDP 
support in the future, should the need arise.

#### External IP address
*0x13*

The command for getting the external IP has never worked correctly, nor has it
been used in any programs we are aware of. We are also unsure about the intended
purpose of this command.

#### Access to preferences
*0x19, 0x1a*

The commands for getting or setting ESP preferences from the c64 have been
removed because we consider them to be inherently unsafe. Third parties should
not be able to write arbitrary data to the ESP flash memory. 

If a mechanism for storing persistent configuration data on the ESP is required,
we need to find a way to make sure that a program can only write a private
section of the flash memory, and we will need to be able to impose limits on the
size of the data stored in those sections.

#### Set TCP port
*0x20*

This command has apparently never had any effect in the legacy firmware, apart
from setting a global variable that was never used.

#### Legacy HTTP POST
*0x24*

The previous implementation of HTTP POST was broken and the payload structure
was unnecessarily complex. Please use the new commands
[`WIC64_HTTP_POST_URL`](#WIC64_HTTP_POST_URL) and
[`WIC64_HTTP_POST_DATA`](#WIC64_HTTP_POST_DATA) instead.

#### Legacy HTTP GET > 64kb
*0x25*
                    
This command was called "bigloader" and was intended for HTTP GET requests
exceeding 64kb. It has never worked properly and has never been officially
documented. Support for HTTP payloads exceeding 64kb has been added with the
extended command protocol.

#### Factory reset

The factory reset command has been deprecated. If this turns out to be required
at all, it will be implemented from the web interface instead.
