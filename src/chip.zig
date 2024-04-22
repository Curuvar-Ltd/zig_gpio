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
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
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
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

/// Access the Linux GPIO Chip interface

const std = @import( "std" );

const Chip    = @This();
const Request = @import( "chip-request.zig" );

const log    = std.log.scoped( .chip );
const assert = std.debug.assert;

// =============================================================================
//  Chip Fields
// =============================================================================

allocator  : std.mem.Allocator   = undefined,
path       : ?[] const u8        = null,
fd         : std.posix.fd_t      = undefined,

info       : extern struct
             {
                name       : [MAX_NAME_SIZE:0]u8,
                label      : [MAX_NAME_SIZE:0]u8,
                line_count : u32,
             } = undefined,

line_names : [][] const u8 = undefined,

// =============================================================================
//  Public Constants
// =============================================================================


// =============================================================================
//  Private Constants
// =============================================================================

const MAX_NAME_SIZE      = 31;
const MAX_LINES          = 64;
const MAX_LINE_ATTRS     = 10;

const Ioctl = enum(u32)
{
    get_info            = 0x8044B401,
    line_info           = 0xC100B405,
    watch_line_info     = 0xC100B406,
    line_request        = 0xC250B407,
    unwatch_line_info   = 0xC004B40C,
    set_line_config     = 0xC110B40D,
    get_line_values     = 0xC010B40E,
    set_line_values     = 0xC010B40F,
};

pub const LineAttrID = enum(u32)  //=> enum gpio_v2_line_attr_id {getLineInfo, watchLineInfo, lineRequest, setLineConfig}
{
    invalid       = 0,
    flags         = 1,
    output_values = 2,
    debounce      = 3,
};

// =============================================================================
//  Public Structures
// =============================================================================

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub const Flags = packed struct (u64) //=> struct gpio_v2_line_flag {getLineInfo, watchLineInfo}
{
    used                  : bool,
    active_low            : bool,
    input                 : bool,
    output                : bool,
    edge_rising           : bool,
    edge_falling          : bool,
    open_drain            : bool,
    open_source           : bool,
    bias_pull_up          : bool,
    bias_pull_down        : bool,
    bias_disabled         : bool,
    event_clock_realtime  : bool,
    event_clock_hte	      : bool,
    pad                   : u51,
};

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
/// The line info structure contains basic data about each line of a chip.

pub const LineInfo = extern struct //=> struct gpio_v2_line_info {getLineInfo, watchLineInfo}
{
    name      : [MAX_NAME_SIZE:0]u8,
    consumer  : [MAX_NAME_SIZE:0]u8,
    offset    : u32,
    num_attrs : u32,
    flags     : Flags align(8),
    attrs     : [MAX_LINE_ATTRS]LineAttribute,
    padding   : [4]u32,
};

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub const LineRequest = extern struct //=> struct gpio_v2_line_request {lineRequest, setLineConfig}
{
    lines             : [MAX_LINES]u32,
    consumer          : [MAX_NAME_SIZE:0]u8,
    config            : LineConfig,
    num_lines         : u32,
    event_buffer_size : u32,
    padding           : [5]u32,
    fd                : std.posix.fd_t,

    // -------------------------------------------------------------------------

    pub fn fillLines( self : *LineRequest, in_mask : u64 ) void
    {
        self.num_lines = 0;

        var mask = in_mask;

        for(0..MAX_LINES) |line|
        {
            if (mask == 0) return;

            if ((mask & 1) != 0)
            {
                self.lines[self.num_lines] = @intCast( line );
                self.num_lines += 1;
            }

            mask >>= 1;
        }
    }
};

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub const LineConfig = extern struct  //=> struct gpio_v2_line_config {lineRequest, setLineConfig}
{
    flags     : u64 align(8),
    num_attrs : u32,
    padding   : [5]u32,
    attrs     : [MAX_LINE_ATTRS]LineConfigAttribute,
};

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub const LineConfigAttribute = extern struct //=> struct gpio_v2_line_config_attribute {lineRequest, setLineConfig}
{
    attr : LineAttribute,
    mask : u64 align(8),
};

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
/// The line attribute structure discribes attirbutes that a chip's line
/// might have.

pub const LineAttribute = extern struct //=> struct gpio_v2_line_attribute {getLineInfo, watchLineInfo, lineRequest, setLineConfig}
{
    id   : LineAttrID,
    data : extern union
    {
        flags           : u64,
        value           : u64,
        debounce_period : u32,
    } align( 8 ),
};

