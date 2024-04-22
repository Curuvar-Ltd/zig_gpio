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

/// This structure is used to request control of lines from the kernel.
/// A line must be successfully requested before it value can be returned.

const std = @import( "std" );

const Request = @This();
const Chip    = @import( "chip.zig" );

const log    = std.log.scoped( .chip_request );
const assert = std.debug.assert;

chip  : * const Chip,
lines : u64,            // a bitmap of the requested lines.
fd    : ?std.posix.fd_t = null,

// =============================================================================
//  Private Constants
// =============================================================================

const MAX_NAME_SIZE      = 31;
const MAX_LINE_ATTRS     = 10;
const MAX_LINES          = 64;
const NS_PER_SEC         = 1_000_000_000;

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

// =============================================================================
//  Public Structures
// =============================================================================

pub const Line = struct
{
    request  : * const Request,
    line     : u6,

    pub const Direction = enum{ input, output };
    pub const Bias      = enum{ none, pull_up, pull_down };
};

// =============================================================================
//  Private Structures
// =============================================================================

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
/// This struct is used to set or get line values.   The mask indicate which
/// lines to get or set.  The bits indicate the values.

const LineValues = extern struct  //=> struct gpio_v2_line_values {getLineValues, setLineValuse}
{
    bits   : u64 align(8),
    mask   : u64 align(8),
};

// -------------------------------------------------------------------------

pub fn init( self : *Request, in_consumer : [] const u8 ) !void
{
    assert( in_consumer.len <= MAX_NAME_SIZE );

    self.deinit();

    var req = std.mem.zeroes( Chip.LineRequest );
    req.fillLines( self.lines );

    std.mem.copyForwards( u8, &req.consumer, in_consumer );

    _ = try Chip.ioctl( self.chip.fd, .line_request, &req );

    log.warn( "Request Lines: {any}", .{ req.lines } );

    self.fd = req.fd;
}

// -------------------------------------------------------------------------

pub fn deinit( self : *Request ) void
{
    if (self.fd) |fd|
    {
        _ = std.os.linux.close( fd );
        self.fd = null;
    }
}

// -------------------------------------------------------------------------

pub fn line( self : Request, in_line : u6 ) !Line
{
    return .{ .request = self, .line = in_line };
}

// -------------------------------------------------------------------------

pub fn getLineValuesMasked( self : Request, in_mask : u64 ) !u64
{
    if (self.fd) |fd|
    {
        var lv = LineValues{ .bits = 0, .mask = in_mask };

        _ = try Chip.ioctl( fd, .get_line_values, &lv );

        return lv.bits;
    }

    return error.NotOpen;
}

// =============================================================================
//  Private Functions
// =============================================================================

// // -----------------------------------------------------------------------------
// //  Public Function lineRequest
// // -----------------------------------------------------------------------------

// pub fn lineRequest( self           : Chip,
//                     in_lines       : [] const u6,
//                     in_values      : [] const LineValue,
//                     in_consumer    : ?[] const u8,
//                     in_buffer_size : u32 ) !LineRequest
// {
//     assert( in_lines.len <= MAX_NAME_SIZE );

//     var req = std.mem.zeroes( LineRequest );

//     for (in_lines, 0..) |a_line, i| req.lines[i] = a_line;

//     req.num_lines         = @intCast( in_lines.len );
//     req.event_buffer_size = in_buffer_size;

//     if (in_consumer) |consumer|
//     {
//         assert( consumer.len <= MAX_NAME_SIZE );

//         std.mem.copyForwards( u8,
//                               req.consumer[0..consumer.len],
//                               consumer );
//     }

//     for (in_values) |a_value|
//     {
//         const an_attr = LineAttribute{ .id   = .output_values,
//                                        .data = .{ .value = @intFromEnum( a_value ) } };

//         const a_config_attr = LineConfigAttribute{ .attr = an_attr,
//                                                    .mask = 0 };

//         req.config.attrs[req.config.num_attrs] = a_config_attr;
//         req.config.num_attrs += 1;
//     }

//     // var result = gpiod_line_config_to_uapi(line_cfg, &uapi_req);

//             // set_output_values(config, uapi_cfg, &attr_idx);

//             // ret = set_debounce_periods(config, &uapi_cfg->config, &attr_idx);
//             // if (ret)
//             // 	return -1;

