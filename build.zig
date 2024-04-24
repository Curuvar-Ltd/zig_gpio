// zig fmt: off
// DO NOT REMOVE ABOVE LINE -- zig's auto-formatting sucks.

// =============================================================================
//  Build the Curuvar zlibgpiod Library
// =============================================================================

const std = @import( "std" );

pub fn build( b : *std.Build ) void
{
    const target   = b.standardTargetOptions( .{} );
    const optimize = b.standardOptimizeOption( .{} );

    // =========================================================================
    //  Create the zlibgpiod module
    // =========================================================================

    _ = b.addModule( "zlibgpiod",
                     .{
                         .root_source_file = .{ .path = "src/zlibgpiod.zig" },
                         .target           = target,
                         .optimize         = optimize,
                       } );


    // =========================================================================
    //  Unit Tests
    // =========================================================================

    // -------------------------------------------------------------------------
    //  Add the tests in src/chip.zig to the unit tests.
    // -------------------------------------------------------------------------

    const chip_tests = b.addTest(
        .{
            .root_source_file = .{ .path = "src/tests.zig" },
            .target           = target,
            .optimize         = optimize,
        } );

    const run_chip_tests = b.addRunArtifact( chip_tests );

    // -------------------------------------------------------------------------
    //  Add a step "test" to "zig build" which builds and runs the tests.
    // -------------------------------------------------------------------------

    const test_step = b.step( "test", "Run unit tests" );

    test_step.dependOn( &run_chip_tests.step );
}