// =============================================================================
//  Public Functions
// =============================================================================

// -----------------------------------------------------------------------------
//  Public Function init
// -----------------------------------------------------------------------------
/// Initialize the chip structure.
///
/// This functuon attempts to open the chip's pseudo-file and, if successful,
/// populates the Chip structure.
///
/// Params:
/// - in_allocater - an allocator to use for chip operations.
/// - in_path      - the path to the chips file (e.g.: /dev/gpiochip0)

pub fn init( self         : *Chip,
             in_allocator : std.mem.Allocator,
             in_path      : [] const u8 ) !void
{
    self.fd = try std.posix.open( in_path,
                                  .{ .ACCMODE = .RDWR, .CLOEXEC = true },
                                  0 );

    errdefer std.posix.close( self.fd );

    log.debug( "chip open {}", .{ self.fd } );

    self.allocator = in_allocator;

    self.path = try self.allocator.dupe( u8, in_path );

     _ = try ioctl( self.fd, .get_info, &self.info );

    log.debug( "get info -- line_count = {}", .{ self.info.line_count } );

     self.line_names = try self.allocator.alloc( [] const u8, self.info.line_count );
     errdefer self.allocator.free( self.line_names );

    for (self.line_names, 0..) |*a_name, i|
    {
        var line_info = std.mem.zeroes( LineInfo );
        line_info.offset = @intCast( i );
        _ = try ioctl( self.fd, .line_info, &line_info );

        const len = std.mem.indexOfSentinel( u8, 0, &line_info.name );

        a_name.* = try self.allocator.dupe( u8, line_info.name[0..len] );
    }
}

// -----------------------------------------------------------------------------
//  Public Function deinit
// -----------------------------------------------------------------------------
/// Close the chip's file and clean up the Chip structure.

pub fn deinit( self : *Chip ) void
{
    if (self.path) |path|
    {
        for (self.line_names) |a_name|
        {
            self.allocator.free( a_name );
        }

        self.allocator.free( self.line_names );
        std.posix.close( self.fd );
        self.allocator.free( path );
        self.path = null;
    }
}

// -----------------------------------------------------------------------------
//  Public Function request
// -----------------------------------------------------------------------------
/// Create a Request structure for this chip that will request the provided
/// lines.

pub fn request( self : *Chip, in_lines : [] const u6 ) Request
{
    var lines : u64 = 0;

    for (in_lines) |a_line| lines |= @as( u64, 1 ) << a_line;

    return .{ .chip = self, .lines = lines };
}

// -----------------------------------------------------------------------------
//  Public Function lineFromName
// -----------------------------------------------------------------------------
/// Given a name, return the line number with that name, or  error.NotFound.

pub fn lineFromName( self : Chip, in_name : [] const u8 ) !u6
{
    for (self.line_names, 0..) |a_name, i|
    {
        if (std.mem.eql( u8, in_name, a_name )) return @intCast( i );
    }

    return error.NotFound;
}

// -----------------------------------------------------------------------------
//  Function ioctl
// -----------------------------------------------------------------------------

pub fn ioctl( in_fd    : std.os.linux.fd_t,
              in_ioctl : Ioctl,
              in_data  : *anyopaque ) !usize
{
    const status = std.os.linux.ioctl( in_fd,
                                       @intFromEnum( in_ioctl ),
                                       @intFromPtr( in_data ) );

    if (status >= 0) return @intCast( status );

    log.err( "ioctl result: {}", .{ std.posix.errno( status ) } );

    switch (std.posix.errno( status ))
    {
        .SUCCESS => return,
        .BADF => unreachable,
        .FAULT => unreachable,
        .INVAL => unreachable,
        .ENOTTY => unreachable,
        else => |err| return std.posix.unexpectedErrno( err ),
    }
}

// =============================================================================
//  Testing
// =============================================================================

const testing   = std.testing;

const chip_path =  "/dev/gpiochip0";

// -----------------------------------------------------------------------------

test "Chip"
{
    var chip : Chip = .{};

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try testing.expect( chip.fd != 0xFFFF_FFFF );

    log.warn( "", .{} );
    log.warn( "chip info.name:       {s}", .{ chip.info.name } );
    log.warn( "chip info.label:      {s}", .{ chip.info.label } );
    log.warn( "chip info.line_count: {}",  .{ chip.info.line_count } );
    log.warn( "", .{} );
}

// -----------------------------------------------------------------------------

test "line from name"
{
    var chip : Chip = .{};

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try testing.expectEqual( 22, chip.lineFromName( "GPIO22" ) );
}
