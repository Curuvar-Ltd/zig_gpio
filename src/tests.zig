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



const std     = @import( "std" );

const Chip    = @import( "chip.zig" );

const log     = std.log.scoped( .tests );

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

test "line number from name"
{
    var chip : Chip = .{};

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try testing.expectEqual( 22, chip.lineNumFromName( "GPIO22" ) );
}

// -----------------------------------------------------------------------------

test "get line info"
{
    var chip : Chip = .{};

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    var line_info : Chip.LineInfo = undefined;

    try chip.getLineInfo( 0, &line_info );

    log.warn( "", .{} );
    log.warn( "line_info.name:       {s}", .{ line_info.name } );
    log.warn( "line_info.consumer:   {s}", .{ line_info.consumer } );
    log.warn( "", .{} );
}

// -----------------------------------------------------------------------------

test "line request"
{
    var chip : Chip = .{};
    var req      = chip.request( &.{ 3, 4, 5, 6 } );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try req.init( "line request" );
    defer req.deinit();

    log.warn( "Request fd     {?}",   .{ req.fd } );

    var lv = try req.getLineValuesMasked( 0xFFFF_FFFF_FFFF_FFFF );

    log.warn( "Orig  values {b:0>64}", .{ lv } );

    try req.setLineValuesMasked( 0b0010, 0b0010 );

    lv = try req.getLineValuesMasked( 0xFFFF_FFFF_FFFF_FFFF );

    log.warn( "Final values {b:0>64}", .{ lv } );
}

// -----------------------------------------------------------------------------

test "watch line"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 3, 4, 5, 6 } );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    var line_info : Chip.LineInfo = undefined;

    try chip.watchLine( 1, &line_info );

    log.warn( "\n === Watch Line ===", .{} );
    log.warn( "line_info.name:       {s}", .{ line_info.name } );
    log.warn( "line_info.consumer:   {s}", .{ line_info.consumer } );
    log.warn( "", .{} );

    log.warn( "start time: {}",  .{ std.time.microTimestamp() } );

    // ### TODO ### why did this request not gerenate an event?

    try req.init( "line request" );
    defer req.deinit();

    if (try chip.waitForInfoEvent( 1_000_000_000 ) > 0)
    {
        log.warn( "event at:   {}",  .{ std.time.microTimestamp() } );

        var info_event : [1]Chip.InfoEvent = undefined;

        _ = try chip.getInfoEvent( &info_event );
    }
    else
    {
        log.warn( "timeout at: {}",  .{ std.time.microTimestamp() } );
    }

    try chip.unwatchLine( 1 );
}

// -----------------------------------------------------------------------------

test "invalid line request"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 62 } ); // No line 62 on chip.

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try testing.expectError( error.InvalidRequest,
                             req.init( "invalid line request" ) );
}

// -----------------------------------------------------------------------------

test "busy line request"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 7 } ); // Line already "owned".

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try testing.expectError( error.LineBusy,
                             req.init( "busy line request" ) );
}

// -----------------------------------------------------------------------------

test "bad single line request"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 3, 4, 5, 6 } );
    var line        = req.line( 7 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try req.init( "line request" );
    defer req.deinit();

    try testing.expectError( error.NotRequested, line.value() );
}

// -----------------------------------------------------------------------------

test "set single line request"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 3, 4, 5, 6 } );
    var line        = req.line( 4 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try req.init( "line request" );
    defer req.deinit();

    try line.setValue( false );
}

// -----------------------------------------------------------------------------

test "get single line request"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 3, 4, 5, 6 } );
    var line        = req.line( 4 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try req.init( "line request" );
    defer req.deinit();

    try testing.expectEqual( false, line.value() );
}

// -----------------------------------------------------------------------------

test "line direction"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 3, 4, 5, 6 } );
    var line        = req.line( 4 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try req.init( "get line direction" );
    defer req.deinit();

    try testing.expectEqual( .output, line.direction() );

    try line.setDirection( .input );

    try testing.expectEqual( .input, line.direction() );

    try line.setDirection( .output );
}

// -----------------------------------------------------------------------------

test "line bias"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 3, 4, 5, 6 } );
    var line        = req.line( 4 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try req.init( "get line direction" );
    defer req.deinit();

    try testing.expectEqual( .none, line.bias() );

    // try line.setBias( .pull_up );

    // try testing.expectEqual( .pull_up, line.bias() );

    // try line.setBias( .none );
}

// -----------------------------------------------------------------------------

test "line edge"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 3, 4, 5, 6 } );
    var line        = req.line( 4 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try req.init( "get line direction" );
    defer req.deinit();

    try testing.expectEqual( .none, line.edge() );

    // try line.setEdge( .both );

    // try testing.expectEqual( .both, line.edge() );

    // try line.setEdge( .none );
}

// -----------------------------------------------------------------------------

test "line drive"
{
    var chip : Chip = .{};
    var req         = chip.request( &.{ 3, 4, 5, 6 } );
    var line        = req.line( 4 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try req.init( "get line direction" );
    defer req.deinit();

    try testing.expectEqual( .none, line.drive() );

    // try line.setDrive( .open_source );

    // try testing.expectEqual( .open_source, line.drive() );
}

// -----------------------------------------------------------------------------

test "get line clock"
{
    var chip : Chip = .{};
    var line        = chip.line( 4 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try testing.expectEqual( .none, line.clock() );
}

// -----------------------------------------------------------------------------

test "get line isActiveLow"
{
    var chip : Chip = .{};
    var line        = chip.line( 4 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try testing.expectEqual( false, line.isActiveLow() );
}

// -----------------------------------------------------------------------------

test "get line isUsed"
{
    var chip : Chip = .{};
    var line        = chip.line( 4 );

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    try testing.expectEqual( false, line.isUsed() ); // ## TODO ## Why is this false?
}
