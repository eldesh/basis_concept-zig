# Basis Concept Zig

**basis_concept-zig** is a collection library of basis concept and their operations.
Some basic concepts such as copy and compare are provided.


## Support

This library is developped with:

- Debian (x86_64) 10.4
- Zig 0.9.1
- Zigmod r79


## Build

```sh
zig build
```


## Unit Test

To performs unit tests of iter-zig:


```sh
zig build test
```


## Generate docs

To generate documentations:


```sh
zig build doc
```

A html documents would be generated under the `./docs` directory.


## Concept

*Concept* are named constraints on types such as Clonable.


In the Zig language, polymorphic functions are sometimes typed `fn (anytype) t`.
In practice, however, functions with such a type require some properties to be implicit in the value of `anytype`.

Naming this implicit constraint allows us to deal explicitly with constraints on types.



