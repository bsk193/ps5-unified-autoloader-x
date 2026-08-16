# ps5-unified-autoloader-x

A standalone PS5 ELF payload that automates loading payloads. This is intended for integration into jailbreak chains rather than direct end-user usage.

> [!NOTE]
> This is a fork of **[itsPLK/ps5-unified-autoloader](https://github.com/itsPLK/ps5-unified-autoloader)**
> with two changes:
>
> 1. It bundles **[Payload Manager X](https://github.com/bsk193/ps5-payload-manager-x)**
>    (`pldmgrx`, HTTP port **8084**) instead of the official
>    [Payload Manager](https://github.com/itsPLK/ps5-payload-manager).
> 2. It **always** starts the manager. Upstream starts it only when no `autoload.txt`
>    is found, so a leftover config silently suppresses it. Here `autoload.txt` is an
>    *additional* payload chain, not an alternative — its payloads run first, then the
>    manager starts.
>
> Everything else — browser handling, app killing, `autoload.txt` parsing, `@sync` — is
> upstream behaviour.
>
> Paired with **[ps5-webkit-autoloader-x](https://github.com/bsk193/ps5-webkit-autoloader-x)**.

## What it does

When loaded via elfldr (e.g. as part of your jailbreak chain), `autoloader.elf`:

1. **Kills the entry point app** (YouTube `PPSA01650`/`01651`/`01652` or Artemis Lua games like Aerial Life, Aibeya, etc.) if it is running
2. **Kills BD Disc Player** (NPXS40140) if it is running, using a careful suspend→wait→kill sequence
3. **Waits for elfldr** to be ready on port 9021 (up to 10 seconds)
4. **Looks for** the `autoload.txt` configuration file in the following order (highest priority first):
   - **App-specific directories on USB** (`/mnt/usb[0-7]/ps5_autoloader_<app>/autoload.txt`, where `<app>` is `bdjb` for BD Disc Player or the Title ID of the entry point app, e.g. `PPSA01650` for YouTube)
   - **App-specific directory in `/data`** (`/data/ps5_autoloader_<app>/autoload.txt`)
   - **Generic directories on USB** (`/mnt/usb[0-7]/ps5_autoloader/autoload.txt`)
   - **Generic directory in `/data`** (`/data/ps5_autoloader/autoload.txt`)
5. **If found**: launches each payload listed in the config via elfldr
6. **Always**: starts the bundled **Payload Manager X** (after a 2 s pause if a config ran)

## autoload.txt format

```
# This is a comment — ignored
@sync                  # move config directory to /data if all loads succeed
mypayload.elf          # loaded from the same directory as this autoload.txt
anotherpayload.elf
!1000                  # sleep 1000 ms before next entry
third_payload.elf
```

- One entry per line
- Filenames are resolved **relative to the directory containing autoload.txt**
  (e.g. if config is on `/mnt/usb0/ps5_autoloader/autoload.txt`, then
  `mypayload.elf` resolves to `/mnt/usb0/ps5_autoloader/mypayload.elf`)
- Absolute paths (starting with `/`) are used as-is
- Lines starting with `#` are comments
- Lines starting with `!` are sleep commands: `!<ms>` sleeps for that many milliseconds
- Lines starting with `@` are directives:
  - `@sync`: If loaded from a USB drive, this moves the entire active configuration directory (including all payloads and `autoload.txt`) to the internal `/data` partition on the PS5. The process runs only after all payloads have loaded successfully with zero errors. It clears the target internal directory, copies the files, verifies them byte-by-byte, and then deletes the folder from the USB drive so that subsequent boots run locally without needing the USB.

## Building

### Requirements
- Docker
- Node.js 20+ (only needed for `-b` builds — Payload Manager X's React frontend)
- git (with submodules, only needed for `-b` builds)

### Clone
```bash
git clone https://github.com/bsk193/ps5-unified-autoloader-x.git
cd ps5-unified-autoloader-x
```

### Build (download pre-built Payload Manager X — recommended)
```bash
./build_release.sh
# or explicitly:
./build_release.sh -d
```

Pulls the latest `pldmgrx_v*.elf` from
[bsk193/ps5-payload-manager-x](https://github.com/bsk193/ps5-payload-manager-x/releases)
and embeds it.

### Build (compile Payload Manager X from source)
```bash
git submodule update --init --recursive
./build_release.sh -b
```

This builds Payload Manager X's React frontend on the host, then compiles it with
`make PLDMGRX=1 PLDMGRX_PORT=8084` inside its own Docker image (which includes
libmicrohttpd, mbedTLS, libcurl), and finally uses a separate lean SDK image to
build the autoloader.

Set `PLDMGRX_PORT` to pick the manager's HTTP port:

| Port | Behaviour |
|---|---|
| `8084` (default) | Drop-in replacement for the official Payload Manager |
| `8184` | Runs alongside the official Payload Manager |

```bash
PLDMGRX_PORT=8184 ./build_release.sh -b
```

> The `-d` (download) path always yields the **8084** build, since that is what
> Payload Manager X publishes. Use `-b` if you need 8184.

### Output
```
autoloader_v0.1.4x_abc1234.elf
```

## Structure

```
autoloader.elf          ← load this via elfldr
  └─ pldmgr.elf         ← embedded Payload Manager X (always launched)
```

> The embedded ELF is staged under the filename `pldmgr.elf` on purpose: the
> Makefile runs `xxd -i` on it, so the generated symbols (`pldmgr_elf`,
> `pldmgr_elf_len`) referenced by `src/main.c` stay unchanged from upstream.