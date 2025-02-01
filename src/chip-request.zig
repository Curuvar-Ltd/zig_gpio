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

/// This structure is used to request control of lines from the kernel.
/// A line must be successfully requested before it value can be returned.
///
/// Note that many of the functions defined on the Line structure use a u64
/// bitmap to indicate which lines to access or what values to set or return.
/// These bitmaps are reletive to the lines that are "owned" by the bitmap, not
/// all the lines for the chip.
///
/// For example, if this Request "owns" line 4, 7, and 9, then the value for
/// line 4 will be the low order bit and the other bitmap values look like this:
///
///      ~~~~=+---+---+---+
///           | 9 | 7 | 4 |
///      ~~~~=+---+---+---+
///

const std     = @import( "std" );

const Request = @This();
const Chip    = @import( "chip.zig" );
const Line    = @import( "chip-line.zig" );

const log    = std.log.scoped( .chip_request );
const assert = std.debug.assert;


/// The Chip containing the requested lines.
chip      : * const Chip,
/// The stream used to control and read the requested lines.
fd        : ?std.posix.fd_t = null,
/// A bitmap of lines requested -- based on line number on the Chip.
lines     : Chip.LineSet,

// =============================================================================
//  Public Constants
// =============================================================================

pub const Direction = enum{ input, output };
pub const Bias      = enum{ none, pull_up, pull_down };
pub const Edge      = enum{ none, rising, falling, both };
pub const Clock     = enum{ none, realtime, hte };
pub const Drive     = enum{ none, open_drain, open_source, push_pull };

// =============================================================================
//  Private Constants
// =============================================================================

const NS_PER_SEC         = 1_000_000_000;

const MAX_NAME_SIZE      = Chip.MAX_NAME_SIZE;
const MAX_LINES          = Chip.MAX_LINES;
const MAX_LINE_ATTRS     = Chip.MAX_LINE_ATTRS;

const LineSet            = Chip.LineSet;
const LineNum            = Chip.LineNum;
const LineInfo           = Chip.LineInfo;
const Flags              = Chip.Flags;
const LineAttribute      = Chip.LineAttribute;

