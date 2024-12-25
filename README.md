<div align="center">

&nbsp;
<h1>typeid-zig</h1>
<p><i>Type-safe, K-sortable, globally unique identifier inspired by Stripe IDs implemented in Zig.</i></p>

&nbsp;

[![Zig](https://img.shields.io/badge/Zig-0.13.0-orange.svg)](https://ziglang.org/)

</div>

&nbsp;

## About

Implementation of Type-IDs in Zig. Implemented as described by the official specification:

- [Type-ID specification](https://github.com/jetify-com/typeid/tree/main/spec)

## What are Type-IDs?

As per the official specification:

TypeIDs are a modern, type-safe extension of UUIDv7. Inspired by a similar use of prefixes
in Stripe's APIs.

TypeIDs are canonically encoded as lowercase strings consisting of three parts:

1. A type prefix (at most 63 characters in all lowercase snake_case ASCII [a-z_]).
2. An underscore '\_' separator
3. A 128-bit UUIDv7 encoded as a 26-character string using a modified base32 encoding.

Here's an example of a TypeID of type `user`:

```
user_2x4y6z8a0b1c2d3e4f5g6h7j8k
  │    │
  │    └── 26-character base32-encoded UUIDv7
  │
  └── Type prefix (snake_case [a-z_])
        Max length: 63 characters
```

A [formal specification](https://github.com/jetify-com/typeid/tree/main/spec) defines the encoding in more detail.

## Installation

1. Add as a dependency in your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/nikoksr/typeid-zig#main
```

2. In your `build.zig`, add the `typeid` module as a dependency:

```zig
const typeid = b.dependency("typeid", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("typeid", typeid.module("typeid"));
```

## Usage

```zig
const TypeID = @import("typeid").TypeID;
const TypeIDBuilder = @import("typeid").TypeIDBuilder;

// Create a new TypeID with prefix
const tid = try TypeID.init("user");

// Get string representation
var buf: [90]u8 = undefined;
const str = try tid.toString(&buf);
// str = "user_01h455vb4pex5vsknk084sn02q"

// Parse existing TypeID string
const parsed = try TypeID.fromString("post_01h455vb4pex5vsknk084sn02q");

// Builder pattern with configuration
const configured = try TypeIDBuilder.init()
    .setPrefix("user")
    .build();
```

## Tests

```bash
zig build test
```
