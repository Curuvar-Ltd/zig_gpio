// zig fmt: off
// DO NOT REMOVE ABOVE LINE -- zig's auto-formatting sucks.

//                Copyright (c) 2024, Curuvar Ltd.
//                      All Rights Reserved
//
// SPDX-License-Identifier: BSD-3-Clause
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

/// This file contains the constant and type definitions needed to access the
/// Linux /dev/gpiochipN interface.

const std = @import( "std" );

const log = std.log.scoped( .gpiochip );

// =============================================================================
//  Public Constants
// =============================================================================

pub const Ioctl = enum(u32)
{
    get_info            = 0x8044B401,  // Data: &ChipInfo
    line_info           = 0xC100B405,  // Data: &LineInfo
    watch_line          = 0xC100B406,  // Data: &LineInfo
    line_request        = 0xC250B407,  // Data: &LineRequest
    unwatch_line        = 0xC004B40C,  // Data: (usize) line number
    set_line_config     = 0xC110B40D,  // Data: &LineRequest
    get_line_values     = 0xC010B40E,  // Data: &LineValues
    set_line_values     = 0xC010B40F,  // Data: &LineValues
};

pub const MAX_NAME_SIZE      = 31;
pub const MAX_LINES          = 64;
pub const MAX_LINE_ATTRS     = 10;

// =============================================================================
//  Public Structures
// =============================================================================

// -----------------------------------------------------------------------------
/// This structure defines the data format for the .get_info ioctl call.

pub const ChipInfo = extern struct
{
    /// The name of the chip as defined by the operating system.
    name       : [MAX_NAME_SIZE:0]u8,
    /// The chip's label.
    label      : [MAX_NAME_SIZE:0]u8,
    /// The number of lines this chip supports.
    line_count : u32,
};

// -----------------------------------------------------------------------------
/// This structure defines the data format for the .line_info and
/// and .watch_line_info ioctl calls.
///
/// Set the "line" field to the desired line number before making the call.

pub const LineInfo = extern struct //=> struct gpio_v2_line_info
{
    /// This line's name as defined by the operating system.
    name      : [MAX_NAME_SIZE:0]u8,
    /// The current consumer of this line, if any.
    consumer  : [MAX_NAME_SIZE:0]u8,
    /// The line number within the Chip.
    line      : u32,
    /// Number of entries in the "attrs" array
    num_attrs : u32,
    /// The current flags for this line.
    flags     : Flags align(8),
    /// The current attributes of this line.
    attrs     : [MAX_LINE_ATTRS]LineAttribute,
    padding   : [4]u32,
};


// -----------------------------------------------------------------------------
/// This stucture defines an info event which is read from the Chip's file
/// descriptor.  Info events are provided after makeing a WatchLine call.

pub const InfoEvent = extern struct
{
    event_type : InfoEventType,
    timestamp  : u64,
    info       : LineInfo,
};

// -----------------------------------------------------------------------------
/// This structure defines the data format for the .line_request and
/// .set_line_config ioctls.

pub const LineRequest = extern struct //=> struct gpio_v2_line_request
{
    /// An array of line numbers to request or configure.  The length
    /// of this array is stored in element "num_lines".
    lines             : [MAX_LINES]u32,
    /// TThe consumer name to tag a line with.  It lets other know
    /// who is controlling the line.
    consumer          : [MAX_NAME_SIZE:0]u8,
    /// Various configuration data for the lines.
    config            : Config,
    /// The number of elements in the "lines" array.
    num_lines         : u32,
    /// The size of the event buffer (set to zero for the default size).
    event_buffer_size : u32,
    padding           : [5]u32,
    /// Will be set to the file descriptor associated with the request.
    fd                : std.posix.fd_t,

    // -------------------------------------------------------------------------
    //  Sub-structures
    // -------------------------------------------------------------------------

    pub const Config = extern struct  //=> struct gpio_v2_line_config
    {
        /// Flags the define the line's state.
        flags     : Flags align(8),
        /// The number of item in the "attrs" array.
        num_attrs : u32,
        padding   : [5]u32,
        /// Various attributes that might be specified for a line.
        attrs     : [MAX_LINE_ATTRS]ConfigAttribute,
    };

    // -------------------------------------------------------------------------

    pub const ConfigAttribute = extern struct //=> struct gpio_v2_line_config_attribute
    {
        attr : LineAttribute,
        mask : u64 align(8),
    };

    // -------------------------------------------------------------------------
    //  Public Function LineRequest fillLines
    // -------------------------------------------------------------------------
    /// This function files the lines array, and set the num_lines filed
    /// based on a StaticBitSet indicating the requested lines.

    pub fn fillLines( self          : *LineRequest,
                      in_mask       : std.StaticBitSet( MAX_LINES ) ) !void
    {
        self.num_lines = 0;

        for(0..MAX_LINES) |line|
        {
            if (in_mask.isSet( line ))
            {
                self.lines[self.num_lines] = @intCast( line );
                self.num_lines += 1;
            }
        }
    }
};

// -----------------------------------------------------------------------------
/// This struct defines the data for the .get_line_values and .set_line_values
/// ioctl calls.

pub const LineValues = extern struct  //=> struct gpio_v2_line_values
{
    /// The value for each line.
    bits   : u64 align(8),
    /// Which lines to get or set.
    mask   : u64 align(8),
};

// -----------------------------------------------------------------------------
/// The line attribute structure discribes a attirbute that a chip's line
/// might have.

