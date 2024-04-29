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

/// This structure is used to control a single line_num.

////////////////////////////////////////////////////////////
//  set_offsets
//    .num_line <== config->num_configs
//    .lines[n] <== config->line_configs[n].offset
//  set_output_values
//    add a single ".values" entry to .attrs with .attr.values <== val
//       and .mask = mask (kernel)
//    .num_attrs += 1;
//  set_debounce_periods
//    add a multiple ".debounce" entry to .attrs with .attr.debounce <== val
//       and .mask = mask (kernel) pins to get the debounce
//    .num_attrs += 1;
//  set_flags
//    fill global flags first then add .flags entry to .attrs.
//
////////////////////////////////////////////////////////////

const std     = @import( "std" );

const Line    = @This();
const Chip    = @import( "chip.zig" );
const Request = @import( "chip-request.zig" );

const log    = std.log.scoped( .chip_request_line );
const assert = std.debug.assert;

/// The Chip contining the requested lines.
chip     : * const Chip,
/// The line number within the chip.
line_num : Chip.LineNum,
/// A Request, that should contain the line.  If the indicated request
/// does not contain the line or is null, this Line structure can only
/// be used to read values and settings.
request  : ?* const Request,

// =============================================================================
//  Private Constants
// =============================================================================

const Direction      = Request.Direction;
const Bias           = Request.Bias;
const Edge           = Request.Edge;
const Clock          = Request.Clock;
const Drive          = Request.Drive;
const LineRequest    = Request.LineRequest;

const LineInfo       = Chip.LineInfo;


// =============================================================================
//  Public Functions
// =============================================================================

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn value( self : Line ) !bool
{
	if (self.request) |req|
	{
		return try req.getLineValue( self.line_num );
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setValue( self : Line, in_value : bool ) !void
{
	if (self.request) |req|
	{
		try req.setLineValue( self.line_num, in_value );
		return;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub inline fn getInfo( self : Line, out_info : *LineInfo ) !void
{
	try self.chip.getLineInfo( self.line_num, out_info );
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn direction( self : Line ) !Direction
{
	var info : LineInfo = undefined;

	try self.getInfo( &info );

	if (info.flags.output) return .output;
	if (info.flags.input)  return .input;

	return error.InvalidDirection;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setDirection( self : Line, in_direction : Direction ) !void
{
	if (self.request) |req|
	{
		try req.setLineConfig( &.{ .{ .lines     = &.{ self.line_num },
		                              .direction = in_direction } } );
		return;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn bias( self : Line ) !Bias
{
	var info : LineInfo = undefined;

	try self.getInfo( &info );

	if (info.flags.bias_pull_up)   return .pull_up;
	if (info.flags.bias_pull_down) return .pull_down;

	return .none;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setBias( self : Line, in_bias : Bias ) !void
{
	if (self.request) |req|
	{
		try req.setLineConfig( &.{ .{ .lines = &.{ self.line_num },
		                              .bias  = in_bias } } );
		return;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn edge( self : Line ) !Edge
{
	var info : LineInfo = undefined;

	try self.getInfo( &info );

	if (!info.flags.edge_rising)
	{
		if (!info.flags.edge_falling) return .none;
		return .falling;
	}

	if (!info.flags.edge_falling) return .rising;

	return .both;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setEdge( self : Line, in_edge : Edge ) !void
{
	if (self.request) |req|
	{
		try req.setLineConfig( &.{ .{ .lines = &.{ self.line_num },
		                              .edge  = in_edge } } );

		return;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn drive( self : Line ) !Drive
{
	var info : LineInfo = undefined;

	try self.getInfo( &info );

	if (!info.flags.open_drain)
	{
		if (!info.flags.open_source) return .none;
		return .open_source;
	}

	if (!info.flags.open_source) return .open_drain;

	return .push_pull;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setDrive( self : Line, in_drive : Drive ) !void
{
	if (self.request) |req|
	{
		try req.setLineConfig( &.{ .{ .lines = &.{ self.line_num },
		                              .drive = in_drive } } );
		return;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn clock( self : Line ) !Clock
{
	var info : LineInfo = undefined;

	try self.getInfo( &info );

	if (info.flags.event_clock_realtime) return .realtime;
	if (info.flags.event_clock_hte)      return .hte;

	return .none;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setClock( self : Line, in_clock: Clock ) !void
{
	if (self.request) |req|
	{
		try req.setLineConfig( &.{ .{ .lines = &.{ self.line_num },
		                              .clock = in_clock } } );
		return;
	}

	return error.NotOpen;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn isActiveLow( self : Line ) !bool
{
	var info : LineInfo = undefined;

	try self.getInfo( &info );

	return info.flags.active_low;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

// pub fn setActiveLow( self : Line, in_active_low : bool ) !void
// {
//   if (self.request) |req|
//   {
//     _ =  req; _ = in_active_low; error.TODO; // setActiveLow
//   }

//     return error.NotOpen;
// }

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn isUsed( self : Line ) !bool
{
	var info : LineInfo = undefined;

	try self.getInfo( &info );

	return info.flags.used;
}