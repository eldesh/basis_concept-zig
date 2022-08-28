const std = @import("std");
const deps = @import("./deps.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("basic_concept", "src/lib.zig");
    lib.setBuildMode(mode);
    deps.addAllTo(lib);
    lib.install();

    const main_tests = b.addTest("src/lib.zig");
    main_tests.setBuildMode(mode);
    deps.addAllTo(main_tests);

    const docs = b.addTest("src/lib.zig");
    docs.setBuildMode(mode);
    deps.addAllTo(docs);
    docs.emit_docs = .emit;

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const docs_step = b.step("doc", "Generate library docs");
    docs_step.dependOn(&docs.step);
}
