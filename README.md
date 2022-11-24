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
    pub usingnamespace if (isClonable(T))
      struct {
        pub fn clone(self: *const Self) CloneError!Self {
          .. T.clone() ..
        }
      }
    else
      struct {}; // empty
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
- Zig 0.9.1 with Zigmod r79
- Zig 0.10.1 with Zigmod r80


## Build

To build, executing the following commands:

```sh
zigmod fetch
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


## Provided Concept

- TrivialEq
  Concept for types that trivially comparable value with `==`.
  This concept is defined for checking the type is comparable with `==`.
  Then any extra method is not provided.

- TrivialDestroy
  Concept for types that trivially destroyable implicitly.
  Then any extra method is not provided.

- Copyable
  Trivially copyable values with `=`.
  `Copy` means to duplicate a value that has no resources shared with the original one.
  In other words, it must not contain a pointer.

- Clonable
  Duplicable values using `clone` method if exists.
  Similar to Copyable, `Clonable` means that the value can be duplicated. However, the concept can be satisfied if the `clone` method is implemented even if the value cannot be copied in the trivial way.
  In other words, if a type is `Copyable`, it is automatically `Clonable` as well.

- PartialEq
  `PartialEq` concept means that a partial equivalence relation is defined for the type.
  The partiality comes from the fact that the relation does not require reflexivity.
  That is, the relation must satisfy the following properties. for all x, y and z:

  - `PartialEq.eq(x, y) == PartialEq.eq(y, x)`
  - `PartialEq.eq(x, y) == PartialEq.eq(y, z) == PartialEq.eq(x, z)`

- Eq
  `Eq` concept means that a full equivalence relation is defined for the type.
  Addition to `PartialEq`, this concept requires relations to have reflexivity.

  - `Eq.eq(x, y) == Eq.eq(y, x)`
  - `Eq.eq(x, y) and Eq.eq(y, z)` implies `Eq.eq(x, z)`
  - `Eq.eq(x, x)`

  Furthermore, this concept also contains `ne` method, which must be consistent with `eq`.

- PartialOrd
  `PartialOrd` concept means parial ordering relation.
  Such relations require the type satisfies properties and have consistensy to `PartialEq`.

  - `PartialOrd.partial_cmp(x, y).?.compare(.eq)` implies `PartialEq.eq(x, y)`
  - `PartialOrd.partial_cmp(x, y).?.compare(.le)` implies `PartialOrd.partial_cmp(x, y).?.compare(.lt) or PartialEq.eq(x, y)`
  - `PartialOrd.partial_cmp(x, y).?.compare(.ge)` implies `PartialOrd.partial_cmp(x, y).?.compare(.lt) or PartialEq.eq(x, y)`


- Ord
  Concept for types that forms total order.
  Implementations must be consistent with `PartialOrd`.

  - `Ord.cmp(x, y) == PartialOrd.partial_cmp(x, y).?`

- Destroy
  The `Destroy` concept provides an interface for destroying values.
  Values of types implementing this concept can be destroyed by `destroy(@This())` or `destroy(@This(), std.mem.Allocator)`.


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
    - trivial_destroy
        - isTrivialDestroy
    - destroy
        - Destroy
    - prelude
        - Clone
        - PartialEq
        - PartialOrd
        - Ord
        - Eq
        - Destroy


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

