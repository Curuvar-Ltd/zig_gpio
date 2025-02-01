// zig fmt: off

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
const Line    = @import( "chip-line.zig" );

const log     = std.log.scoped( .chip );
const assert  = std.debug.assert;

// =============================================================================
//  Chip Fields
// =============================================================================

allocator  : std.mem.Allocator   = undefined,
path       : ?[] const u8        = null,
fd         : std.posix.fd_t      = undefined,
info       : ChipInfo            = undefined,
line_names : [][] const u8       = undefined,

// =============================================================================
//  Public Constants
// =============================================================================

pub const LineSet = std.bit_set.IntegerBitSet( MAX_LINES );
pub const LineNum = std.math.IntFittingRange( 0, MAX_LINES - 1 );

pub const MAX_NAME_SIZE      = 31;
pub const MAX_LINES          = 64;
pub const MAX_LINE_ATTRS     = 10;

// =============================================================================
//  Private Constants
// =============================================================================

// -----------------------------------------------------------------------------
/// These are the Ioctl call values that the GPIO system uses.

const Ioctl = enum(u32)
{
		// Ioctl values that use the Chip's file descriptor

		/// Read information about a chip into the Chip.ChipInfo structure.
		get_info            = 0x8044B401,  // Data: &ChipInfo
		/// Read information about a line into the Chip.LineInfo structure.
		/// Note: this does not return the lines value (or any other ".attrs").
		line_info           = 0xC100B405,  // Data: &LineInfo
		/// Read information about a line into the Chip.LineInfo structure and
		/// start watching the line.
		watch_line          = 0xC100B406,  // Data: &LineInfo
		/// Request control over a set of lines and set initial line configuration
		/// based on a pre-filled Request.LineRequest structure.  This ioctl
		/// opens a file descriptor that is used to control the requested line
		/// and returns it in the fd field.
		line_request        = 0xC250B407,  // Data: &LineRequest
		/// Stop watching a line.
		unwatch_line        = 0xC004B40C,  // Data: &usize (line number)

		// Ioctl values that use the Request's file descriptor
		/// Update the line configuration of lines that have previously been
		/// requested based on a pre-fille Request.LineRequest structure.
		set_line_config     = 0xC110B40D,  // Data: &LineRequest

		/// Read
		get_line_values     = 0xC010B40E,  // Data: &LineValues
		set_line_values     = 0xC010B40F,  // Data: &LineValues
};

// =============================================================================
//  Public Structures
// =============================================================================

// -----------------------------------------------------------------------------
/// This structure is used to get information about the Chip itself.
/// It is filled by the .get_info ioctl.

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
/// This structure contains information about a specific line on a Chip.
/// It is filled by the .line_info and .watch_line_info ioctls.
/// It is also used as part of the data returned by an InfoEvent.
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
		attrs     : [MAX_LINE_ATTRS] LineAttribute,
		_         : [4]u32,
};

// -----------------------------------------------------------------------------
/// This stucture describes the data returned by an info event.  These are
/// read from the Chip's file descriptor by the getInfoEvent function.
///
/// Info events are provided after makeing a WatchLine call.

pub const InfoEvent = extern struct
{
		event_type : EventType,
		timestamp  : u64,
		info       : LineInfo,

		pub const EventType = enum(u32)  //=> enum gpiod_info_event_type {getLineInfoEvent}
		{
				requested    = 1,
				released     = 2,
				reconfigured = 3,
		};
};

// -----------------------------------------------------------------------------
/// The line attribute structure discribes a attirbute that a chip's line
/// might have. It is filled as part of the Chip's LineInfo structure and
/// read as part of a Request's LineRequest structure.
///
/// This struct forms a type of tagged union.  The id value indicates the
/// type of the attribute, and the appropriate data element holds the value.
///
/// See the description of the LineInfo and LineRequest for more information
/// about the use of the structure.

pub const LineAttribute = extern struct //=> struct gpio_v2_line_attribute
{
	/// The type of this attribute.
	id   : ID,
	/// The data for this attribute.
	data : extern union
	{
		flags    : Flags, // if .id is .flags
		values   : u64,   // if .id is .values
		debounce : u32,   // if .id is .debounce
	} align( 8 ),

	pub const ID = enum(u32)  //=> enum gpio_v2_line_attr_id {getLineInfo, watchLineInfo, lineRequest, setLineConfig}
	{
		invalid       = 0,
		flags         = 1,
		values        = 2,
		debounce      = 3,
	};
};

