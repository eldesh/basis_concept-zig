# Basis Concept Zig

**basis_concept-zig** is a collection library of "basis concept" and some operations on it.
Some basic concepts such as `Copyable` are provided.


## Concept

*Concept* are named constraints on types such as `Clonable`.


In the Zig language, polymorphic functions are sometimes typed `fn (anytype) t`.
Often, however, functions with such types implicitly require some properties for their types.
The `Concept` allows such implicit constraints to be named.

Naming such implicit constraint allows us to deal explicitly with constraints on types.
Further, some associated polymorphic functions are able to be implemented to each Concept such like `Cloneable.clone`.


## Examples

### Equivalence of generic data type

To compare equivalence of data of various types:

```
/// A type constructed from various `isEq` types
const S = struct {
	val_int: u32,
	val_opt: ?u8,
	val_eit: error{MyError}![5]u8,
};

const s1: S = ...;
const s2: S = ...;
if (Eq.eq(&s1, &s2)) {
    ...
}
```


### Check for cloneability

When you want to implement `clone` on a container type only for types that are clonable.

```
pub fn Container(comptime T: type) type {
  return struct {
    pub const Self: type = @This();
    pub const CloneError: type = std.mem.Allocator.Error;
    ..
    pub usingnamespace if isClonable(T) {
      return struct {
        pub fn clone(self: *const Self) CloneError!Self {
          .. T.clone() ..
        }
      };
    } else {
      return struct {}; // empty
    };
  };
}

// For a clonable type C:
var c = Container(C);
var d = try c.clone(); // clonable

// For a not clonable type N:
var n = Container(N);
// _ = try n.clone(); // compilation error
```


### Comparison by total order

When you want to pass an ordering function for a key type of a Mapping container.

```
var map: Map(Key, Value) = MakeKeyValueMap(Key, Value, Ord.on(Key));
map.insert(key1, value1);
map.insert(key2, value2);
...
```


## Support

This library is developped with:

- Debian (x86_64) 10.4
- Zig 0.9.1
- Zigmod r79


## Build

To build:

```sh
zig build
```


## Unit Test

To performs unit tests:

```sh
zig build test
```


## Generate docs

To generate documents:

```sh
zig build doc
```

A html documents would be generated under the `./docs` directory.


## Module Hierarchy


- basis_concept (the root module)
    - copy
		- isCopyable
    - clone
        - isClonable
        - Clone
    - partial_ord
        - isPartialOrd
        - PartialOrd
    - ord
        - isOrd
        - Ord
    - trivial_eq
        - isTrivialEq
    - partial_eq
        - isPartialEq
        - PartialEq
    - eq
        - isEq
        - Eq
    - prelude
        - Clone
        - PartialEq
        - PartialOrd
        - Ord
        - Eq


## Concept Convention

Implementations of concept on types, are follows some conventions.
For any concept `C`, `implC`, `isC` and `C` maybe implemented.

- `fn implC(comptime T:type) bool`  
    Determine if the type `T` satisfies concept `C` directly.

- `fn isC(comptime T:type) bool`  
    Determine if the type `T` satisfies concept `C`.

- `const C = struct { ... };`  
    Namespace `C` that implements generic functions that depend on the concept `C`.

- `fn DeriveC(comptime T:type) type`  
    Derive functions that depend on `C`.

