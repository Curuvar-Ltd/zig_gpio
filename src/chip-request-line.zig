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

/// This structure is used to control a single line.

const std     = @import( "std" );

const Line    = @This();
const Chip    = @import( "chip.zig" );
const Request = @import( "chip-request.zig" );

const log    = std.log.scoped( .chip_request_line );
const assert = std.debug.assert;

request  : * const Request,
line     : Chip.LineNum,

// =============================================================================
//  Public Functions
// =============================================================================

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn value( self : Line ) !bool
{
    return self.request.getLineValue( self.line );
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setValue( self : Line, in_value : bool ) !void
{
    return self.request.setLineValue( self.line, in_value );
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub inline fn getInfo( self : Line, out_info : *GPIO.LineInfo ) !void
{
    self.line.chip.getLineInfo( self.line, out_info );
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn getDirection( self : Line ) !GPIO.Direction
{
    var info : GPIO.LineInfo = undefined;

    try self.getInfo( &info );

    if (info.flags.output) return .output;

    return .input;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setDirection( self : Line, in_value : GPIO.Direction ) !void
{
    _= self; _ = in_value; // ### TODO ### implement setDirection
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn getBias( self : Line ) !GPIO.Bias
{
    var info : GPIO.LineInfo = undefined;

    try self.getInfo( &info );

    if (info.flags.bias_pull_up)   return .pull_up;
    if (info.flags.bias_pull_down) return .pull_down;

    return .none;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setBias( self : Line, in_value : GPIO.Bias ) !void
{
    _= self; _ = in_value; // ### TODO ### implement setBias
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn getEdge( self : Line ) !GPIO.Edge
{
    var info : GPIO.LineInfo = undefined;

    try self.getInfo( &info );

    if (!info.flags.edge_rising)  return .falling;
    if (!info.flags.edge_falling) return .rising;

    return .both;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setEdge( self : Line, in_value : GPIO.Edge ) !void
{
    _= self; _ = in_value; // ### TODO ### implement setEdge
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn getDrive( self : Line ) !GPIO.Drive
{
    var info : GPIO.LineInfo = undefined;

    try self.getInfo( &info );

    if (!info.flags.open_drain)  return .open_source;
    if (!info.flags.open_source) return .open_drain;

    return .push_pull;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setDrive( self : Line, in_value : GPIO.Drive ) !void
{
    _= self; _ = in_value; // ### TODO ### implement setDrive
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn getClock( self : Line ) !GPIO.Clock
{
    var info : GPIO.LineInfo = undefined;

    try self.getInfo( &info );

    if (info.flags.event_clock_realtime) return .realtime;
    if (info.flags.event_clock_hte)      return .hte;

    return .none;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setClock( self : Line, in_value : GPIO.Clock ) !void
{
    _= self; _ = in_value; // ### TODO ### implement setClock
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn isActiveLow( self : Line ) !bool
{
    var info : GPIO.LineInfo = undefined;

    try self.getInfo( &info );

    return info.flags.active_low;
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn setActiveLow( self : Line, in_active_low : bool ) !void
{
    _= self; _ = in_active_low; // ### TODO ### implement setActiveLow
}

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

pub fn isUsed( self : Line ) !bool
{
    var info : GPIO.LineInfo = undefined;

    try self.getInfo( &info );

    return info.flags.used;
}