pub const LineAttribute = extern struct //=> struct gpio_v2_line_attribute
{
    /// The time of this attribute.
    id   : ID,
    /// The data for this attribute.
    data : extern union
    {
        flags    : Flags, // if .id is .flags
        values   : u64,   // if .id is .value
        debounce : u32,   // if .id is .debounce
    } align( 8 ),

    pub const ID = enum(u32)  //=> enum gpio_v2_line_attr_id {getLineInfo, watchLineInfo, lineRequest, setLineConfig}
    {
        invalid       = 0,
        flags         = 1,
        value         = 2,
        debounce      = 3,
    };
};

// -----------------------------------------------------------------------------

pub const Flags = packed struct (u64) //=> struct gpio_v2_line_flag {getLineInfo, watchLineInfo}
{
    /// Set true if the line is assigned to a consumer.
    used                  : bool,
    /// Set true if the line is active low.
    active_low            : bool,
    /// Set true if the line is configured as an input line.
    input                 : bool,
    /// Set true if the line is configured as an output line.
    output                : bool,
    edge_rising           : bool,
    edge_falling          : bool,
    /// Set true if the line's output pin is configured as open drain.
    open_drain            : bool,
    /// Set true if the line's output pin is configured as open source.
    open_source           : bool,
    /// Set true if the line's output pin has a pull-up resistor.
    bias_pull_up          : bool,
    /// Set true if the line's output pin has a pull-down resistor.
    bias_pull_down        : bool,
    /// Set true if the line's output pin's bias is disabled.
    bias_disabled         : bool,
    /// Set true if the pin uses the realtiom clock
    event_clock_realtime  : bool,
    /// Set true if the pin uses the hte clock
    event_clock_hte	      : bool,
    pad                   : u51,
};

// -----------------------------------------------------------------------------

pub const InfoEventType = enum(u32)  //=> enum gpiod_info_event_type {getLineInfoEvent}
{
    requested    = 1,
    released     = 2,
    reconfigured = 3,
};

// -----------------------------------------------------------------------------
//  Function ioctl
// -----------------------------------------------------------------------------

pub fn ioctl( in_fd    : std.os.linux.fd_t,
              in_ioctl : Ioctl,
              in_data  : *anyopaque ) !usize
{
    const status : isize = @bitCast( std.os.linux.ioctl(
                                        in_fd,
                                        @intFromEnum( in_ioctl ),
                                        @intFromPtr( in_data ) ) );

    if (status != 0) log.warn( "status: {}", .{ status } );

    if (status >= 0) return @bitCast( status );

    log.err( "result: {}", .{ std.posix.errno( status ) } );

    switch (std.posix.errno( status ))
    {
        .BUSY    => return error.LineBusy,
        .PERM    => return error.PermissionDenied,
        .INVAL   => return error.InvalidRequest,
        .BADF    => unreachable,
        .FAULT   => unreachable,
        .NOTTY   => unreachable,
        else => |err| return std.posix.unexpectedErrno( err ),
    }
}

// -----------------------------------------------------------------------------
//  Function readEvent
// -----------------------------------------------------------------------------
/// Call to read an event from a Chip.
///
/// Caller must have made a watch_line ioctl to tell kernel to generate events.
/// If no event is available this call will block until one becomes available.
/// If you want to test to see if an event is available, use the pollInfoEvent
/// call.
///
/// Parameters:
/// - in_fd      the file descriptor of an open Chip stream
/// - in_timeout timeout in nS.  Pass null for now no timeout.

pub fn readEvent( in_fd     : std.os.linux.fd_t,
                  out_event : *InfoEvent ) !void
{
    const status : isize = @bitCast( std.os.linux.read(
                                        in_fd,
                                        @ptrCast( out_event ),
                                        @sizeOf( InfoEvent ) ) );

    log.warn( "status: {}", .{ status } );

    if (status == @sizeOf( InfoEvent )) return;

    log.err( "result: {}", .{ std.posix.errno( status ) } );

    if (status >= 0) return error.BadRead; // ## TODO ## check this code?

    switch (std.posix.errno( status ))
    {
        .BUSY    => unreachable,
        .PERM    => unreachable,
        .INVAL   => unreachable,
        .BADF    => unreachable,
        .FAULT   => unreachable,
        .NOTTY   => unreachable,
        else => |err| return std.posix.unexpectedErrno( err ),
    }
}

// -----------------------------------------------------------------------------
//  Function pollInfoEvent
// -----------------------------------------------------------------------------
/// Call this to determine if an info event is avaiable to read.
///
/// Parameters:
/// - in_fd      the file descriptor of an open Chip stream
/// - in_timeout timeout in nS.  Pass null for now no timeout.

pub fn pollInfoEvent( in_fd      : std.os.linux.fd_t,
                      in_timeout : ?u64 ) !bool
{
    var timeout : std.os.linux.timespec = undefined;

	if (in_timeout) |t|
    {
		timeout.tv_sec  = @intCast( t / 1_000_000_000 );
		timeout.tv_nsec = @intCast( t % 1_000_000_000 );
	}

    var pollfd : std.os.linux.pollfd = .{ .fd      = in_fd,
                                          .events  =   std.os.linux.POLL.IN
                                                     | std.os.linux.POLL.PRI,
                                          .revents = 0 };

    const status : isize = @bitCast( std.os.linux.ppoll(
                                        @ptrCast( &pollfd ),
                                        1,
                                        if (in_timeout != null) &timeout else null,
                                        null ) );

    log.warn( "status: {any}", .{ status } );

    if (status == 1) return true;
    if (status == 0) return false;

    log.err( "result: {}", .{ std.posix.errno( status ) } );

    switch (std.posix.errno( status ))
    {
        .BUSY    => unreachable,
        .PERM    => unreachable,
        .INVAL   => unreachable,
        .BADF    => unreachable,
        .FAULT   => unreachable,
        .NOTTY   => unreachable,
        else => |err| return std.posix.unexpectedErrno( err ),
    }
}