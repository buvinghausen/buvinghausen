## My Open Source Projects

### [SequentialGuid](https://github.com/buvinghausen/SequentialGuid)
[![NuGet](https://img.shields.io/nuget/v/SequentialGuid.svg)](https://www.nuget.org/packages/SequentialGuid/) [![NuGet Downloads](https://img.shields.io/nuget/dt/SequentialGuid.svg)](https://www.nuget.org/packages/SequentialGuid/)

A zero-dependency .NET library for generating RFC 9562 compliant, time-ordered UUIDs. Produces UUIDv7 (millisecond precision), UUIDv8 (tick precision), deterministic UUIDv5/v8 name-based, and random UUIDv4 identifiers — all with SQL Server sort-order support and built-in timestamp extraction. Ideal for reducing clustered index fragmentation while retaining the global uniqueness and merge-safety of standard UUIDs.

### [TaskTupleAwaiter](https://github.com/buvinghausen/TaskTupleAwaiter)
[![NuGet](https://img.shields.io/nuget/v/TaskTupleAwaiter.svg)](https://www.nuget.org/packages/TaskTupleAwaiter/) [![NuGet Downloads](https://img.shields.io/nuget/dt/TaskTupleAwaiter.svg)](https://www.nuget.org/packages/TaskTupleAwaiter/)

A lightweight .NET library that lets you `await` a tuple of tasks and destructure the results in a single line. Supports up to 16 tasks with mixed return types, `ConfigureAwait`, and .NET 8+ `ConfigureAwaitOptions` — no `Task.WhenAll` boilerplate required.