// =============================================================================
//  Public Structures
// =============================================================================

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
	/// Flags the define the line's state.
	flags             : Flags align(8),
	/// The number of item in the "attrs" array.
	num_attrs         : u32,
	_                 : [5]u32,
	/// Various attributes that might be specified for a line.
	attrs             : [MAX_LINE_ATTRS] extern struct
	{
		attr            : LineAttribute,
		mask            : u64 align(8),
	},
	/// The number of elements in the "lines" array.
	num_lines         : u32,
	/// The size of the event buffer (set to zero for the default size).
	event_buffer_size : u32,
	__                : [5]u32,
	/// Will be set to the file descriptor associated with the request.
	fd                : std.posix.fd_t,

	// -------------------------------------------------------------------------
	//  Public Function LineRequest.buildRequest
	// -------------------------------------------------------------------------
	/// This function files the lines array, and set the num_lines filed
	/// based on a IntegerBitSet indicating the requested lines.

	pub fn buildRequest( self         : *LineRequest,
	                     in_line_mask : ?LineSet,
	                     in_config    : [] const LineConfig ) !void
	{
		var line_mask : LineSet = .{ .mask = 0 };

		self.* = std.mem.zeroes( LineRequest );

		// First add any lines from the line mask to the request.

		if (in_line_mask) |mask|
		{
			line_mask = mask;

			for(0..MAX_LINES) |line_num|
			{
				if (mask.isSet( line_num ))
				{
					self.lines[self.num_lines] = @intCast( line_num );
					self.num_lines += 1;
				}
			}
		}

		// Loop through the LineConfig items...

		for (in_config) |a_config|
		{
			log.warn( "a_config: {any}", .{ a_config } );

			var config_mask : u64 = 0;

			// Make sure all lines to be configured are listed in the
			// "lines" array.

			for (a_config.lines) |a_line|
			{
				// If the line is not already in the "lines" array add it.
				if (!line_mask.isSet( a_line ))
				{
					line_mask.set( a_line );
					self.lines[self.num_lines] = @intCast( a_line );
					self.num_lines += 1;
				}

				const position = std.mem.indexOfScalar( u32,
				                                        &self.lines,
																								a_line );

				config_mask |= @as( u64, 1 ) << @intCast( position.? );
			}

			if (a_config.values) |values|
			{
				if (values.len != a_config.lines.len) return error.WrongNumberOfValues;

				if (self.num_attrs >= MAX_LINE_ATTRS) return error.ToManyAttributes;

				const an_attr = &(self.attrs[self.num_attrs]);
				self.num_attrs += 1;

				var value_bits : u64 = 0;

				for (a_config.lines, 0..) |a_line, i|
				{
					if (values[i])
					{
						const position = std.mem.indexOfScalar( u32,
						                                        &self.lines,
																										a_line );

						value_bits |= @as( u64, 1 ) << @intCast( position.? );
					}
				}

				an_attr.mask             = config_mask;
				an_attr.attr.id          = .values;
				an_attr.attr.data.values = value_bits;
			}

			if (a_config.debounce) |debounce|
			{
				if (self.num_attrs >= MAX_LINE_ATTRS) return error.ToManyAttributes;

				const an_attr = &(self.attrs[self.num_attrs]);
				self.num_attrs += 1;

				an_attr.mask               = config_mask;
				an_attr.attr.id            = .debounce;
				an_attr.attr.data.debounce = debounce;
			}

			var flags     = std.mem.zeroes( Flags );
			var flags_set = false;

			if (a_config.direction) |dir|
			{
				flags_set = true;
				switch (dir)
				{
					.input  => flags.input  = true,
					.output => flags.output = true,
				}
			}

			if (a_config.bias) |bias|
			{
				flags_set = true;
				switch (bias)
				{
					.pull_up =>
					{
						flags.input          = true;
						flags.bias_pull_up   = true;
					},
					.pull_down =>
					{
						flags.input          = true;
						flags.bias_pull_down = true;
					},
					else =>
					{
						flags.input          = true;
						flags.bias_disabled  = true;
					},
				}
			}

			if (a_config.edge) |edge|
			{
				flags_set = true;
				switch (edge)
				{
					.rising =>
					{
						flags.input        = true;
					  flags.edge_rising  = true;
					},
					.falling =>
					{
						flags.input        = true;
					  flags.edge_falling = true;
					},
					.both =>
					{
						flags.input        = true;
						flags.edge_rising  = true;
						flags.edge_falling = true;
					},
					else => continue,
				}
			}

			if (a_config.drive) |drive|
			{
				flags_set = true;
				switch (drive)
				{
					.open_drain  => flags.open_drain  = true,
					.open_source => flags.open_source = true,
					else         => continue,
				}
			}

			if (a_config.clock) |clock|
			{
				flags_set = true;
				switch (clock)
				{
					.realtime  => flags.event_clock_realtime  = true,
					.hte       => flags.event_clock_hte       = true,
					else         => continue,
				}
			}

			if (flags_set)
			{
				if (self.num_attrs >= MAX_LINE_ATTRS) return error.ToManyAttributes;

				const an_attr = &(self.attrs[self.num_attrs]);
				self.num_attrs += 1;

				an_attr.mask            = config_mask;
				an_attr.attr.id         = .flags;
				an_attr.attr.data.flags = flags;
			}
		}
	}
};

// -----------------------------------------------------------------------------
/// This struct is filled by the .get_line_values ioctl and read by the
/// .set_line_values ioctl calls.  It allows quick access to multiple
/// line values simultaniously.
///
/// Note that the bit position in both the bits and mask fields are relative
/// to the request's lines (as defined in Request.LineRequest.lines) not
/// the chip's.  For example, if the request "owns" lines 3, 4, and 5; the
/// low order bit of either bits or mask will represent the chips line 3.

pub const LineValues = extern struct  //=> struct gpio_v2_line_values
{
	/// The value for each line.
	bits   : u64 align(8),
	/// Which lines to get or set.
	mask   : u64 align(8),
};

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
/// This sturcture is read from a Requests's file descriptor by the
/// readEdgeEvent function to advise of a change in a line's settings.

pub const EdgeEvent = extern struct  //=> struct gpiod_edge_event
{
	event_type   : EventType,
	timestamp    : u64,
	line_offset  : u32,
	global_seqno : c_long,
	line_seqno   : c_long,

	pub const EventType = enum(u32) //=> enum gpiod_edge_event_type
	{
		raising  = 1,
		falling  = 2,
	};
};

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub const LineConfig = struct
{
	lines        : [] const LineNum = &.{},
	values       : ?[] const bool   = null,
	direction    : ?Direction       = null,
	bias         : ?Bias            = null,
	edge         : ?Edge            = null,
	drive        : ?Drive           = null,
	clock        : ?Clock           = null,
	debounce     : ?u32             = null,
};

