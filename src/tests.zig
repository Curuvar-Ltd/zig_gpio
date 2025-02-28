// zig fmt: off

//                Copyright (c) 2025, Curuvar Ltd.
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



const std     = @import( "std" );

const Chip    = @import( "chip.zig" );
const Request = @import( "chip-request.zig" );
const Line    = @import( "chip-line.zig" );

const log     = std.log.scoped( .tests );

// =============================================================================
//  Testing
// =============================================================================

const testing   = std.testing;

const chip_path =  "/dev/gpiochip0";

// -----------------------------------------------------------------------------
// Test the Chip's, init, deinit, request, lineNumFromName, getLineInfo, and
// ioctl functions.

test "Chip Tests"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var line_info : Chip.LineInfo = undefined;

	try chip.getLineInfo( try chip.lineNumFromName( "GPIO22" ), &line_info );

	log.warn( "chip info.name:       {s}", .{ chip.info.name } );
	log.warn( "chip info.label:      {s}", .{ chip.info.label } );
	log.warn( "chip info.line_count: {}",  .{ chip.info.line_count } );
	log.warn( "line_info.line:       {}",    .{ line_info.line } );
	log.warn( "line_info.name:       {s}",   .{ line_info.name } );
	log.warn( "line_info.consumer:   {s}",   .{ line_info.consumer } );
	log.warn( "line_info.flags:      {any}", .{ line_info.flags } );
	log.warn( "line_info.num_attrs:  {}",    .{ line_info.num_attrs } );

	try testing.expectEqual( 22,       line_info.line );
}

// -----------------------------------------------------------------------------
// Test the Chip's request function.

test "line request"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	try testing.expectError( error.InvalidRequest, chip.request( &.{ 62 } ) );

	var req = try chip.request( &.{ 7 } ); // Line already "owned".

	try testing.expectError( error.LineBusy, req.reserve( "busy", 0, &.{} ) );

	req = try chip.request( &.{ 3, 4, 5, 6 } );

	try req.reserve( "testing", 0, &.{ .{ .lines     = &.{ 4 },
		                                    .direction = .output } } );
	defer req.release();

	log.warn( "Request fd     {?}",   .{ req.fd } );

	var lv = try req.getLineValuesMasked( 0xFFFF_FFFF_FFFF_FFFF );

	log.warn( "Orig  values {b:0>64}", .{ lv } );

	try req.setLineValuesMasked( 0b0010, 0b0010 );

	lv = try req.getLineValuesMasked( 0xFFFF_FFFF_FFFF_FFFF );

	log.warn( "Final values {b:0>64}", .{ lv } );
}

// -----------------------------------------------------------------------------
// Test the Chip's, watchLine, unwatchLine, waitInfoEvent, getInfoEvent,
// pollEvent, and readEvent functions.

test "watch line"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var req = try chip.request( &.{ 3, 4, 5, 6 } );

	var line_info : Chip.LineInfo = undefined;

	try chip.watchLine( 3, &line_info );

	log.warn( "\n === Watch Line ===", .{} );
	log.warn( "line_info.line:       {}",    .{ line_info.line } );
	log.warn( "line_info.name:       {s}",   .{ line_info.name } );
	log.warn( "line_info.consumer:   {s}",   .{ line_info.consumer } );
	log.warn( "line_info.flags:      {any}", .{ line_info.flags } );
	log.warn( "line_info.num_attrs:  {}",    .{ line_info.num_attrs } );
	log.warn( "", .{} );

	log.warn( "start time: {}",  .{ std.time.microTimestamp() } );

	// ### TODO ### why did this request not gerenate an event?

	try req.reserve( "testing", 0, &.{} );
	defer req.release();

	if (try chip.waitForInfoEvent( 1_000_000_000 ) > 0)
	{
		log.warn( "event at:   {}",  .{ std.time.microTimestamp() } );

		var info_event : [1]Chip.InfoEvent = undefined;

		_ = try chip.getInfoEvent( &info_event );

		log.warn( "", .{} );
		log.warn( "line_info.flags:      {any}", .{ info_event } );
		log.warn( "", .{} );
	}
	else
	{
		log.warn( "timeout at: {}",  .{ std.time.microTimestamp() } );
	}

	try chip.unwatchLine( 3 );
}

// -----------------------------------------------------------------------------

test "set single line request"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var req  = try chip.request( &.{ 3, 4, 5, 6 } );
	var line = try req.line( 4 );

	try req.reserve( "testing", 0, &.{} );
	defer req.release();

	try line.setValue( false );
}

// -----------------------------------------------------------------------------

test "get single line request"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var req  = try chip.request( &.{ 3, 4, 5, 6 } );
	var line = try req.line( 4 );

	try req.reserve( "testing", 0, &.{} );
	defer req.release();

	try testing.expectEqual( false, line.value() );
}

// -----------------------------------------------------------------------------

test "line direction"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var req  = try chip.request( &.{ 3, 4, 5, 6 } );
	var line = try req.line( 4 );

	try req.reserve( "testing", 0, &.{} );
	defer req.release();

	try line.setDirection( .input );

	try testing.expectEqual( .input, line.direction() );

	try line.setDirection( .output );

	try testing.expectEqual( .output, line.direction() );
}

// -----------------------------------------------------------------------------

test "line bias"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var req  = try chip.request( &.{ 3, 4, 5, 6 } );
	var line = try req.line( 3 );

	try req.reserve( "testing", 0, &.{} );
	defer req.release();

	log.warn( "direction: {any}", .{ try line.direction() } );

	try testing.expectEqual( .none, line.bias() );

	try line.setBias( .pull_up );

	try testing.expectEqual( .pull_up, line.bias() );

	try line.setBias( .none );
}

// -----------------------------------------------------------------------------

test "line edge"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var req  = try chip.request( &.{ 3, 4, 5, 6 } );
	var line = try req.line( 4 );

	try req.reserve( "testing", 0, &.{} );
	defer req.release();

	try testing.expectEqual( .none, line.edge() );

	// try line.setEdge( .both );

	// try testing.expectEqual( .both, line.edge() );

	// try line.setEdge( .none );
}

// -----------------------------------------------------------------------------

test "line drive"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var req  = try chip.request( &.{ 3, 4, 5, 6 } );
	var line = try req.line( 4 );

	try req.reserve( "testing", 0, &.{} );
	defer req.release();

	try testing.expectEqual( .none, line.drive() );

	// try line.setDrive( .open_source );

	// try testing.expectEqual( .open_source, line.drive() );
}

// -----------------------------------------------------------------------------

test "get line clock"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var line = try chip.line( 4 );

	try testing.expectEqual( .none, line.clock() );
}

// -----------------------------------------------------------------------------

test "get line isActiveLow"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var line = try chip.line( 4 );

	try testing.expectEqual( false, line.isActiveLow() );
}

// -----------------------------------------------------------------------------

test "get line isUsed"
{
	log.warn( "", .{} );
	defer log.warn( "▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂", .{} );

	var chip = try Chip.init( std.testing.allocator, chip_path );
	defer chip.deinit();

	var line = try chip.line( 4 );

	try testing.expectEqual( false, line.isUsed() ); // ## TODO ## Why is this false?
}