//             // ret = set_flags(config, &uapi_cfg->config, &attr_idx);
//             // if (ret)
//             // 	return -1;

//             // uapi_cfg->config.num_attrs = attr_idx;

//     // if (result != 0) return null;

//     // result = read_chip_info( self.fd, &info );
//     //         memset(info, 0, sizeof(*info));

//     //         ret = gpiod_ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, info);

//     // if (result != 0) return null;

//     log.warn( "before:", .{} );
//     log.warn( "req.num_lines:    {}",    .{ req.num_lines } );
//     log.warn( "req.lines:        {any}", .{ req.lines } );
//     log.warn( "req.consumer:     {s}",   .{ req.consumer } );
//     log.warn( "req.config:       {any}", .{ req.config } );
//     log.warn( "req.evt_buf_size: {}",    .{ req.event_buffer_size } );
//     log.warn( "req.fd:           {}",    .{ req.fd } );


//     _ = try self.ioctl( .line_request, &req );

//     log.warn( "after:", .{} );
//     log.warn( "req.num_lines:    {}",    .{ req.num_lines } );
//     log.warn( "req.lines:        {any}", .{ req.lines } );
//     log.warn( "req.consumer:     {s}",   .{ req.consumer } );
//     log.warn( "req.config:       {any}", .{ req.config } );
//     log.warn( "req.evt_buf_size: {}",    .{ req.event_buffer_size } );
//     log.warn( "req.fd:           {}",    .{ req.fd } );

//     // request = gpiod_line_request_from_uapi( &uapi_req, info.name );

//     // if (request == null) close( request.fd );

//     return req;
// }

// -----------------------------------------------------------------------------
//  Public Function setLineConfig
// -----------------------------------------------------------------------------

// pub fn setLineConfig( self : chip, in_line : u6, in_config : lineConfig ) !void
// {

// }


//     var lr = std.mem.zeros( LineRequest );

//     if (in_consumer) |c| std.mem.copy( u8, lr.consumer, c ); // ??? Direction

//     _ = try self.ioctl( .set_line_config, &lr );

// pub fn setLineConfig( self : Chip, in_request : *LineRequestX, in_config : *LineConfigX )
// {
//     var lr = std.mem.zeros( LineRequest );

//     lr.num_lines = in_config.num_configs;

//     for (0..lr.num_lines) |i|
//     {
//         lr.offsets[i] = in_config.line_configs.offset;
//     }
// 	// set_output_values(in_config, lr, &attr_idx);

// //	if (!has_at_least_one_output_direction(config)) return;

//     var lca : *LineConfigAttribute = undefined;

//     lca = lr.config.attrs[attr_idx++]
//     lca.id = .output_valuse;

//     var mask   : u64 = 0;
//     var values : u64 = 0;

// //	set_kernel_output_values(&mask, &values, config);

//     for (0..in_config.num_configs) |i|
//     {
//         var per_line = in_config.line_configs[i];

//     }

//     lca.attr.values = values;
//     lca.mask        = mask;

// 	// ret = set_debounce_periods(in_config, &lr->config, &(attr_idx));
// 	// if (ret)
// 	// 	return -1;

// 	// ret = set_flags(in_config, &lr->config, &attr_idx);
// 	// if (ret)
// 	// 	return -1;

// 	// lr->config.num_attrs = attr_idx;

// // 	if (!offsets_equal(request, &lr)) {
// // 		errno = EINVAL;
// // 		return -1;
// // 	}

//     _ = try self.ioctl( .set_line_config, &lr );
// }


// // -----------------------------------------------------------------------------
// //  Public Function getLineValuesMasked
// // -----------------------------------------------------------------------------

// pub fn getLineValuesMasked( self : Chip, in_mask : u64 ) !u64
// {
//     var lv = LineValues{ .bits = 0, .mask = in_mask };

//     _ = try self.ioctl( .get_line_values, &lv );

//     return lv.bits;
// }

// // -----------------------------------------------------------------------------
// //  Public Function getLineValues
// // -----------------------------------------------------------------------------

// pub fn getLineValues( self : Chip,
//                       in_values : []PerLineValue ) !void
// {
//     if (in_values.len == 0) return;

//     var lv = LineValues{ .bits = 0, .mask = 0 };

//     for (in_values) |a_line_value|
//     {
//         lv.mask |= @as( u64, 1 ) << a_line_value.line;
//     }

//     _ = try self.ioctl( .set_line_values, &lv );

