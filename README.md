# dart_osgi

An OSGi framework for Dart, for use with [ivi-homescreen](https://github.com/toyota-connected/ivi-homescreen) 3.0.

The shell already knows how to run several Flutter engines in one process, hold
a startup deadline for a critical bundle, and tear down one that misses it.
What it does not have is a Dart-side framework: the lifecycle, the service
registry, and the transport between the two. That is what lives here.

## Packages

| Package | Depends on Flutter | What it is |
|---|:---:|---|
| `osgi_api` | no | Interfaces only: bundle lifecycle, activator, service registry, and the shell transport seam. |
| `osgi_framework` | no | The framework itself. Runs in the framework isolate. |
| `osgi_flutter` | yes | The MethodChannel shell transport. No widgets: a bundle that wants to show its own lifecycle renders `ManagedBundle.states` directly. |
| `osgi_ffi` | no | The FFI shell transport, through `libihs_shared`. What a headless bundle uses: no UI binding, and the ACTIVE report never crosses the platform thread. |
| `osgi_test` | no | Test doubles, so an activator can be tested without a shell, an engine, or a display. |

The split is not cosmetic. A headless bundle -- a CAN decoder, a telemetry sink
-- has no views, and dragging in a UI binding so it can send three integers to
the shell is the kind of dependency that later turns out to be load-bearing.
Such a bundle depends on `osgi_api` and `osgi_framework`, plus `osgi_ffi` if it
has to announce itself to the shell at all -- and never on Flutter.

## MethodChannel or FFI?

Both, for different things, and the distinction matters more than the answer.
There are three data paths and they do not want the same mechanism:

**1. Bootstrap and lifecycle** — a bundle announcing itself, and later reporting
that its activator finished. A handful of messages per bundle, each a few
integers and a string.

This is a `MethodChannel` (`dev.osgi/bridge`), and it is the only path that
crosses into native code. It is the default because it is what runs today: the
handshake is validated on hardware against a shell that needs no changes to
accept it (by ivi-homescreen's minimal test activator, which speaks the same
handshake).

It has two costs. It couples the ACTIVE report to the platform thread, which is
at its busiest during exactly the window that report needs to cross -- and a
critical bundle's startup deadline is running the whole time. It also makes a
headless bundle initialize a UI binding for no other reason. An FFI transport
through `libihs_shared.so`, already the documented surface for out-of-tree
plugins, avoids both.

**Both transports are kept, and that is a security requirement rather than a
convenience.** An FFI transport requires every bundle to hold `dart:ffi`, which
grants arbitrary read and write over the entire process address space and
`dlopen` of libc — so it is exactly the capability an untrusted bundle must not
have. Bundles that ship as part of a signed image use FFI; third-party bundles
are meant to get the channel and no `dart:ffi` at all, at the cost of the fast
paths below.

That is the target, not today. The channel transport still uses `dart:ffi`
itself: `NativeApi.initializeApiDLData` and `SendPort.nativePort`, which the
handshake sends to the shell, both live there. An ffi-free tier needs the shell
to deliver the framework port over the channel instead.

No in-process capability scheme changes this. See
[DR-001](docs/decisions/DR-001.md) for what was checked and why a proc-address
design in the style of `eglGetProcAddress` does not hold.

`ShellTransport` is the interface both implement, so a bundle's code does not
change when its tier does.

**2. Between bundles** — service lookups, events, registry traffic. High
frequency, ordinary Dart objects.

This never touches native code at all. All engines in an ivi-homescreen process
share one Dart VM, so bundles are isolates in one address space and this is
`SendPort` between them. Routing it through a platform channel would marshal
every call through the platform thread to reach a destination in the same
process.

**3. Bulk payloads** — point clouds, camera frames, decoded video.

Anything that copies is not viable at frame rate. `Pointer.address` travels as
an `int` over a `SendPort` and the receiving isolate reconstitutes the pointer;
isolates share the process address space, so nothing is copied. This is the
zero-copy path, and it does not need FFI *calls* to work -- only FFI *pointers*.

So "MethodChannel vs zero-copy FFI" is a false choice for path 1, and paths 2
and 3 are already zero-copy without either being involved.

**Paths 2 and 3 both depend on bundles sharing one Dart VM.** A bundle isolated
into its own process for the reasons above loses both, and everything it sends
goes over the channel. That is the real price of the untrusted tier, and it is
why DR-001 is a premise-level constraint rather than a transport detail.

## Layout

Native [pub workspaces](https://dart.dev/tools/pub/workspaces) (Dart 3.6+)
rather than melos -- one lockfile, one `.dart_tool`, no extra tool to keep
current.

`osgi_flutter` depends on the Flutter SDK and a workspace resolves as a unit, so
resolve with `flutter pub get`, not `dart pub get`. The three pure-Dart packages
still analyze and test with plain `dart`.

```sh
flutter pub get
dart analyze
(cd packages/osgi_api       && dart test)
(cd packages/osgi_framework && dart test)
(cd packages/osgi_test      && dart test)
(cd packages/osgi_flutter   && flutter test)
```

> Run `dart test` from each package root rather than passing directories to one
> invocation: `osgi_test`'s own library file is `lib/osgi_test.dart`, which
> matches the runner's `*_test.dart` glob when it recurses.

## Status

Early. Implemented and tested: the transport seam, the lifecycle model, a
service registry with LDAP filters, an event admin, the bundle lifecycle --
`ManagedBundle`, which runs one bundle's activator against the shell and
reports ACTIVE when it has really finished -- the framework isolate, which lets
bundles in separate isolates publish and find each other's services, and a
loader that spawns a pure-Dart bundle into its own isolate and runs it there.
The FFI transport (`osgi_ffi`) is written and unit-tested, and both halves it
depends on are now merged upstream: the `ihs_osgi_*` surface in `libihs_shared`
(ivi-homescreen #538) and the shell host that installs the proc table behind it
(#540). The boundary itself is now tested against a real Dart VM and a real
`libihs_shared` on every CI run: registration crosses, the shell's
`Dart_CObject_kSendPort` materialises as a `SendPort` the bundle can actually
send through, a minted handle is honoured and a forged one refused.

What is still unproven is the deployment, not the boundary -- two bundles, two
engines, two connectors, critical-first ordering. That is what
`test/osgi_multi_bundle.sh` asserts, and it runs on virtual KMS rather than a
board, so "not yet run on hardware" remains true of the whole path even once it
is green.

No lifecycle widgets are supplied, and that is a decision rather than a gap.
`ManagedBundle.state` is a `BundleState` and `ManagedBundle.states` a
`Stream<BundleState>`, so a bundle that wants to show its own lifecycle wraps
the stream in a `StreamBuilder` and renders whatever suits it -- `isLive` and
`isTerminal` are on `BundleState` for exactly that. A widget set here would have
to guess at the shape (an overlay? a banner? a gate holding the tree back until
ACTIVE?), and every bundle that disagreed would carry the guess anyway.

The shell side is merged in ivi-homescreen `v3.0` (#419–#431, plus #537, #538
and #540 for the declared-name check and the FFI path), and its critical-first
startup ordering has been proven on hardware with a minimal activator. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for what exists in each package.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — the process, the three data
  paths, the lifecycle, and the handshake from a bundle's side.
- [docs/decisions/DR-001.md](docs/decisions/DR-001.md) — why third-party
  bundles cannot be isolated in-process.

## License

MIT. See [LICENSE](LICENSE).
