# HavokOS

A minimal Linux-based desktop operating system with built-in HSL (Havok Scripting Library) customization.

## Features

- **Minimal & Fast** - Lightweight Debian Bookworm base with Openbox window manager
- **Custom Desktop** - Built with Python and GTK3
- **Havok Browser** - WebKit2GTK-based web browser
- **Havok Files** - Custom file manager with sidebar and context menus
- **Havok Editor** - Text/code editor with HSL syntax highlighting
- **Havok Settings** - System configuration panel (display, network, appearance, power, HSL)
- **HSL (Havok Scripting Library)** - Custom programming language (.hsl) for full OS customization
- **HavokCustom Folder** - Drop .hsl files on your desktop to extend the OS

## Running in QEMU (TCG)

```bash
qemu-system-x86_64 -cdrom HavokOS-1.0.0.iso -m 1024 -accel tcg
```

Minimum 512MB RAM recommended, 1024MB preferred.

## HSL - Havok Scripting Library

HSL is HavokOS's built-in scripting language. Files with the `.hsl` extension can be placed in:

- `~/Desktop/HavokCustom/` - Your custom extensions (loaded after system files)
- `~/Desktop/HavokCustom/IMPORTANT/` - System files (do not modify unless you know what you're doing)

### Example HSL

```hsl
# my_widget.hsl - A custom desktop widget

app "My Clock Widget" {
    type: "desktop_widget"
    width: 200
    height: 100
    x: 20
    y: 20

    label "Time" {
        text: shell("date +%H:%M:%S")
        color: "#e94560"
        font_size: 24
    }

    button "Refresh" {
        on click {
            label.text = shell("date +%H:%M:%S")
        }
    }
}
```

### HSL Built-in Functions

| Function | Description |
|----------|-------------|
| `print(...)` | Print to console |
| `shell(cmd)` | Run a shell command |
| `read_file(path)` | Read a text file |
| `write_file(path, content)` | Write a text file |
| `list_dir(path)` | List directory contents |
| `exists(path)` | Check if path exists |
| `mkdir(path)` | Create a directory |
| `getenv(name)` | Get environment variable |
| `sleep(seconds)` | Sleep for N seconds |
| `now()` | Get current timestamp |
| `len(x)` | Get length of string/list |
| `str(x)` / `int(x)` / `float(x)` | Type conversions |
| `range(start, stop, step)` | Generate number range |
| `upper(s)` / `lower(s)` | String case conversion |
| `contains(haystack, needle)` | Check if string contains substring |
| `replace(s, old, new)` | String replacement |
| `split(s, sep)` / `join(sep, list)` | String splitting/joining |

### HSL Control Flow

```hsl
# Variables
name = "HavokOS"
version = 1.0

# Conditions
if version > 1.0 {
    print("New version!")
} else {
    print("Current version")
}

# Loops
for item in ["a", "b", "c"] {
    print(item)
}

while true {
    print("Running...")
    sleep(1)
}

# Functions
func greet(name) {
    print("Hello, " + name + "!")
}

greet("World")
```

## Building from Source

The ISO is automatically built by GitHub Actions on push to main. To build locally:

```bash
# Requires: debootstrap, squashfs-tools, xorriso, isolinux, grub
sudo bash build/build.sh
```

## Project Structure

```
HavokOS/
├── .github/workflows/
│   └── build-iso.yml          # GitHub Actions CI workflow
├── build/
│   └── build.sh               # ISO build script
├── hsl/
│   ├── interpreter.py         # HSL interpreter
│   └── stdlib/                # HSL standard library
│       ├── ui.hsl
│       └── system.hsl
├── overlay/
│   ├── etc/                   # System configuration
│   ├── usr/
│   │   ├── bin/               # HavokOS applications
│   │   │   ├── havok-browser
│   │   │   ├── havok-files
│   │   │   ├── havok-editor
│   │   │   ├── havok-settings
│   │   │   ├── havok-desktop
│   │   │   └── havok-panel
│   │   └── share/applications/ # Desktop entries
│   └── home/havok/Desktop/
│       └── HavokCustom/
│           ├── IMPORTANT/      # System HSL files
│           │   ├── readme.txt
│           │   ├── desktop.hsl
│           │   ├── panel.hsl
│           │   ├── app_browser.hsl
│           │   ├── app_files.hsl
│           │   ├── app_editor.hsl
│           │   ├── app_settings.hsl
│           │   ├── menu.hsl
│           │   └── theme.hsl
│           └── (user .hsl files)
└── README.md
```

## License

MIT License