//     for (in_values) |*v|
//     {
//         v.value = (if ((lv.bits & (@as( u64, 1 ) << v.line)) != 0) .active else .inactive);
//     }
// }

// // -----------------------------------------------------------------------------
// //  Public Function setLineValuesMasked
// // -----------------------------------------------------------------------------
// /// Set a subset of the lines simultaniously
// ///
// /// Parameters:
// /// - in_mask   - a bitmask indicating the lines to set
// /// - in_values - the values to set the lines to

// pub fn setLineValuesMasked( self      : Chip,
//                             in_mask   : u64,
//                             in_values : u64 ) !void
// {
//     var lv = LineValues{ .bits = in_values, .mask = in_mask };

//     _ = try self.ioctl( .set_line_values, &lv );
// }

// // -----------------------------------------------------------------------------
// //  Public Function setLineValues
// // -----------------------------------------------------------------------------
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



// =============================================================================
//  Public Constants
// =============================================================================

// pub const LineValue = enum(u1)  //=> enum gpiod_line_value
// {
//     inactive =  0,
//     active   =  1,
// };

// pub const LineDirection = enum(u32)  //=> enum gpiod_line_direction
// {
//     as_is    = 1,
//     input    = 2,
//     output   = 3,
//     unknown  = 4,
// };

// pub const LineEdge = enum(u32)  //=> enum gpiod_line_edge
// {
//     as_is    = 1,
//     rising   = 2,
//     falling  = 3,
//     both     = 4,
// };

// pub const LineAttrID = enum(u32)  //=> enum gpio_v2_line_attr_id {getLineInfo, watchLineInfo, lineRequest, setLineConfig}
// {
//     invalid       = 0,
//     flags         = 1,
//     output_values = 2,
//     debounce      = 3,
// };

// pub const LineBias = enum(u32)  //=> enum gpiod_line_bias
// {
//     as_is     = 1,
//     unknown   = 2,
//     disabled  = 3,
//     pull_up   = 4,
//     pull_down = 5,
// };

// pub const LineDrive = enum(u32)  //=> enum gpiod_line_drive
// {
//     push_pull    = 1,
//     open_drain   = 2,
//     open_source  = 3,
// };

// pub const LineClock = enum(u32)  //=> enum gpiod_line_clock
// {
//     monotonic = 1,
//     realtime  = 2,
//     hte       = 3,
// };

// pub const InfoEventType = enum(u32)  //=> enum gpiod_info_event_type {getLineInfoEvent}
// {
//     requested    = 1,
//     released     = 2,
//     reconfigured = 3,
// };

// pub const EdgeEventType = enum(u32) //=> enum gpiod_edge_event_type
// {
//     raising  = 1,
//     falling  = 2,
// };

// pub const LineEventType = enum(u32) //=> enum gpio_v2_line_event_id
// {
//     raising  = 1,
//     falling  = 2,
// };

// =============================================================================
//  Public Structures
// =============================================================================

// // -----------------------------------------------------------------------------
// //  Public Structure Line
// // -----------------------------------------------------------------------------
// /// This structure is used to get and set various parameters of a single
// /// gpio line.

// pub const LineXXX = struct
// {
//     chip  : * const Chip,
//     line  : u6,

//     pub const Direction = enum{ input, output };
//     pub const Bias      = enum{ none, pull_up, pull_down };

//     // -------------------------------------------------------------------------
//     //  Public Function value
//     // -------------------------------------------------------------------------
//     /// Get the current value of the line.
//     ///
//     /// Return
//     /// - true  - if the line is asserted
//     /// - false - if the line is not asserted

//     pub fn value( self : Line ) !bool
//     {
//         var lv = LineValues{ .bits = 0, .mask = @as( u64, 1 ) << self.line };

//         _ = try self.chip.ioctl( .get_line_values, &lv );

//         return (lv.bits & lv.mask) != 0;
//     }

//     // -------------------------------------------------------------------------
//     //  Public Function setValue
//     // -------------------------------------------------------------------------
//     /// Set the current value of a line.

//     pub fn setValue( self : Line, in_value : bool ) !void
//     {
//         var lv : LineValues = .{ .mask = @as( u64, 1 ) << self.line,
//                                  .bits = 0 };

//         if (in_value) lv.bits = lv.mask;

//         _ = try self.chip.ioctl( .set_line_values, &lv );
//     }