// =============================================================================
//  Public Functions
// =============================================================================

// -----------------------------------------------------------------------------
//  Public Function Request.reserve
// -----------------------------------------------------------------------------
/// Reserve the Request's lines.
///
/// This function request access to the Request's lines and opens a stream
/// that is used to control and read the requested lines.

pub fn reserve( self            : *Request,
								in_consumer     : [] const u8,
								in_evt_buf_size : u32,
								in_config       : [] const LineConfig  ) !void
{
	assert( in_consumer.len <= MAX_NAME_SIZE );

	self.release();

	var req : LineRequest = undefined;

	try req.buildRequest( self.lines, in_config );

	// Note to self: These MUST come after the buildRequest call:

	std.mem.copyForwards( u8, &req.consumer, in_consumer );
	req.event_buffer_size = in_evt_buf_size;

	_ = try Chip.ioctl( self.chip.fd, .line_request, &req );

	self.fd = req.fd;
}

// -----------------------------------------------------------------------------
//  Public Function Request.deinit
// -----------------------------------------------------------------------------
/// Close the stream for this Request.

pub fn release( self : *Request ) void
{
	if (self.fd) |fd|
	{
		_ = std.os.linux.close( fd );
		self.fd = null;
	}
}

// -----------------------------------------------------------------------------
//  Public Function line
// -----------------------------------------------------------------------------
/// Return a Line struct used to control a single line from this request.
///
/// This function may be called before the Request's reserve function is
/// called.

pub inline fn line( self : *Request, in_line : LineNum ) !Line
{
	if (!self.lines.isSet( in_line )) return error.InvalidRequest;

	const the_line : Line =  .{ .chip     = self.chip,
	                         .request  = self,
	                         .line_num = in_line };
	return the_line;
}

// -----------------------------------------------------------------------------
//  Public Function getLineInfo
// -----------------------------------------------------------------------------
/// Fill in LineInfo structure for a given line.
///
/// This function allows raw access to the .line_info ioctl.

pub inline fn getLineInfo( self     : Request,
                           in_line  : LineNum,
                           out_info : *LineInfo ) !void
{
	try self.chip.getLineInfo( in_line, out_info );
}

// -----------------------------------------------------------------------------
//  Public Function Request.setLineConfig
// -----------------------------------------------------------------------------
/// Update the confguration of selected line.

