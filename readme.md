# zig-leveldb

zig-leveldb is a Zig wrapper for LevelDB, providing a simple and efficient way to interact with LevelDB from Zig programs.

## Features

- Zig bindings for LevelDB
- Key-value storage with high performance
- Support for basic LevelDB operations (get, put, delete, iterate)
- Easy-to-use API
- Built with Zig's safety and performance in mind

## Installation

Before:

```bash
sudo dnf install -y leveldb-devel
```

After:

```bash
zig build run
zig build test
