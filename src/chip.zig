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

/// Access the Linux GPIO Chip interface

const std = @import( "std" );

const Chip    = @This();
const Request = @import( "chip-request.zig" );
const GPIO    = @import( "gpio.zig" );

const log     = std.log.scoped( .chip );
const assert  = std.debug.assert;

// =============================================================================
//  Chip Fields
// =============================================================================

allocator  : std.mem.Allocator   = undefined,
path       : ?[] const u8        = null,
fd         : std.posix.fd_t      = undefined,
info       : GPIO.ChipInfo       = undefined,
line_names : [][] const u8       = undefined,

// =============================================================================
//  Public Constants
// =============================================================================

pub const LineSet = std.StaticBitSet( GPIO.MAX_LINES );
pub const LineNum = std.math.IntFittingRange( 0, GPIO.MAX_LINES - 1 );

// =============================================================================
//  Public Functions
// =============================================================================

// -----------------------------------------------------------------------------
//  Public Function Chip.init
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

     _ = try GPIO.ioctl( self.fd, .get_info, &self.info );

    log.debug( "get info -- line_count = {}", .{ self.info.line_count } );

     self.line_names = try self.allocator.alloc( [] const u8,
                                                 self.info.line_count );

     errdefer self.allocator.free( self.line_names );

    for (self.line_names, 0..) |*a_name, i|
    {
        var line_info = std.mem.zeroes( GPIO.LineInfo );
        line_info.line = @intCast( i );
        _ = try GPIO.ioctl( self.fd, .line_info, &line_info );

        const len = std.mem.indexOfSentinel( u8, 0, &line_info.name );

        a_name.* = try self.allocator.dupe( u8, line_info.name[0..len] );
    }
}

// -----------------------------------------------------------------------------
//  Public Function Chip.deinit
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
//  Public Function Chip.request
// -----------------------------------------------------------------------------
/// Create a Request structure for this chip that will request the provided
/// lines.
///
/// This function may be called before the Chip's init function is called.
///
/// The Request's init function must be called before using the request.

pub fn request( self : *Chip, in_lines : [] const LineNum ) Request
{
    var req = Request{ .chip  = self,
                       .lines = std.mem.zeroes( LineSet ) };

    for (in_lines) |a_line| req.lines.set( a_line );

    return req;
}

// -----------------------------------------------------------------------------
//  Public Function Chip.lineFromName
// -----------------------------------------------------------------------------
/// Given a name, return the line number with that name, or  error.NotFound.

pub fn lineFromName( self : Chip, in_name : [] const u8 ) !LineNum
{
    for (self.line_names, 0..) |a_name, i|
    {
        if (std.mem.eql( u8, in_name, a_name )) return @intCast( i );
    }

    return error.NotFound;
}

// -----------------------------------------------------------------------------
//  Public Function Chip.getLineInfo
// -----------------------------------------------------------------------------
/// Fill in LineInfo structure for a given line.
///
/// This function allows raw access to the .line_info ioctl.

pub fn getLineInfo( self     : Chip,
                    in_line  : LineNum,
                    out_info : *GPIO.LineInfo ) !void
{
    out_info.* = std.mem.zeroes( GPIO.LineInfo );
    out_info.line = @intCast( in_line );
    _ = try GPIO.ioctl( self.fd, .line_info, out_info );
}

// -----------------------------------------------------------------------------
//  Public Function Chip.watchLine
// -----------------------------------------------------------------------------
/// Start watching a given line.
///
/// This function allows raw access to the .watch_line ioctl.

pub fn watchLine( self     : Chip,
                  in_line  : LineNum,
                  out_info : *GPIO.LineInfo ) !void
{
    out_info.* = std.mem.zeroes( GPIO.LineInfo );
    out_info.line = @intCast( in_line );
    _ = try GPIO.ioctl( self.fd, .watch_line, out_info );
}

// -----------------------------------------------------------------------------
//  Public Function Chip.unwatchLine
// -----------------------------------------------------------------------------
/// Stop watching a given line.
///
/// This function allows raw access to the .line_info ioctl.

pub fn unwatchLine( self     : Chip,
                    in_line  : LineNum ) !void
{
    var line : u32 = @intCast( in_line );

    _ = try GPIO.ioctl( self.fd, .unwatch_line, &line );
}

// -----------------------------------------------------------------------------
//  Public Function Chip.getInfoEvent
// -----------------------------------------------------------------------------

pub fn getInfoEvent( self      : Chip,
                     out_event : *GPIO.InfoEvent ) !void
{
    out_event.* = std.mem.zeroes( GPIO.InfoEvent );

    try GPIO.readEvent( self.fd, out_event );
}

// -----------------------------------------------------------------------------
//  Public Function Chip.waitForInfoEvent
// -----------------------------------------------------------------------------

pub fn waitForInfoEvent( self       : Chip,
                         in_timeout : ?u64 ) !bool
{
    return try GPIO.pollInfoEvent( self.fd, in_timeout );
}