// -----------------------------------------------------------------------------
/// This is a bitmap indicating various attibutes a line might have.  It forms
/// part of the LineInfo, LineAttribute, and LineRequest structure definitions.

pub const Flags = packed struct (u64) //=> struct gpio_v2_line_flag {getLineInfo, watchLineInfo}
{
	/// Set true if the line is assigned to a consumer.
	used                  : bool = false,
	/// Set true if the line is active low.
	active_low            : bool = false,
	/// Set true if the line is configured as an input line.
	input                 : bool = false,
	/// Set true if the line is configured as an output line.
	output                : bool = false,
	edge_rising           : bool = false,
	edge_falling          : bool = false,
	/// Set true if the line's output pin is configured as open drain.
	open_drain            : bool = false,
	/// Set true if the line's output pin is configured as open source.
	open_source           : bool = false,
	/// Set true if the line's output pin has a pull-up resistor.
	bias_pull_up          : bool = false,
	/// Set true if the line's output pin has a pull-down resistor.
	bias_pull_down        : bool = false,
	/// Set true if the line's output pin's bias is disabled.
	bias_disabled         : bool = false,
	/// Set true if the pin uses the realtiom clock
	event_clock_realtime  : bool = false,
	/// Set true if the pin uses the hte clock
	event_clock_hte	      : bool = false,
	_                     : u51  = 0,
};

// =============================================================================
//  Public Functions
// =============================================================================

// -----------------------------------------------------------------------------
//  Public Function Chip.init
// -----------------------------------------------------------------------------
/// Initialize the chip structure.
///
/// This functuon attempts to open the chip's pseudo-file and, if successful,
/// returns a populated Chip structure.
///
/// Params:
/// - in_allocater - an allocator to use for chip operations.
/// - in_path      - the path to the chips file (e.g.: /dev/gpiochip0)

pub fn init( in_allocator : std.mem.Allocator,
            in_path      : [] const u8 ) !Chip
{
	var chip : Chip = .{ .allocator = in_allocator };

	chip.fd = try std.posix.open( in_path,
	                              .{ .ACCMODE = .RDWR, .CLOEXEC = true },
	                              0 );

	errdefer std.posix.close( chip.fd );

	log.debug( "chip open {}", .{ chip.fd } );

	chip.path = try in_allocator.dupe( u8, in_path );
	errdefer in_allocator.free( chip.path.? );

	_ = try ioctl( chip.fd, .get_info, &chip.info );

	log.debug( "get info -- line_count = {}", .{ chip.info.line_count } );

	chip.line_names = try in_allocator.alloc( [] const u8,
	                                          chip.info.line_count );

	errdefer in_allocator.free( chip.line_names );

	for (chip.line_names, 0..) |*a_name, i|
	{
		var line_info = std.mem.zeroes( LineInfo );
		line_info.line = @intCast( i );
		_ = try ioctl( chip.fd, .line_info, &line_info );

		const len = std.mem.indexOfSentinel( u8, 0, &line_info.name );

		a_name.* = try in_allocator.dupe( u8, line_info.name[0..len] );
	}

	return chip;
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
/// Note that the order in which the lines number are listed in in_lines is
/// not significant.  The retured Request sturcture will handle the lines
/// in numerical order.

pub fn request( self        : * const Chip,
                in_lines    : [] const LineNum ) !Request
{
	var req = Request{ .chip  = self,
	                   .lines = std.mem.zeroes( LineSet ) };

	for (in_lines) |a_line|
	{
		if (a_line >= self.line_names.len) return error.InvalidRequest;

		req.lines.set( a_line );
	}

	return req;
}

// -----------------------------------------------------------------------------
//  Public Function line
// -----------------------------------------------------------------------------
/// Return a Line struct that can be used to get (not set) information about a
/// single line from this chip.
///
/// Note: trying to use any of the Line's "set..." functions will result
/// in a NotOpen error.  To use the "set..." functions, the Line must be
/// created using the Request struct's "line" funciton.
///

pub inline fn line( self : * const Chip, in_line : LineNum ) !Line
{
	if (in_line >= self.line_names.len) return error.InvalidRequest;

	return .{ .chip = self, .request = null, .line_num = in_line };
}

// -----------------------------------------------------------------------------
//  Public Function Chip.lineNumFromName
// -----------------------------------------------------------------------------
/// Given a name, return the line number with that name, or  error.NotFound.

pub fn lineNumFromName( self : Chip, in_name : [] const u8 ) !LineNum
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
                    out_info : *LineInfo ) !void
{
	out_info.* = std.mem.zeroes( LineInfo );
	out_info.line = @intCast( in_line );
	_ = try ioctl( self.fd, .line_info, out_info );
}