//     // -------------------------------------------------------------------------
//     //  Public Function watch
//     // -------------------------------------------------------------------------

//     pub fn watch( self : Line ) !void
//     {
//         var line_info = std.mem.zeroes( LineInfo );
//         line_info.offset = self.line;

//         _ = try self.chip.ioctl( .watch_line_info, &line_info );
//     }

//     // -------------------------------------------------------------------------
//     //  Public Function unwatch
//     // -------------------------------------------------------------------------

//     pub fn unwatch( self : Line ) !void
//     {
//         var line_info = std.mem.zeroes( LineInfo );
//         line_info.offset = self.line;

//         _ = try self.chip.ioctl( .unwatch_line_info, &line_info );
//     }

//     // -------------------------------------------------------------------------
//     //  Public Function getLineInfo
//     // -------------------------------------------------------------------------

//     pub fn getLineInfo( self : Line, out_line_info : *LineInfo ) !void
//     {
//         out_line_info.* = std.mem.zeroes( LineInfo );
//         out_line_info.offset = self.line;

//         _ = try self.chip.ioctl( .line_info, out_line_info );
//     }

//     // -------------------------------------------------------------------------
//     //  Public Function direction
//     // -------------------------------------------------------------------------

//     pub fn direction( self : Line ) !Direction
//     {
//         var line_info = std.mem.zeroes( LineInfo );
//         line_info.offset = self.line;

//         _ = try self.chip.ioctl( .line_info, &line_info );

//         if (line_info.flags.input)
//         {
//             assert( !line_info.flags.output );
//             return .input;
//         }

//         assert( line_info.flags.output );

//         return .output;
//     }

//     // -------------------------------------------------------------------------
//     //  Public Function bias
//     // -------------------------------------------------------------------------

//     pub fn bias( self : Line ) !Bias
//     {
//         var line_info = std.mem.zeroes( LineInfo );
//         line_info.offset = self.line;

//         _ = try self.chip.ioctl( .line_info, &line_info );

//         if (line_info.flags.bias_pull_up)
//         {
//             // assert( !line_info.flags.bias_pull_down );
//             // assert( !line_info.flags.bias_disabled );
//             return .pull_up;
//         }

//         if (line_info.flags.bias_pull_down)
//         {
//             // assert( !line_info.flags.bias_disabled );
//             return .pull_down;
//         }

//         // assert( line_info.flags.bias_disabled );

//         return .none;
//     }
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const Flags = packed struct (u64) //=> struct gpio_v2_line_flag {getLineInfo, watchLineInfo}
// {
//     used                  : bool,
//     active_low            : bool,
//     input                 : bool,
//     output                : bool,
//     edge_rising           : bool,
//     edge_falling          : bool,
//     open_drain            : bool,
//     open_source           : bool,
//     bias_pull_up          : bool,
//     bias_pull_down        : bool,
//     bias_disabled         : bool,
//     event_clock_realtime  : bool,
//     event_clock_hte	      : bool,
//     pad                   : u51,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------
// /// The line info structure contains basic data about each line of a chip.

// pub const LineInfo = extern struct //=> struct gpio_v2_line_info {getLineInfo, watchLineInfo}
// {
//     name      : [MAX_NAME_SIZE:0]u8,
//     consumer  : [MAX_NAME_SIZE:0]u8,
//     offset    : u32,
//     num_attrs : u32,
//     flags     : Flags align(8),
//     attrs     : [MAX_LINE_ATTRS]LineAttribute,
//     padding   : [4]u32,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------
// /// This sturcture is filled by getLineInfoEvent to advise of a change in a
// /// line's settings.

// pub const LineInfoEvent = extern struct    //=> struct gpio_v2_line_info_changed {getLineInfoEvent}
// {
//     info       : LineInfo,
//     timestamp  : u64 align(8),
//     event_type : InfoEventType,
//     pad        : [5]u32,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const LineConfig = extern struct  //=> struct gpio_v2_line_config {lineRequest, setLineConfig}
// {
//     flags     : u64 align(8),
//     num_attrs : u32,
//     padding   : [5]u32,
//     attrs     : [MAX_LINE_ATTRS]LineConfigAttribute,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------
// /// The line attribute structure discribes attirbutes that a chip's line
// /// might have.

