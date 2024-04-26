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
const Line    = @import( "chip-request-line.zig" );
const GPIO    = @import( "gpio.zig" );

const log    = std.log.scoped( .chip_request );
const assert = std.debug.assert;

/// The Chip contining the requested lines.
chip      : * const Chip,
/// The stream used to control and read the requested lines.
fd        : ?std.posix.fd_t = null,
/// A bitmap of lines requested -- based on line number on the Chip.
lines     : Chip.LineSet,

// =============================================================================
//  Private Constants
// =============================================================================

const NS_PER_SEC         = 1_000_000_000;

// =============================================================================
//  Public Functions
// =============================================================================

// -----------------------------------------------------------------------------
//  Public Function Request.init
// -----------------------------------------------------------------------------
/// Initialize the Request structure.
///
/// This function request access to the Request's lines and opens a stream
/// that is used to control and read the requested lines.
///
/// Note: The Request's Chip MUST be initialized before calling this function.

pub fn init( self        : *Request,
             in_consumer : [] const u8 ) !void
{
    assert( in_consumer.len <= GPIO.MAX_NAME_SIZE );

    self.deinit();

    // Create a zero filled LineRequest structure

    var req = std.mem.zeroes( GPIO.LineRequest );

    // Fill in the line array and num_lines based on the Request's
    // lines set.

    try req.fillLines( self.lines );

    // Fill in the consumer field.

    std.mem.copyForwards( u8, &req.consumer, in_consumer );

    // ### TODO ### Set event_buffer_size ##########################

    // req.event_buffer_size = ????;

    // ### TODO ### Set initial output pin values ##########################

    // if (the-req-has-output-pins)
    // {
    //     const next_attr = &req.config.attrs[req.config.num_attrs];
    //     req.config.num_attrs += 1;

    //     next_attr.attr.id = .value;
    //     next_attr.attr.data.values = value_bits; // u64
    //     next_attr.mask             = value_mask; // u64
    // }

    // ### TODO ### Set pin debounce intervals #####################

    // for (each-something) |dbp|
    // {
    //     const period      = get-debounce;
    //     const mask : u64  = 0;
    //
    //     for (each-pin) |pin| mask |= @as( u64, 1 ) << pin;

    //     if (req.config.num_attrs >= MAX_LINE_ATTRS) return error.ToManyAttrs;

    //     const next_attr = &req.config.attrs[req.config.num_attrs];
    //     req.config.num_attrs += 1;

    //     next_attr.attr.id = .debounce;
    //     next_attr.attr.data.debounce = period; // u64
    //     next_attr.mask               = mask;      // u64
    // }

    // #### TODO ### Set flags ###########################
    //       set pins to .input or .output
    //       set pins to bias values
    //       set pins trigger edge

	// ret = set_flags(config, &uapi_cfg->config, &attr_idx);

    // ----- test test test --------

        var flags = std.mem.zeroes( GPIO.Flags );

        flags.output = true;

        const next_attr = &req.config.attrs[req.config.num_attrs];
        req.config.num_attrs += 1;

        next_attr.attr.id = .flags;
        next_attr.attr.data.flags = flags;   // u64
        next_attr.mask            = 0b0010;  // u64

    // ----- test test test --------

    // -- C version does get_info ioctl here to get chip name. --

    _ = try GPIO.ioctl( self.chip.fd, .line_request, &req );

    log.warn( "Request Lines: {any}", .{ req.lines[0..req.num_lines] } );

    self.fd = req.fd;
}

// -----------------------------------------------------------------------------
//  Public Function Request.deinit
// -----------------------------------------------------------------------------
/// Close the stream for this Request.

pub fn deinit( self : *Request ) void
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
/// Return a Line struct used to control a singe line from this request.
///
/// This function may be called before the Request is initialized.

pub inline fn line( self : *Request, in_line : Chip.LineNum ) Line
{
    return .{ .request = self, .line = in_line };
}

// -----------------------------------------------------------------------------
//  Public Function getLineInfo
// -----------------------------------------------------------------------------
/// Fill in LineInfo structure for a given line.
///
/// This function allows raw access to the .line_info ioctl.

pub inline fn getLineInfo( self     : Request,
                           in_line  : LineNum,
                           out_info : *GPIO.LineInfo ) !void
{
    try self.chip.getLineInfo( in_line, out_info );
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
        var lv : GPIO.LineValues = .{ .bits = 0, .mask = in_mask };

        _ = try GPIO.ioctl( fd, .get_line_values, &lv );

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
        var lv : GPIO.LineValues = .{ .bits = 0,
                                       .mask = 0xFFFF_FFFF_FFFF_FFFF };

        _ = try GPIO.ioctl( fd, .get_line_values, &lv );

        var retval = try self.chip.allocator.alloc( ?bool,
                                                    self.chip.info.line_count );

        errdefer self.chip.allocator.free( retval );

        var line_index : Chip.LineNum = 0;
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

pub fn getLineValue( self : Request, in_line : Chip.LineNum ) !bool
{
    if (!self.lines.isSet( in_line )) return error.NotRequested;

    if (self.fd) |fd|
    {
        var lv : GPIO.LineValues = .{ .bits = 0,
                                       .mask = 0xFFFF_FFFF_FFFF_FFFF };

        _ = try GPIO.ioctl( fd, .get_line_values, &lv );

        var line_index : Chip.LineNum = 0;
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
        var lv : GPIO.LineValues = .{ .bits = in_values, .mask = in_mask };

        _ = try GPIO.ioctl( fd, .set_line_values, &lv );

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
                     in_line  : Chip.LineNum,
                     in_value : bool ) !void
{
    if (!self.lines.isSet( in_line )) return error.NotRequested;

    if (self.fd) |fd|
    {
        var line_index : Chip.LineNum = 0;
        var bit_mask   : u64          = 1;

        for (0..self.chip.info.line_count) |i|
        {
            if (self.lines.isSet( line_index ))
            {
                if (i == in_line)
                {
                    var lv : GPIO.LineValues = .{ .bits = if (in_value) bit_mask else 0,
                                                   .mask = bit_mask };

                    _ = try GPIO.ioctl( fd, .set_line_values, &lv );

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
                            out_event : []GPIO.EdgeEvent ) !usize
{
    return try GPIO.readEvent( GPIO.EdgeEvent, self.fd, out_event );
}

// -----------------------------------------------------------------------------
//  Public Function Chip.waitForEdgeEvent
// -----------------------------------------------------------------------------

pub inline fn waitForEdgeEvent( self       : Request,
                                in_timeout : ?u64 ) !usize
{
    return try GPIO.pollEvent( GPIO.EdgeEvent, self.fd, in_timeout );
}