// -----------------------------------------------------------------------------
//  Public Function Chip.watchLine
// -----------------------------------------------------------------------------
/// Start watching a given line.
///
/// This function allows raw access to the .watch_line ioctl.

pub fn watchLine( self     : Chip,
                  in_line  : LineNum,
                  out_info : *LineInfo ) !void
{
	out_info.* = std.mem.zeroes( LineInfo );
	out_info.line = @intCast( in_line );
	_ = try ioctl( self.fd, .watch_line, out_info );
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
	var lineNum : u32 = @intCast( in_line );

	_ = try ioctl( self.fd, .unwatch_line, &lineNum );
}

// -----------------------------------------------------------------------------
//  Public Function Chip.getInfoEvent
// -----------------------------------------------------------------------------

pub inline fn getInfoEvent( self      : Chip,
                            out_event : []InfoEvent ) !usize
{
	return try readEvent( InfoEvent, self.fd, out_event );
}

// -----------------------------------------------------------------------------
//  Public Function Chip.waitForInfoEvent
// -----------------------------------------------------------------------------

pub inline fn waitForInfoEvent( self       : Chip,
                                in_timeout : ?u64 ) !usize
{
	return try pollEvent( InfoEvent, self.fd, in_timeout );
}

// -----------------------------------------------------------------------------
//  Function ioctl
// -----------------------------------------------------------------------------

pub fn ioctl( in_fd    : std.os.linux.fd_t,
              in_ioctl : Ioctl,
              in_data  : *anyopaque ) !usize
{
	// We use std.os.linux.ioctl insted of srd.posix.ioctl because we
	// want to handle certain status values be returning errors instead
	// of using "unreachable".

	// Oh, and the fact that, at the time of this writing, there was
	// no posix.ioctl defined in the Zig standard library.

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
/// Call to read an event from a Chip or Request file descriptor.

pub fn readEvent( T          : anytype,
                  in_fd      : std.os.linux.fd_t,
                  out_events : []T ) !usize
{
	const byte_len         = @sizeOf( T ) * out_events.len;
	const byte_ptr : [*]u8 = @ptrCast( out_events.ptr );

	const size = try std.posix.read( in_fd, byte_ptr[0..byte_len] );

	return size / @sizeOf( T );
}

// -----------------------------------------------------------------------------
//  Function pollEvent
// -----------------------------------------------------------------------------
/// Call this to determine if an event is avaiable to read.
///
/// Parameters:
/// - in_fd      the file descriptor of an open Chip or Request stream
/// - in_timeout timeout in nS.  Pass null for now no timeout.
///
/// Return the number of items of type T that can be read.

pub fn pollEvent( T          : anytype,
                  in_fd      : std.os.linux.fd_t,
                  in_timeout : ?u64 ) !usize
{
	var timeout : std.os.linux.timespec = undefined;

	if (in_timeout) |t|
		{
		timeout.tv_sec  = @intCast( t / 1_000_000_000 );
		timeout.tv_nsec = @intCast( t % 1_000_000_000 );
	}

	var pollfd : [1]std.posix.pollfd = .{ .{ .fd      = in_fd,
	                                         .events  =   std.os.linux.POLL.IN
	                                                    | std.os.linux.POLL.PRI,
	                                         .revents = 0 } };

	const size = try std.posix.ppoll( @ptrCast( &pollfd ),
	                                  if (in_timeout != null) &timeout else null,
	                                  null );

	return size / @sizeOf( T );
}