// pub const LineAttribute = extern struct //=> struct gpio_v2_line_attribute {getLineInfo, watchLineInfo, lineRequest, setLineConfig}
// {
//     id   : LineAttrID,
//     data : extern union
//     {
//         flags           : u64,
//         value           : u64,
//         debounce_period : u32,
//     } align( 8 ),
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const LineConfigAttribute = extern struct //=> struct gpio_v2_line_config_attribute {lineRequest, setLineConfig}
// {
//     attr : LineAttribute,
//     mask : u64 align(8),
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const LineRequest = extern struct //=> struct gpio_v2_line_request {lineRequest, setLineConfig}
// {
//     lines             : [MAX_LINES]u32,
//     consumer          : [MAX_NAME_SIZE:0]u8,
//     config            : LineConfig,
//     num_lines         : u32,
//     event_buffer_size : u32,
//     padding           : [5]u32,
//     fd                : std.posix.fd_t,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const EdgeEvent = extern struct  //=> struct gpiod_edge_event
// {
//     event_type   : EdgeEventType,
//     timestamp    : u64,
//     line_offset  : u32,
//     global_seqno : c_long,
//     line_seqno   : c_long,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const LineEvent = extern struct  //=> struct gpio_v2_line_event
// {
//     timestamp    : u64 align(8), // nS
//     id           : LineEventType,
//     offset       : u32,
//     seqno        : u32,
//     line_seqno   : u32,
//     padding      : [6]u32,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const EdgeEventBuffer = extern struct  //=> struct gpiod_edge_event_buffer
// {
//     capacity    : usize,
//     num_events  : usize,
//     events      : [*]EdgeEvent,
//     event_data  : [*]LineEvent,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const InfoEvent = extern struct  //=> struct gpiod_info_event
// {
//     event_type : InfoEventType,
//     timestamp  : u64,
//     info       : LineInfoX,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const LineConfigX = extern struct  //=> struct gpiod_line_config
// {
//     line_configs  : [MAX_LINES]PerLineConfig,
//     num_configs   : usize,
//     output_values : [MAX_LINES]LineValue,
//     num_values    : usize,
//     sref_list     : ?*SettingsNode,
// };

// pub const LineConfigNew = struct
// {
//     line_configs  : []PerLineConfig,
//     output_values : []LineValue,
//     sref_list     : ?*SettingsNode,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const LineSettings = extern struct  //=> struct gpiod_line_settings
// {
//     direction       : LineDirection,
//     edge_detection  : LineEdge,
//     drive           : LineDrive,
//     bias            : LineBias,
//     active_low      : bool,
//     clock           : LineClock,
//     debounce_period : c_long,
//     value           : LineValue,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const PerLineConfig = extern struct  //=> struct per_line_config
// {
//     offset  : u32,
//     node    : *SettingsNode,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const SettingsNode = extern struct  //=> struct settings_node
// {
//     next      : *SettingsNode,
//     settings  : LineSettings,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const RequestConfig = extern struct //=> struct gpiod_request_config
// {
//     consumer          : [MAX_NAME_SIZE:0]u8,
//     event_buffer_size : usize,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const LineRequestX = extern struct //=> struct gpiod_line_request
// {
//     chip_name : [*:0]u8,
//     offsets   : [MAX_LINES]u32,
//     num_lines : usize,
//     fd        : std.posix.fd_t,
// };

// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const LineInfoX = extern struct //=> struct gpiod_line_info
// {
//     offset          : u32,
//     name            : [MAX_NAME_SIZE:0]u8,
//     used            : bool,
//     consumer        : [MAX_NAME_SIZE:0]u8,
//     direction       : LineDirection,
//     active_low      : bool,
//     bias            : LineBias,
//     drive           : LineDrive,
//     edge            : LineEdge,
//     clock           : LineClock,
//     debounced       : bool,
//     debounce_period : c_long,    // in uS
// };


// // -----------------------------------------------------------------------------
// // -----------------------------------------------------------------------------

// pub const PerLineValue = struct
// {
//     line  : u6        = undefined,
//     value : LineValue = undefined,
// };


// // -----------------------------------------------------------------------------
// //  Public Function watchLineInfo
// // -----------------------------------------------------------------------------
// /// Watch line info.
// ///
// /// Params:
// /// - in_line  - the offset to the line to watch
// /// - out_info - the LineInfo struct to fill in (must remain valid until unwatch)

