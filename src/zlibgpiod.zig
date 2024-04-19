// zig fmt: off
// DO NOT REMOVE ABOVE LINE -- zig's auto-formatting sucks.

const std = @import( "std" );

const GPIO = @This();

const log = std.log.scoped( .zlibgpiod );

// =============================================================================
//  Structure Chip
// =============================================================================

pub const Chip = struct
{
    allocator : std.mem.Allocator = undefined,
    path      : ?[] const u8      = null,
    fd        : std.posix.fd_t    = undefined,

    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    //  Private Structure Constants
    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    const MAX_NAME_SIZE      = 31;
    const LINE_NUM_ATTRS_MAX = 10;
    const NS_PER_SEC         = 1_000_000_000;

    pub const Ioctl = enum(u32)
    {
        get_chip_info       = 0x8044B401,
        get_line_info       = 0xC100B405,
        watch_line_info     = 0xC100B406,
        unwatch_line_info   = 0xC004B40C,
        get_line            = 0xC250B407,
        set_line_config     = 0xC110B40D,
        get_line_values     = 0xC010B40E,
        set_line_values     = 0xC010B40F,
    };

    pub const ChangeType = enum(u32)
    {
        requested    = 1,
        released     = 2,
        reconfigured = 3,
    }

    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    //  Public Sub Structures
    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------

    pub const Flags = packed struct (u64)
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

    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------

    pub const Info = extern struct
    {
        name       : [MAX_NAME_SIZE:0]u8,
        label      : [MAX_NAME_SIZE:0]u8,
        line_count : u32,
    };

    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------

    pub const  LineAttribute = extern struct
    {
        id   : u32,
        data : extern union
        {
            flags           : u64,
            values          : u64,
            demounce_period : u32,
        } align( 8 ),
    };

    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------

    pub const LineInfo = extern struct
    {
        name      : [MAX_NAME_SIZE:0]u8,
        consumer  : [MAX_NAME_SIZE:0]u8,
        offset    : u32,
        num_attrs : u32,
        flags     : Flags align(8),
        attrs     : [LINE_NUM_ATTRS_MAX]LineAttribute,
        padding   : [4]u32,
    };

    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------

    pub const LineInfoChange = extern struct
    {
        info       : LineInfo,
        timestamp  : u64 aligned( 8 ),
        event_type : u32,
        pad        : [5]u32,
    };

    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    //  Public Functions
    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    // -------------------------------------------------------------------------
    //  Public Function init
    // -------------------------------------------------------------------------

    pub fn init( self         : *Chip,
                 in_allocator : std.mem.Allocator,
                 in_path      : [] const u8 ) !void
    {
        self.allocator = in_allocator;

//        const flags : std.posix.O = .{ .ACCMODE = .RDWR, .CLOEXEC = true };

        self.fd = try std.posix.open( in_path,
                                      .{ .ACCMODE = .RDWR, .CLOEXEC = true },
                                      0 );

        errdefer( std.posix.close( self.fd ) );

        self.path = try self.allocator.dupe( u8, in_path );
    }

    // -------------------------------------------------------------------------
    //  Public Function deinit
    // -------------------------------------------------------------------------

    pub fn deinit( self : *Chip ) void
    {
        if (self.path) |path|
        {
            std.posix.close( self.fd );
            self.allocator.free( path );
            self.path = null;
        }
    }

    // -------------------------------------------------------------------------
    //  Public Function getInfo
    // -------------------------------------------------------------------------

    pub fn getInfo( self : Chip, out_info : *Info ) !void
    {
        _ = try self.ioctl( .get_chip_info, out_info );
    }

    // -------------------------------------------------------------------------
    //  Public Function getLineInfo
    // -------------------------------------------------------------------------
    /// Get line info
    ///
    /// Params:
    /// - in_line  - the offset to the line to get info for
    /// - out_info - the LineInfo struct to fill in.

    pub fn getLineInfo( self     : Chip,
                        in_line  : u32,
                        out_info : *LineInfo ) !void
    {
        out_info.* = std.mem.zeroes( LineInfo );
        out_info.offset = in_line;
        _ = try self.ioctl( .get_line_info, out_info );
    }

    // -------------------------------------------------------------------------
    //  Public Function watchLineInfo
    // -------------------------------------------------------------------------
    /// Watch line info.
    ///
    /// Params:
    /// - in_line  - the offset to the line to watch
    /// - out_info - the LineInfo struct to fill in (must remain valid until unwatch)

    pub fn watchLineInfo( self     : Chip,
                          in_line  : u32,
                          out_info : *LineInfo ) !void
    {
        out_info.* = std.mem.zeroes( LineInfo );
        out_info.offset = in_line;
        _ = try self.ioctl( .watch_line_info, out_info );
    }

    // -------------------------------------------------------------------------
    //  Public Function unwatchLineInfo
    // -------------------------------------------------------------------------
    /// Un-watch a line.
    ///
    /// Params:
    /// - in_line  - the offset to the line to stop watching

    pub fn unwatchLineInfo( self : Chip, in_line : u32 ) !void
    {
        _ = try self.ioctl( .unwatch_line_info, &in_line );
    }

    // -------------------------------------------------------------------------
    //  Public Function waitInfoEvent
    // -------------------------------------------------------------------------
    /// Return:
    /// - true  - an event is pending
    /// - false - wait timed out

    pub fn waitInfoEvent( self : Chip, ?in_timeout_ns : u64 ) !bool
    {
        var status = undefined;

        if (in_timeout_ns) |timeout|
        {
            const ts : std.os.linux.timespec = .{ tv_sec  = timeout / NS_PER_SEC,
                                                  tv_nsec = timeout % NS_PER_SEC };

            status = std.os.linux.ppoll( &self.fd, 1, &ts, null );
        }
        else
        {
            status = std.os.linux.ppoll( &self.fd, 1, null, null );
        }

        if (status >= 0) return status > 0;

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

    // -------------------------------------------------------------------------
    //  Public Function getInfoEvent
    // -------------------------------------------------------------------------

    pub fn getInfoEvent( self : Chip, out_change : *LineInfoChange ) !bool
    {
        out_change.* = std.mem.zeroes( LineInfoChange );

        const result = std.os.linux.read( self.fd, &out_change, @sizeOf( LineInfoChange ) );

        if (result = @sizeOf( LineInfoChange )) return true;

        if (result > 0) return error.EIO;

        switch (std.posix.errno( status ))
        {
            .SUCCESS => return false,
            else => |err| return std.posix.unexpectedErrno( err ),
        }
    }

    // -------------------------------------------------------------------------
    //  Public Function offsetFromName
    // -------------------------------------------------------------------------

    pub fn offsetFromName( self : Chip, in_name : [] const u8 ) !u32
    {
        var info : Chip.Info = undefined;

        try chip.getInfo( &info );

        for (0..info.line_count) |line|
        {
            var line_info : Chip.LineInfo = undefined;
            try chip.getLineInfo( @intCast( line ), &line_info );

            if (std.mem.compare( u8, in_name, line_info.name ) == 0)
            {
                return line_info.offset;
            }
        }
        return error.ENOENT;
    }

    // -------------------------------------------------------------------------
    //  Public Function requestLines
    // -------------------------------------------------------------------------

    pub fn requestLines( self : Chip, in_name : [] const u8 ) !u32
    {
        // _ = try self.ioctl( .unwatch_line_info, &in_line );
    }


    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    //  Private Functions
    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    // -------------------------------------------------------------------------
    //  Function ioctl
    // -------------------------------------------------------------------------

    fn ioctl( self : Chip, in_ioctl : Ioctl, in_data : anytype ) !usize
    {
        const status = std.os.linux.ioctl( self.fd,
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
};

// =============================================================================
//  Testing
// =============================================================================

test "Chip"
{
    var chip : Chip = .{};

    try chip.init( std.testing.allocator, "/dev/gpiochip0" );
    defer chip.deinit();

    try std.testing.expect( chip.fd != 0xFFFF_FFFF );
    // try std.testing.expect( chip!.path.len == 14 );

    var info : Chip.Info = undefined;

    try chip.getInfo( &info );

    log.warn( "", .{} );
    log.warn( "chip info.name:       {s}", .{ info.name } );
    log.warn( "chip info.label:      {s}", .{ info.label } );
    log.warn( "chip info.line_count: {}",  .{ info.line_count } );

    for (0..info.line_count) |line|
    {
        var line_info : Chip.LineInfo = undefined;

        try chip.getLineInfo( @intCast( line ), &line_info );

        log.warn( "", .{} );
        log.warn( "line name:       {s}", .{ line_info.name } );
        log.warn( "line consumer:   {s}", .{ line_info.consumer } );
        log.warn( "line offset:     {}",  .{ line_info.offset } );
        log.warn( "line num_attrs:  {}",  .{ line_info.num_attrs } );
        log.warn( "line flags:      {any}", .{ line_info.flags } );

        try chip.watchLineInfo( @intCast( line ), &line_info );
        try chip.unwatchLineInfo( @intCast( line ) );
    }

    // try std.testing.expectEqual(@as(i32, 42), list.pop());
}

// =============================================================================
// =============================================================================

// /**
//  * @struct gpiod_line_settings
//  * @{
//  *
//  * Refer to @ref line_settings for functions that operate on
//  * gpiod_line_settings.
//  *
//  * @}
// */
// struct gpiod_line_settings;

// /**
//  * @struct gpiod_line_config
//  * @{
//  *
//  * Refer to @ref line_config for functions that operate on gpiod_line_config.
//  *
//  * @}
// */
// struct gpiod_line_config;

// /**
//  * @struct gpiod_request_config
//  * @{
//  *
//  * Refer to @ref request_config for functions that operate on
//  * gpiod_request_config.
//  *
//  * @}
// */
// struct gpiod_request_config;

// /**
//  * @struct gpiod_line_request
//  * @{
//  *
//  * Refer to @ref line_request for functions that operate on
//  * gpiod_line_request.
//  *
//  * @}
// */
// struct gpiod_line_request;

// /**
//  * @struct gpiod_info_event
//  * @{
//  *
//  * Refer to @ref line_watch for functions that operate on gpiod_info_event.
//  *
//  * @}
// */
// struct gpiod_info_event;

// /**
//  * @struct gpiod_edge_event
//  * @{
//  *
//  * Refer to @ref edge_event for functions that operate on gpiod_edge_event.
//  *
//  * @}
// */
// struct gpiod_edge_event;

// /**
//  * @struct gpiod_edge_event_buffer
//  * @{
//  *
//  * Refer to @ref edge_event for functions that operate on
//  * gpiod_edge_event_buffer.
//  *
//  * @}
// */
// struct gpiod_edge_event_buffer;

// =============================================================================
// =============================================================================




// /**
//  * @brief Wait for line status change events on any of the watched lines
//  *        on the chip.
//  * @param chip GPIO chip object.
//  * @param timeout_ns Wait time limit in nanoseconds. If set to 0, the function
//  *                   returns immediately. If set to a negative number, the
//  *                   function blocks indefinitely until an event becomes
//  *                   available.
//  * @return 0 if wait timed out, -1 if an error occurred, 1 if an event is
//  *         pending.
//  */
// int gpiod_chip_wait_info_event(struct gpiod_chip *chip, int64_t timeout_ns);

// /**
//  * @brief Read a single line status change event from the chip.
//  * @param chip GPIO chip object.
//  * @return Newly read watch event object or NULL on error. The event must be
//  *         freed by the caller using ::gpiod_info_event_free.
//  * @note If no events are pending, this function will block.
//  */
// struct gpiod_info_event *gpiod_chip_read_info_event(struct gpiod_chip *chip);

// /**
//  * @brief Map a line's name to its offset within the chip.
//  * @param chip GPIO chip object.
//  * @param name Name of the GPIO line to map.
//  * @return Offset of the line within the chip or -1 on error.
//  * @note If a line with given name is not exposed by the chip, the function
//  *       sets errno to ENOENT.
//  */
// int gpiod_chip_get_line_offset_from_name(struct gpiod_chip *chip,
// 					 const char *name);

// /**
//  * @brief Request a set of lines for exclusive usage.
//  * @param chip GPIO chip object.
//  * @param req_cfg Request config object. Can be NULL for default settings.
//  * @param line_cfg Line config object.
//  * @return New line request object or NULL if an error occurred. The request
//  *         must be released by the caller using ::gpiod_line_request_release.
//  */
// struct gpiod_line_request *
// gpiod_chip_request_lines(struct gpiod_chip *chip,
// 			 struct gpiod_request_config *req_cfg,
// 			 struct gpiod_line_config *line_cfg);

// /**
//  * @}
//  *
//  * @defgroup chip_info Chip info
//  * @{
//  *
//  * Functions for retrieving kernel information about chips.
//  *
//  * Line info object contains an immutable snapshot of a chip's status.
//  *
//  * The chip info contains all the publicly available information about a
//  * chip.
//  *
//  * Some accessor methods return pointers. Those pointers refer to internal
//  * fields. The lifetimes of those fields are tied to the lifetime of the
//  * containing chip info object. Such pointers remain valid until
//  * ::gpiod_chip_info_free is called on the containing chip info object. They
//  * must not be freed by the caller.
//  */

// /**
//  * @brief Free a chip info object and release all associated resources.
//  * @param info GPIO chip info object to free.
//  */
// void gpiod_chip_info_free(struct gpiod_chip_info *info);

// /**
//  * @brief Get the name of the chip as represented in the kernel.
//  * @param info GPIO chip info object.
//  * @return Valid pointer to a human-readable string containing the chip name.
//  *         The string lifetime is tied to the chip info object so the pointer
//  *         must not be freed by the caller.
//  */
// const char *gpiod_chip_info_get_name(struct gpiod_chip_info *info);

// /**
//  * @brief Get the label of the chip as represented in the kernel.
//  * @param info GPIO chip info object.
//  * @return Valid pointer to a human-readable string containing the chip label.
//  *         The string lifetime is tied to the chip info object so the pointer
//  *         must not be freed by the caller.
//  */
// const char *gpiod_chip_info_get_label(struct gpiod_chip_info *info);

// /**
//  * @brief Get the number of lines exposed by the chip.
//  * @param info GPIO chip info object.
//  * @return Number of GPIO lines.
//  */
// size_t gpiod_chip_info_get_num_lines(struct gpiod_chip_info *info);

// /**
//  * @}
//  *
//  * @defgroup line_defs Line definitions
//  * @{
//  *
//  * These defines are used across the API.
//  */

// /**
//  * @brief Logical line state.
//  */
// enum gpiod_line_value {
// 	GPIOD_LINE_VALUE_ERROR = -1,
// 	/**< Returned to indicate an error when reading the value. */
// 	GPIOD_LINE_VALUE_INACTIVE = 0,
// 	/**< Line is logically inactive. */
// 	GPIOD_LINE_VALUE_ACTIVE = 1,
// 	/**< Line is logically active. */
// };

// /**
//  * @brief Direction settings.
//  */
// enum gpiod_line_direction {
// 	GPIOD_LINE_DIRECTION_AS_IS = 1,
// 	/**< Request the line(s), but don't change direction. */
// 	GPIOD_LINE_DIRECTION_INPUT,
// 	/**< Direction is input - for reading the value of an externally driven
// 	 *   GPIO line. */
// 	GPIOD_LINE_DIRECTION_OUTPUT,
// 	/**< Direction is output - for driving the GPIO line. */
// };

// /**
//  * @brief Edge detection settings.
//  */
// enum gpiod_line_edge {
// 	GPIOD_LINE_EDGE_NONE = 1,
// 	/**< Line edge detection is disabled. */
// 	GPIOD_LINE_EDGE_RISING,
// 	/**< Line detects rising edge events. */
// 	GPIOD_LINE_EDGE_FALLING,
// 	/**< Line detects falling edge events. */
// 	GPIOD_LINE_EDGE_BOTH,
// 	/**< Line detects both rising and falling edge events. */
// };

// /**
//  * @brief Internal bias settings.
//  */
// enum gpiod_line_bias {
// 	GPIOD_LINE_BIAS_AS_IS = 1,
// 	/**< Don't change the bias setting when applying line config. */
// 	GPIOD_LINE_BIAS_UNKNOWN,
// 	/**< The internal bias state is unknown. */
// 	GPIOD_LINE_BIAS_DISABLED,
// 	/**< The internal bias is disabled. */
// 	GPIOD_LINE_BIAS_PULL_UP,
// 	/**< The internal pull-up bias is enabled. */
// 	GPIOD_LINE_BIAS_PULL_DOWN,
// 	/**< The internal pull-down bias is enabled. */
// };

// /**
//  * @brief Drive settings.
//  */
// enum gpiod_line_drive {
// 	GPIOD_LINE_DRIVE_PUSH_PULL = 1,
// 	/**< Drive setting is push-pull. */
// 	GPIOD_LINE_DRIVE_OPEN_DRAIN,
// 	/**< Line output is open-drain. */
// 	GPIOD_LINE_DRIVE_OPEN_SOURCE,
// 	/**< Line output is open-source. */
// };

// /**
//  * @brief Clock settings.
//  */
// enum gpiod_line_clock {
// 	GPIOD_LINE_CLOCK_MONOTONIC = 1,
// 	/**< Line uses the monotonic clock for edge event timestamps. */
// 	GPIOD_LINE_CLOCK_REALTIME,
// 	/**< Line uses the realtime clock for edge event timestamps. */
// 	GPIOD_LINE_CLOCK_HTE,
// 	/**< Line uses the hardware timestamp engine for event timestamps. */
// };

// /**
//  * @}
//  *
//  * @defgroup line_info Line info
//  * @{
//  *
//  * Functions for retrieving kernel information about both requested and free
//  * lines.
//  *
//  * Line info object contains an immutable snapshot of a line's status.
//  *
//  * The line info contains all the publicly available information about a
//  * line, which does not include the line value. The line must be requested
//  * to access the line value.
//  *
//  * Some accessor methods return pointers. Those pointers refer to internal
//  * fields. The lifetimes of those fields are tied to the lifetime of the
//  * containing line info object. Such pointers remain valid until
//  * ::gpiod_line_info_free is called on the containing line info object. They
//  * must not be freed by the caller.
//  */

// /**
//  * @brief Free a line info object and release all associated resources.
//  * @param info GPIO line info object to free.
//  */
// void gpiod_line_info_free(struct gpiod_line_info *info);

// /**
//  * @brief Copy a line info object.
//  * @param info Line info to copy.
//  * @return Copy of the line info or NULL on error. The returned object must
//  *         be freed by the caller using :gpiod_line_info_free.
//  */
// struct gpiod_line_info *gpiod_line_info_copy(struct gpiod_line_info *info);

// /**
//  * @brief Get the offset of the line.
//  * @param info GPIO line info object.
//  * @return Offset of the line within the parent chip.
//  *
//  * The offset uniquely identifies the line on the chip. The combination of the
//  * chip and offset uniquely identifies the line within the system.
//  */
// unsigned int gpiod_line_info_get_offset(struct gpiod_line_info *info);

// /**
//  * @brief Get the name of the line.
//  * @param info GPIO line info object.
//  * @return Name of the GPIO line as it is represented in the kernel.
//  *         This function returns a valid pointer to a null-terminated string
//  *         or NULL if the line is unnamed. The string lifetime is tied to the
//  *         line info object so the pointer must not be freed.
//  */
// const char *gpiod_line_info_get_name(struct gpiod_line_info *info);

// /**
//  * @brief Check if the line is in use.
//  * @param info GPIO line object.
//  * @return True if the line is in use, false otherwise.
//  *
//  * The exact reason a line is busy cannot be determined from user space.
//  * It may have been requested by another process or hogged by the kernel.
//  * It only matters that the line is used and can't be requested until
//  * released by the existing consumer.
//  */
// bool gpiod_line_info_is_used(struct gpiod_line_info *info);

// /**
//  * @brief Get the name of the consumer of the line.
//  * @param info GPIO line info object.
//  * @return Name of the GPIO consumer as it is represented in the kernel.
//  *         This function returns a valid pointer to a null-terminated string
//  *         or NULL if the consumer name is not set.
//  *         The string lifetime is tied to the line info object so the pointer
//  *         must not be freed.
//  */
// const char *gpiod_line_info_get_consumer(struct gpiod_line_info *info);

// /**
//  * @brief Get the direction setting of the line.
//  * @param info GPIO line info object.
//  * @return Returns ::GPIOD_LINE_DIRECTION_INPUT or
//  *         ::GPIOD_LINE_DIRECTION_OUTPUT.
//  */
// enum gpiod_line_direction
// gpiod_line_info_get_direction(struct gpiod_line_info *info);

// /**
//  * @brief Get the edge detection setting of the line.
//  * @param info GPIO line info object.
//  * @return Returns ::GPIOD_LINE_EDGE_NONE, ::GPIOD_LINE_EDGE_RISING,
//  *         ::GPIOD_LINE_EDGE_FALLING or ::GPIOD_LINE_EDGE_BOTH.
//  */
// enum gpiod_line_edge
// gpiod_line_info_get_edge_detection(struct gpiod_line_info *info);

// /**
//  * @brief Get the bias setting of the line.
//  * @param info GPIO line object.
//  * @return Returns ::GPIOD_LINE_BIAS_PULL_UP, ::GPIOD_LINE_BIAS_PULL_DOWN,
//  *         ::GPIOD_LINE_BIAS_DISABLED or ::GPIOD_LINE_BIAS_UNKNOWN.
//  */
// enum gpiod_line_bias
// gpiod_line_info_get_bias(struct gpiod_line_info *info);

// /**
//  * @brief Get the drive setting of the line.
//  * @param info GPIO line info object.
//  * @return Returns ::GPIOD_LINE_DRIVE_PUSH_PULL, ::GPIOD_LINE_DRIVE_OPEN_DRAIN
//  *         or ::GPIOD_LINE_DRIVE_OPEN_SOURCE.
//  */
// enum gpiod_line_drive
// gpiod_line_info_get_drive(struct gpiod_line_info *info);

// /**
//  * @brief Check if the logical value of the line is inverted compared to the
//  *        physical.
//  * @param info GPIO line object.
//  * @return True if the line is "active-low", false otherwise.
//  */
// bool gpiod_line_info_is_active_low(struct gpiod_line_info *info);

// /**
//  * @brief Check if the line is debounced (either by hardware or by the kernel
//  *        software debouncer).
//  * @param info GPIO line info object.
//  * @return True if the line is debounced, false otherwise.
//  */
// bool gpiod_line_info_is_debounced(struct gpiod_line_info *info);

// /**
//  * @brief Get the debounce period of the line, in microseconds.
//  * @param info GPIO line info object.
//  * @return Debounce period in microseconds.
//  *         0 if the line is not debounced.
//  */
// unsigned long
// gpiod_line_info_get_debounce_period_us(struct gpiod_line_info *info);

// /**
//  * @brief Get the event clock setting used for edge event timestamps for the
//  *        line.
//  * @param info GPIO line info object.
//  * @return Returns ::GPIOD_LINE_CLOCK_MONOTONIC, ::GPIOD_LINE_CLOCK_HTE or
//  *         ::GPIOD_LINE_CLOCK_REALTIME.
//  */
// enum gpiod_line_clock
// gpiod_line_info_get_event_clock(struct gpiod_line_info *info);

// /**
//  * @}
//  *
//  * @defgroup line_watch Line status watch events
//  * @{
//  *
//  * Accessors for the info event objects allowing to monitor changes in GPIO
//  * line status.
//  *
//  * Callers are notified about changes in a line's status due to GPIO uAPI
//  * calls. Each info event contains information about the event itself
//  * (timestamp, type) as well as a snapshot of line's status in the form
//  * of a line-info object.
//  */

// /**
//  * @brief Line status change event types.
//  */
// enum gpiod_info_event_type {
// 	GPIOD_INFO_EVENT_LINE_REQUESTED = 1,
// 	/**< Line has been requested. */
// 	GPIOD_INFO_EVENT_LINE_RELEASED,
// 	/**< Previously requested line has been released. */
// 	GPIOD_INFO_EVENT_LINE_CONFIG_CHANGED,
// 	/**< Line configuration has changed. */
// };

// /**
//  * @brief Free the info event object and release all associated resources.
//  * @param event Info event to free.
//  */
// void gpiod_info_event_free(struct gpiod_info_event *event);

// /**
//  * @brief Get the event type of the status change event.
//  * @param event Line status watch event.
//  * @return One of ::GPIOD_INFO_EVENT_LINE_REQUESTED,
//  *         ::GPIOD_INFO_EVENT_LINE_RELEASED or
//  *         ::GPIOD_INFO_EVENT_LINE_CONFIG_CHANGED.
//  */
// enum gpiod_info_event_type
// gpiod_info_event_get_event_type(struct gpiod_info_event *event);

// /**
//  * @brief Get the timestamp of the event.
//  * @param event Line status watch event.
//  * @return Timestamp in nanoseconds, read from the monotonic clock.
//  */
// uint64_t gpiod_info_event_get_timestamp_ns(struct gpiod_info_event *event);

// /**
//  * @brief Get the snapshot of line-info associated with the event.
//  * @param event Line info event object.
//  * @return Returns a pointer to the line-info object associated with the event.
//  *         The object lifetime is tied to the event object, so the pointer must
//  *         be not be freed by the caller.
//  * @warning Thread-safety:
//  *          Since the line-info object is tied to the event, different threads
//  *          may not operate on the event and line-info at the same time. The
//  *          line-info can be copied using ::gpiod_line_info_copy in order to
//  *          create a standalone object - which then may safely be used from a
//  *          different thread concurrently.
//  */
// struct gpiod_line_info *
// gpiod_info_event_get_line_info(struct gpiod_info_event *event);

// /**
//  * @}
//  *
//  * @defgroup line_settings Line settings objects
//  * @{
//  *
//  * Functions for manipulating line settings objects.
//  *
//  * Line settings object contains a set of line properties that can be used
//  * when requesting lines or reconfiguring an existing request.
//  *
//  * Mutators in general can only fail if the new property value is invalid. The
//  * return values can be safely ignored - the object remains valid even after
//  * a mutator fails and simply uses the sane default appropriate for given
//  * property.
//  */

// /**
//  * @brief Create a new line settings object.
//  * @return New line settings object or NULL on error. The returned object must
//  *         be freed by the caller using ::gpiod_line_settings_free.
//  */
// struct gpiod_line_settings *gpiod_line_settings_new(void);

// /**
//  * @brief Free the line settings object and release all associated resources.
//  * @param settings Line settings object.
//  */
// void gpiod_line_settings_free(struct gpiod_line_settings *settings);

// /**
//  * @brief Reset the line settings object to its default values.
//  * @param settings Line settings object.
//  */
// void gpiod_line_settings_reset(struct gpiod_line_settings *settings);

// /**
//  * @brief Copy the line settings object.
//  * @param settings Line settings object to copy.
//  * @return New line settings object that must be freed using
//  *         ::gpiod_line_settings_free or NULL on failure.
//  */
// struct gpiod_line_settings *
// gpiod_line_settings_copy(struct gpiod_line_settings *settings);

// /**
//  * @brief Set direction.
//  * @param settings Line settings object.
//  * @param direction New direction.
//  * @return 0 on success, -1 on error.
//  */
// int gpiod_line_settings_set_direction(struct gpiod_line_settings *settings,
// 				      enum gpiod_line_direction direction);

// /**
//  * @brief Get direction.
//  * @param settings Line settings object.
//  * @return Current direction.
//  */
// enum gpiod_line_direction
// gpiod_line_settings_get_direction(struct gpiod_line_settings *settings);

// /**
//  * @brief Set edge detection.
//  * @param settings Line settings object.
//  * @param edge New edge detection setting.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_settings_set_edge_detection(struct gpiod_line_settings *settings,
// 					   enum gpiod_line_edge edge);

// /**
//  * @brief Get edge detection.
//  * @param settings Line settings object.
//  * @return Current edge detection setting.
//  */
// enum gpiod_line_edge
// gpiod_line_settings_get_edge_detection(struct gpiod_line_settings *settings);

// /**
//  * @brief Set bias.
//  * @param settings Line settings object.
//  * @param bias New bias.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_settings_set_bias(struct gpiod_line_settings *settings,
// 				 enum gpiod_line_bias bias);

// /**
//  * @brief Get bias.
//  * @param settings Line settings object.
//  * @return Current bias setting.
//  */
// enum gpiod_line_bias
// gpiod_line_settings_get_bias(struct gpiod_line_settings *settings);

// /**
//  * @brief Set drive.
//  * @param settings Line settings object.
//  * @param drive New drive setting.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_settings_set_drive(struct gpiod_line_settings *settings,
// 				  enum gpiod_line_drive drive);

// /**
//  * @brief Get drive.
//  * @param settings Line settings object.
//  * @return Current drive setting.
//  */
// enum gpiod_line_drive
// gpiod_line_settings_get_drive(struct gpiod_line_settings *settings);

// /**
//  * @brief Set active-low setting.
//  * @param settings Line settings object.
//  * @param active_low New active-low setting.
//  */
// void gpiod_line_settings_set_active_low(struct gpiod_line_settings *settings,
// 					bool active_low);

// /**
//  * @brief Get active-low setting.
//  * @param settings Line settings object.
//  * @return True if active-low is enabled, false otherwise.
//  */
// bool gpiod_line_settings_get_active_low(struct gpiod_line_settings *settings);

// /**
//  * @brief Set debounce period.
//  * @param settings Line settings object.
//  * @param period New debounce period in microseconds.
//  */
// void
// gpiod_line_settings_set_debounce_period_us(struct gpiod_line_settings *settings,
// 					   unsigned long period);

// /**
//  * @brief Get debounce period.
//  * @param settings Line settings object.
//  * @return Current debounce period in microseconds.
//  */
// unsigned long
// gpiod_line_settings_get_debounce_period_us(
// 		struct gpiod_line_settings *settings);

// /**
//  * @brief Set event clock.
//  * @param settings Line settings object.
//  * @param event_clock New event clock.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_settings_set_event_clock(struct gpiod_line_settings *settings,
// 					enum gpiod_line_clock event_clock);

// /**
//  * @brief Get event clock setting.
//  * @param settings Line settings object.
//  * @return Current event clock setting.
//  */
// enum gpiod_line_clock
// gpiod_line_settings_get_event_clock(struct gpiod_line_settings *settings);

// /**
//  * @brief Set the output value.
//  * @param settings Line settings object.
//  * @param value New output value.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_settings_set_output_value(struct gpiod_line_settings *settings,
// 					 enum gpiod_line_value value);

// /**
//  * @brief Get the output value.
//  * @param settings Line settings object.
//  * @return Current output value.
//  */
// enum gpiod_line_value
// gpiod_line_settings_get_output_value(struct gpiod_line_settings *settings);

// /**
//  * @}
//  *
//  * @defgroup line_config Line configuration objects
//  * @{
//  *
//  * Functions for manipulating line configuration objects.
//  *
//  * The line-config object contains the configuration for lines that can be
//  * used in two cases:
//  *  - when making a line request
//  *  - when reconfiguring a set of already requested lines.
//  *
//  * A new line-config object is empty. Using it in a request will lead to an
//  * error. In order to a line-config to become useful, it needs to be assigned
//  * at least one offset-to-settings mapping by calling
//  * ::gpiod_line_config_add_line_settings.
//  *
//  * When calling ::gpiod_chip_request_lines, the library will request all
//  * offsets that were assigned settings in the order that they were assigned.
//  * If any of the offsets was duplicated, the last one will take precedence.
//  */

// /**
//  * @brief Create a new line config object.
//  * @return New line config object or NULL on error. The returned object must
//  *         be freed by the caller using ::gpiod_line_config_free.
//  */
// struct gpiod_line_config *gpiod_line_config_new(void);

// /**
//  * @brief Free the line config object and release all associated resources.
//  * @param config Line config object to free.
//  */
// void gpiod_line_config_free(struct gpiod_line_config *config);

// /**
//  * @brief Reset the line config object.
//  * @param config Line config object to free.
//  *
//  * Resets the entire configuration stored in the object. This is useful if
//  * the user wants to reuse the object without reallocating it.
//  */
// void gpiod_line_config_reset(struct gpiod_line_config *config);

// /**
//  * @brief Add line settings for a set of offsets.
//  * @param config Line config object.
//  * @param offsets Array of offsets for which to apply the settings.
//  * @param num_offsets Number of offsets stored in the offsets array.
//  * @param settings Line settings to apply.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_config_add_line_settings(struct gpiod_line_config *config,
// 					const unsigned int *offsets,
// 					size_t num_offsets,
// 					struct gpiod_line_settings *settings);

// /**
//  * @brief Get line settings for offset.
//  * @param config Line config object.
//  * @param offset Offset for which to get line settings.
//  * @return New line settings object (must be freed by the caller) or NULL on
//  *         error.
//  */
// struct gpiod_line_settings *
// gpiod_line_config_get_line_settings(struct gpiod_line_config *config,
// 				    unsigned int offset);

// /**
//  * @brief Set output values for a number of lines.
//  * @param config Line config object.
//  * @param values Buffer containing the output values.
//  * @param num_values Number of values in the buffer.
//  * @return 0 on success, -1 on error.
//  *
//  * This is a helper that allows users to set multiple (potentially different)
//  * output values at once while using the same line settings object. Instead of
//  * modifying the output value in the settings object and calling
//  * ::gpiod_line_config_add_line_settings multiple times, we can specify the
//  * settings, add them for a set of offsets and then call this function to
//  * set the output values.
//  *
//  * Values set by this function override whatever values were specified in the
//  * regular line settings.
//  *
//  * Each value must be associated with the line identified by the corresponding
//  * entry in the offset array filled by
//  * ::gpiod_line_request_get_requested_offsets.
//  */
// int gpiod_line_config_set_output_values(struct gpiod_line_config *config,
// 					const enum gpiod_line_value *values,
// 					size_t num_values);

// /**
//  * @brief Get the number of configured line offsets.
//  * @param config Line config object.
//  * @return Number of offsets for which line settings have been added.
//  */
// size_t
// gpiod_line_config_get_num_configured_offsets(struct gpiod_line_config *config);

// /**
//  * @brief Get configured offsets.
//  * @param config Line config object.
//  * @param offsets Array to store offsets.
//  * @param max_offsets Number of offsets that can be stored in the offsets array.
//  * @return Number of offsets stored in the offsets array.
//  *
//  * If max_offsets is lower than the number of lines actually requested (this
//  * value can be retrieved using ::gpiod_line_config_get_num_configured_offsets),
//  * then only up to max_lines offsets will be stored in offsets.
//  */
// size_t
// gpiod_line_config_get_configured_offsets(struct gpiod_line_config *config,
// 					 unsigned int *offsets,
// 					 size_t max_offsets);

// /**
//  * @}
//  *
//  * @defgroup request_config Request configuration objects
//  * @{
//  *
//  * Functions for manipulating request configuration objects.
//  *
//  * Request config objects are used to pass a set of options to the kernel at
//  * the time of the line request. The mutators don't return error values. If the
//  * values are invalid, in general they are silently adjusted to acceptable
//  * ranges.
//  */

// /**
//  * @brief Create a new request config object.
//  * @return New request config object or NULL on error. The returned object must
//  *         be freed by the caller using ::gpiod_request_config_free.
//  */
// struct gpiod_request_config *gpiod_request_config_new(void);

// /**
//  * @brief Free the request config object and release all associated resources.
//  * @param config Line config object.
//  */
// void gpiod_request_config_free(struct gpiod_request_config *config);

// /**
//  * @brief Set the consumer name for the request.
//  * @param config Request config object.
//  * @param consumer Consumer name.
//  * @note If the consumer string is too long, it will be truncated to the max
//  *       accepted length.
//  */
// void gpiod_request_config_set_consumer(struct gpiod_request_config *config,
// 				       const char *consumer);

// /**
//  * @brief Get the consumer name configured in the request config.
//  * @param config Request config object.
//  * @return Consumer name stored in the request config.
//  */
// const char *
// gpiod_request_config_get_consumer(struct gpiod_request_config *config);

// /**
//  * @brief Set the size of the kernel event buffer for the request.
//  * @param config Request config object.
//  * @param event_buffer_size New event buffer size.
//  * @note The kernel may adjust the value if it's too high. If set to 0, the
//  *       default value will be used.
//  * @note The kernel buffer is distinct from and independent of the user space
//  *       buffer (::gpiod_edge_event_buffer_new).
//  */
// void
// gpiod_request_config_set_event_buffer_size(struct gpiod_request_config *config,
// 					   size_t event_buffer_size);

// /**
//  * @brief Get the edge event buffer size for the request config.
//  * @param config Request config object.
//  * @return Edge event buffer size setting from the request config.
//  */
// size_t
// gpiod_request_config_get_event_buffer_size(struct gpiod_request_config *config);

// /**
//  * @}
//  *
//  * @defgroup line_request Line request operations
//  * @{
//  *
//  * Functions allowing interactions with requested lines.
//  */

// /**
//  * @brief Release the requested lines and free all associated resources.
//  * @param request Line request object to release.
//  */
// void gpiod_line_request_release(struct gpiod_line_request *request);

// /**
//  * @brief Get the name of the chip this request was made on.
//  * @param request Line request object.
//  * @return Name the GPIO chip device. The returned pointer is valid for the
//  * lifetime of the request object and must not be freed by the caller.
//  */
// const char *
// gpiod_line_request_get_chip_name(struct gpiod_line_request *request);

// /**
//  * @brief Get the number of lines in the request.
//  * @param request Line request object.
//  * @return Number of requested lines.
//  */
// size_t
// gpiod_line_request_get_num_requested_lines(struct gpiod_line_request *request);

// /**
//  * @brief Get the offsets of the lines in the request.
//  * @param request Line request object.
//  * @param offsets Array to store offsets.
//  * @param max_offsets Number of offsets that can be stored in the offsets array.
//  * @return Number of offsets stored in the offsets array.
//  *
//  * If max_offsets is lower than the number of lines actually requested (this
//  * value can be retrieved using ::gpiod_line_request_get_num_requested_lines),
//  * then only up to max_lines offsets will be stored in offsets.
//  */
// size_t
// gpiod_line_request_get_requested_offsets(struct gpiod_line_request *request,
// 					 unsigned int *offsets,
// 					 size_t max_offsets);

// /**
//  * @brief Get the value of a single requested line.
//  * @param request Line request object.
//  * @param offset The offset of the line of which the value should be read.
//  * @return Returns 1 or 0 on success and -1 on error.
//  */
// enum gpiod_line_value
// gpiod_line_request_get_value(struct gpiod_line_request *request,
// 			     unsigned int offset);

// /**
//  * @brief Get the values of a subset of requested lines.
//  * @param request GPIO line request.
//  * @param num_values Number of lines for which to read values.
//  * @param offsets Array of offsets identifying the subset of requested lines
//  *                from which to read values.
//  * @param values Array in which the values will be stored. Must be sized
//  *               to hold \p num_values entries. Each value is associated with
//  *               the line identified by the corresponding entry in \p offsets.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_request_get_values_subset(struct gpiod_line_request *request,
// 					 size_t num_values,
// 					 const unsigned int *offsets,
// 					 enum gpiod_line_value *values);

// /**
//  * @brief Get the values of all requested lines.
//  * @param request GPIO line request.
//  * @param values Array in which the values will be stored. Must be sized to
//  *               hold the number of lines filled by
//  *               ::gpiod_line_request_get_num_requested_lines.
//  *               Each value is associated with the line identified by the
//  *               corresponding entry in the offset array filled by
//  *               ::gpiod_line_request_get_requested_offsets.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_request_get_values(struct gpiod_line_request *request,
// 				  enum gpiod_line_value *values);

// /**
//  * @brief Set the value of a single requested line.
//  * @param request Line request object.
//  * @param offset The offset of the line for which the value should be set.
//  * @param value Value to set.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_request_set_value(struct gpiod_line_request *request,
// 				 unsigned int offset,
// 				 enum gpiod_line_value value);

// /**
//  * @brief Set the values of a subset of requested lines.
//  * @param request GPIO line request.
//  * @param num_values Number of lines for which to set values.
//  * @param offsets Array of offsets, containing the number of entries specified
//  *                by \p num_values, identifying the requested lines for
//  *                which to set values.
//  * @param values Array of values to set, containing the number of entries
//  *               specified by \p num_values. Each value is associated with the
//  *               line identified by the corresponding entry in \p offsets.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_request_set_values_subset(struct gpiod_line_request *request,
// 					 size_t num_values,
// 					 const unsigned int *offsets,
// 					 const enum gpiod_line_value *values);

// /**
//  * @brief Set the values of all lines associated with a request.
//  * @param request GPIO line request.
//  * @param values Array containing the values to set. Must be sized to
//  *               contain the number of lines filled by
//  *               ::gpiod_line_request_get_num_requested_lines.
//  *               Each value is associated with the line identified by the
//  *               corresponding entry in the offset array filled by
//  *               ::gpiod_line_request_get_requested_offsets.
//  * @return 0 on success, -1 on failure.
//  */
// int gpiod_line_request_set_values(struct gpiod_line_request *request,
// 				  const enum gpiod_line_value *values);

// /**
//  * @brief Update the configuration of lines associated with a line request.
//  * @param request GPIO line request.
//  * @param config New line config to apply.
//  * @return 0 on success, -1 on failure.
//  * @note The new line configuration completely replaces the old.
//  * @note Any requested lines without overrides are configured to the requested
//  *       defaults.
//  * @note Any configured overrides for lines that have not been requested
//  *       are silently ignored.
//  */
// int gpiod_line_request_reconfigure_lines(struct gpiod_line_request *request,
// 					 struct gpiod_line_config *config);

// /**
//  * @brief Get the file descriptor associated with a line request.
//  * @param request GPIO line request.
//  * @return The file descriptor associated with the request.
//  *         This function never fails.
//  *         The returned file descriptor must not be closed by the caller.
//  *         Call ::gpiod_line_request_release to close the file.
//  */
// int gpiod_line_request_get_fd(struct gpiod_line_request *request);

// /**
//  * @brief Wait for edge events on any of the requested lines.
//  * @param request GPIO line request.
//  * @param timeout_ns Wait time limit in nanoseconds. If set to 0, the function
//  *                   returns immediately. If set to a negative number, the
//  *                   function blocks indefinitely until an event becomes
//  *                   available.
//  * @return 0 if wait timed out, -1 if an error occurred, 1 if an event is
//  *         pending.
//  *
//  * Lines must have edge detection set for edge events to be emitted.
//  * By default edge detection is disabled.
//  */
// int gpiod_line_request_wait_edge_events(struct gpiod_line_request *request,
// 					int64_t timeout_ns);

// /**
//  * @brief Read a number of edge events from a line request.
//  * @param request GPIO line request.
//  * @param buffer Edge event buffer, sized to hold at least \p max_events.
//  * @param max_events Maximum number of events to read.
//  * @return On success returns the number of events read from the file
//  *         descriptor, on failure return -1.
//  * @note This function will block if no event was queued for the line request.
//  * @note Any exising events in the buffer are overwritten. This is not an
//  *       append operation.
//  */
// int gpiod_line_request_read_edge_events(struct gpiod_line_request *request,
// 					struct gpiod_edge_event_buffer *buffer,
// 					size_t max_events);

// /**
//  * @}
//  *
//  * @defgroup edge_event Line edge events handling
//  * @{
//  *
//  * Functions and data types for handling edge events.
//  *
//  * An edge event object contains information about a single line edge event.
//  * It contains the event type, timestamp and the offset of the line on which
//  * the event occurred as well as two sequence numbers (global for all lines
//  * in the associated request and local for this line only).
//  *
//  * Edge events are stored into an edge-event buffer object to improve
//  * performance and to limit the number of memory allocations when a large
//  * number of events are being read.
//  */

// /**
//  * @brief Event types.
//  */
// enum gpiod_edge_event_type {
// 	GPIOD_EDGE_EVENT_RISING_EDGE = 1,
// 	/**< Rising edge event. */
// 	GPIOD_EDGE_EVENT_FALLING_EDGE,
// 	/**< Falling edge event. */
// };

// /**
//  * @brief Free the edge event object.
//  * @param event Edge event object to free.
//  */
// void gpiod_edge_event_free(struct gpiod_edge_event *event);

// /**
//  * @brief Copy the edge event object.
//  * @param event Edge event to copy.
//  * @return Copy of the edge event or NULL on error. The returned object must
//  *         be freed by the caller using ::gpiod_edge_event_free.
//  */
// struct gpiod_edge_event *gpiod_edge_event_copy(struct gpiod_edge_event *event);

// /**
//  * @brief Get the event type.
//  * @param event GPIO edge event.
//  * @return The event type (::GPIOD_EDGE_EVENT_RISING_EDGE or
//  *         ::GPIOD_EDGE_EVENT_FALLING_EDGE).
//  */
// enum gpiod_edge_event_type
// gpiod_edge_event_get_event_type(struct gpiod_edge_event *event);

// /**
//  * @brief Get the timestamp of the event.
//  * @param event GPIO edge event.
//  * @return Timestamp in nanoseconds.
//  * @note The source clock for the timestamp depends on the event_clock
//  *       setting for the line.
//  */
// uint64_t gpiod_edge_event_get_timestamp_ns(struct gpiod_edge_event *event);

// /**
//  * @brief Get the offset of the line which triggered the event.
//  * @param event GPIO edge event.
//  * @return Line offset.
//  */
// unsigned int gpiod_edge_event_get_line_offset(struct gpiod_edge_event *event);

// /**
//  * @brief Get the global sequence number of the event.
//  * @param event GPIO edge event.
//  * @return Sequence number of the event in the series of events for all lines
//  *         in the associated line request.
//  */
// unsigned long gpiod_edge_event_get_global_seqno(struct gpiod_edge_event *event);

// /**
//  * @brief Get the event sequence number specific to the line.
//  * @param event GPIO edge event.
//  * @return Sequence number of the event in the series of events only for this
//  *         line within the lifetime of the associated line request.
//  */
// unsigned long gpiod_edge_event_get_line_seqno(struct gpiod_edge_event *event);

// /**
//  * @brief Create a new edge event buffer.
//  * @param capacity Number of events the buffer can store (min = 1, max = 1024).
//  * @return New edge event buffer or NULL on error.
//  * @note If capacity equals 0, it will be set to a default value of 64. If
//  *       capacity is larger than 1024, it will be limited to 1024.
//  * @note The user space buffer is independent of the kernel buffer
//  *       (::gpiod_request_config_set_event_buffer_size). As the user space
//  *       buffer is filled from the kernel buffer, there is no benefit making
//  *       the user space buffer larger than the kernel buffer.
//  *       The default kernel buffer size for each request is (16 * num_lines).
//  */
// struct gpiod_edge_event_buffer *
// gpiod_edge_event_buffer_new(size_t capacity);

// /**
//  * @brief Get the capacity (the max number of events that can be stored) of
//  *        the event buffer.
//  * @param buffer Edge event buffer.
//  * @return The capacity of the buffer.
//  */
// size_t
// gpiod_edge_event_buffer_get_capacity(struct gpiod_edge_event_buffer *buffer);

// /**
//  * @brief Free the edge event buffer and release all associated resources.
//  * @param buffer Edge event buffer to free.
//  */
// void gpiod_edge_event_buffer_free(struct gpiod_edge_event_buffer *buffer);

// /**
//  * @brief Get an event stored in the buffer.
//  * @param buffer Edge event buffer.
//  * @param index Index of the event in the buffer.
//  * @return Pointer to an event stored in the buffer. The lifetime of the
//  *         event is tied to the buffer object. Users must not free the event
//  *         returned by this function.
//  * @warning Thread-safety:
//  *          Since events are tied to the buffer instance, different threads
//  *          may not operate on the buffer and any associated events at the same
//  *          time. Events can be copied using ::gpiod_edge_event_copy in order
//  *          to create a standalone objects - which each may safely be used from
//  *          a different thread concurrently.
//  */
// struct gpiod_edge_event *
// gpiod_edge_event_buffer_get_event(struct gpiod_edge_event_buffer *buffer,
// 				  unsigned long index);

// /**
//  * @brief Get the number of events a buffer has stored.
//  * @param buffer Edge event buffer.
//  * @return Number of events stored in the buffer.
//  */
// size_t
// gpiod_edge_event_buffer_get_num_events(struct gpiod_edge_event_buffer *buffer);

// /**
//  * @}
//  *
//  * @defgroup misc Stuff that didn't fit anywhere else
//  * @{
//  *
//  * Various libgpiod-related functions.
//  */

// /**
//  * @brief Check if the file pointed to by path is a GPIO chip character device.
//  * @param path Path to check.
//  * @return True if the file exists and is either a GPIO chip character device
//  *         or a symbolic link to one.
//  */
// bool gpiod_is_gpiochip_device(const char *path);

// /**
//  * @brief Get the API version of the library as a human-readable string.
//  * @return A valid pointer to a human-readable string containing the library
//  *         version. The pointer is valid for the lifetime of the program and
//  *         must not be freed by the caller.
//  */
// const char *gpiod_api_version(void);

// /**
//  * @}
//  */

// #ifdef __cplusplus
// } /* extern "C" */
// #endif

// #endif /* __LIBGPIOD_GPIOD_H__ */