pub fn setLineConfig( self      : * const Request,
                      in_config : [] const LineConfig ) !void
{
	if (self.fd) |fd|
	{
		var req : LineRequest = undefined;

		try req.buildRequest( null, in_config );

		_ = try Chip.ioctl( fd, .set_line_config, &req );

		return;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
//  Public Function getLineValuesMasked
// -----------------------------------------------------------------------------
/// Get a subset of the lines simultaniously as a bitmask.
///
/// Parameters:
/// - in_mask   - a bitmask indicating the lines to get

pub fn getLineValuesMasked( self    : Request,
                            in_mask : u64 ) !u64
{
	if (self.fd) |fd|
	{
		var lv : LineValues = .{ .bits = 0, .mask = in_mask };

		_ = try Chip.ioctl( fd, .get_line_values, &lv );

		return lv.bits;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
//  Public Function getLineValues
// -----------------------------------------------------------------------------
/// Returns the a slice of optional booleans indexed by line number.
///
/// The length of the slice is the number of lines that this Request's
/// unterlying Chip has (not the number of requesed lines).
///
/// The value of each returned item is:
/// - true  - the line is part of this request and is asserted
/// - false - the line is part of this request and is not asserted
/// - null  - the line is not part of this request.

pub fn getLineValues( self : Request ) ![]?bool
{
	if (self.fd) |fd|
	{
		var lv : LineValues = .{ .bits = 0,
		                      .mask = 0xFFFF_FFFF_FFFF_FFFF };

		_ = try Chip.ioctl( fd, .get_line_values, &lv );

		var retval = try self.chip.allocator.alloc( ?bool,
		                                            self.chip.info.line_count );

		errdefer self.chip.allocator.free( retval );

		var line_index : LineNum = 0;
		var bit_mask   : u64          = 1;

		for (0..self.chip.info.line_count) |i|
		{
			if (self.lines.isSet( line_index ))
			{
				retval[i] = (lv.bits & bit_mask) != 0;
				bit_mask <<= 1;
			}
			else
			{
				retval[i] = null;
			}

			line_index += 1;
		}

		return retval;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
//  Public Function getLineValue
// -----------------------------------------------------------------------------
/// Returns the value of a specific line
///
/// The value returned is:
/// - true  - the line is asserted
/// - false - the line is not asserted
///

pub fn getLineValue( self : Request, in_line : LineNum ) !bool
{
	if (!self.lines.isSet( in_line )) return error.NotRequested;

	if (self.fd) |fd|
	{
		var lv : LineValues = .{ .bits = 0,
		                         .mask = 0xFFFF_FFFF_FFFF_FFFF };

		_ = try Chip.ioctl( fd, .get_line_values, &lv );

		var line_index : LineNum = 0;
		var bit_mask   : u64          = 1;

		for (0..self.chip.info.line_count) |i|
		{
			if (self.lines.isSet( line_index ))
			{
				if (i == in_line) return  (lv.bits & bit_mask) != 0;
				bit_mask <<= 1;
			}

			line_index += 1;
		}

		unreachable;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
//  Public Function setLineValuesMasked
// -----------------------------------------------------------------------------
/// Set a subset of the lines simultaniously.
///
/// Parameters:
/// - in_mask   - a bitmask indicating the lines to set
/// - in_values - the values to set the lines to

pub fn setLineValuesMasked( self      : Request,
                            in_mask   : u64,
                            in_values : u64 ) !void
{
	if (self.fd) |fd|
	{
		var lv : LineValues = .{ .bits = in_values, .mask = in_mask };

		_ = try Chip.ioctl( fd, .set_line_values, &lv );

		return;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
//  Public Function setLineValues
// -----------------------------------------------------------------------------
// /// Set a multiple lines simultaniously.
// ///
// /// Parameters
// /// - in_line_values - a slice of line/value pairs.
// ///
// /// Note: If a specific line is specified more than once in the slice, then
// ///       if any mention of the line specifies the line as active the line
// ///       will be set active


// pub fn setLineValues( self : Chip, in_values : [] const PerLineValue ) !void
// {
//     if (in_values.len == 0) return;

//     var lv = LineValues{ .bits = 0, .mask = 0 };

//     for (in_values) |a_line_value|
//     {
//         const mask = @as( u64, 1 ) << a_line_value.line;

//         lv.mask |= mask;

//         if (a_line_value.value == .active)
//         {
//             lv.bits |= mask;
//         }
//     }

//     _ = try self.ioctl( .set_line_values, &lv );
// }

// -----------------------------------------------------------------------------
//  Public Function setLineValue
// -----------------------------------------------------------------------------
/// Set the value of a specific line
///
/// - true  - the line is asserted
/// - false - the line is not asserted
///

pub fn setLineValue( self     : Request,
                     in_line  : LineNum,
                     in_value : bool ) !void
{
	if (!self.lines.isSet( in_line )) return error.NotRequested;

	if (self.fd) |fd|
	{
		var line_index : LineNum = 0;
		var bit_mask   : u64     = 1;

		for (0..self.chip.info.line_count) |i|
		{
			if (self.lines.isSet( line_index ))
			{
				if (i == in_line)
				{
					var lv : LineValues = .{ .bits = if (in_value) bit_mask else 0,
																		.mask = bit_mask };

					_ = try Chip.ioctl( fd, .set_line_values, &lv );

					return;
				}
				bit_mask <<= 1;
			}

			line_index += 1;
		}

		unreachable;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
//  Public Function getEdgeEvent
// -----------------------------------------------------------------------------

pub inline fn getEdgeEvent( self      : Request,
                            out_event : []EdgeEvent ) !usize
{
	return try Chip.readEvent( EdgeEvent, self.fd, out_event );
}

// -----------------------------------------------------------------------------
//  Public Function waitForEdgeEvent
// -----------------------------------------------------------------------------

pub inline fn waitForEdgeEvent( self       : Request,
                                in_timeout : ?u64 ) !usize
{
	return try Chip.pollEvent( EdgeEvent, self.fd, in_timeout );
}