// pub fn watchLineInfo( self     : Chip,
//                       in_line  : u32,
//                       out_info : *LineInfo ) !void
// {
//     out_info.* = std.mem.zeroes( LineInfo );
//     out_info.offset = in_line;
//     _ = try ioctl( self.fd, .watch_line_info, out_info );
// }

// // -----------------------------------------------------------------------------
// //  Public Function unwatchLineInfo
// // -----------------------------------------------------------------------------
// /// Un-watch a line.
// ///
// /// Params:
// /// - in_line  - the offset to the line to stop watching

// pub fn unwatchLineInfo( self : Chip, in_line : u32 ) !void
// {
//     _ = try ioctl( self.fd, .unwatch_line_info, @constCast( &in_line ) );
// }

// // -----------------------------------------------------------------------------
// //  Public Function waitInfoEvent
// // -----------------------------------------------------------------------------
// /// Return:
// /// - true  - an event is pending
// /// - false - wait timed out

// pub fn waitInfoEvent( self : Chip, in_timeout_ns : ?u64 ) !bool
// {
//     var status = undefined;

//     if (in_timeout_ns) |timeout|
//     {
//         const ts : std.os.linux.timespec = .{ .tv_sec  = timeout / NS_PER_SEC,
//                                               .tv_nsec = timeout % NS_PER_SEC };

//         status = std.os.linux.ppoll( &self.fd, 1, &ts, null );
//     }
//     else
//     {
//         status = std.os.linux.ppoll( &self.fd, 1, null, null );
//     }

//     if (status >= 0) return status > 0;

//     switch (std.posix.errno( status ))
//     {
//         .SUCCESS => return,
//         .BADF => unreachable,
//         .FAULT => unreachable,
//         .INVAL => unreachable,
//         .ENOTTY => unreachable,
//         else => |err| return std.posix.unexpectedErrno( err ),
//     }
// }

// // -----------------------------------------------------------------------------
// //  Public Function getLineInfoEvent
// // -----------------------------------------------------------------------------

// pub fn getLineInfoEvent( self : Chip, out_change : *LineInfoEvent ) !bool
// {
//     out_change.* = std.mem.zeroes( LineInfoEvent );

//     const result = std.os.linux.read( self.fd,
//                                       &out_change,
//                                       @sizeOf( LineInfoEvent ) );

//     if (result == @sizeOf( LineInfoEvent )) return true;

//     if (result > 0) return error.EIO;

//     switch (std.posix.errno( result ))
//     {
//         .SUCCESS => return false,
//         else => |err| return std.posix.unexpectedErrno( err ),
//     }
// }


// =============================================================================
//  Testing
// =============================================================================

const testing   = std.testing;

const chip_path =  "/dev/gpiochip0";

// -----------------------------------------------------------------------------

test "line request"
{
    var chip : Chip = .{};

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    var req = chip.request( &[_]u6{ 3, 4, 5, 6 } );
    try req.init( "line request" );
    defer req.deinit();

    log.warn( "Request fd     {?}",   .{ req.fd } );

    const lv = try req.getLineValuesMasked( 0xFFFF_FFFF_FFFF_FFFB );

    log.warn( "values {b:0>64}", .{ lv } );

    for (0..chip.line_names.len) |i|
    {
        var line_info = std.mem.zeroes( Chip.LineInfo );
        line_info.offset = @intCast( i );
        _ = try Chip.ioctl( chip.fd, .line_info, &line_info );

        log.warn( "", .{} );
        log.warn( "line_info.name:       {s}", .{ line_info.name } );
        log.warn( "line_info.consumer:   {s}", .{ line_info.consumer } );
        log.warn( "", .{} );
    }
}

// -----------------------------------------------------------------------------

test "bad line request"
{
    var chip : Chip = .{};

    try chip.init( std.testing.allocator, chip_path );
    defer chip.deinit();

    var req = chip.request( &[_]u6{ 7 } );
    try req.init( "bad line request" );
    defer req.deinit();

    for (0..chip.line_names.len) |i|
    {
        var line_info = std.mem.zeroes( Chip.LineInfo );
        line_info.offset = @intCast( i );
        _ = try Chip.ioctl( chip.fd, .line_info, &line_info );

        log.warn( "", .{} );
        log.warn( "line_info.name:       {s}", .{ line_info.name } );
        log.warn( "line_info.consumer:   {s}", .{ line_info.consumer } );
        log.warn( "", .{} );
    }
}