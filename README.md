# Debian Trixie Development Environment

A comprehensive, single-image development environment built on Debian Trixie. Designed for web, C/C++, and Python development with strict architecture constraints (Westmere-safe, no AVX-512) and fully self-contained offline caching capabilities.

## Pre-built Image

- **nvim-container**: Main container image baking Dockerfile onto github container registry. [![build-nvim-env](https://github.com/sar/nvim-container/actions/workflows/build-dev.yml/badge.svg)](https://github.com/sar/nvim-container/actions/workflows/build-dev.yml)


## Stack Details

| Component | Specification |
| :--- | :--- |
| **Base OS** | Debian Trixie (13) - `main` and `contrib` only (no `non-free`) |
| **Python** | 3.15.2 (Compiled from source to `/usr/local`) |
| **Node.js** | 24.x (Auto-resolved latest) |
| **Neovim** | 0.11.5 (Pre-built Linux x86_64 binary) |
| **Shell** | Zsh with Powerlevel10k, syntax highlighting, autosuggestions, history search |
| **C/C++ Toolchain** | GCC, Clang, CMake, Ninja, Boost, OpenCV, LLVM, Valgrind |
| **Target ISA** | x86_64 (`-march=westmere -mtune=generic`), AVX-512 disabled |
| **Container Runtimes** | Docker (`docker.io`), Podman, Buildah, Skopeo, containerd |
| **Orchestration** | Docker Compose v2.36.0, Podman Compose 1.2.0 |
| **Networking/Security** | ClamAV daemon, StevenBlack hosts, HTTPS-only APT sources |
| **Git Tooling** | GitUI 0.28.1, GitHub CLI, git-lfs, git-flow, tig |
| **Web/Scraping** | Chromium, w3m, lynx, Scrapy, BeautifulSoup4, Playwright, Selenium |

## Directory Layout

All downloaded artifacts, source code, caches, and toolchains are persisted under `/workspace`. This allows the image to be exported and rebuilt offline, and keeps APT caches intact (no `apt-get clean`).

```text
/workspace
├── bin/                  # Helper scripts and symlinks (fd, bat, gitui, docker-compose)
├── downloads/            # Cached tarballs, zips, and source archives
│   ├── fonts/            # Nerd Fonts zips (JetBrains, Fira, Hack, Meslo)
│   ├── gitui.tar.gz
│   ├── nvim-linux-x86_64.tar.gz
│   └── Python-3.15.2.tgz
├── src/                  # Extracted source code (e.g., Python compilation tree)
│   └── python/
├── fonts/                # Extracted Nerd Fonts
├── hosts/                # StevenBlack hosts file cache
├── node/                 # Node.js binary distribution
├── nvim/                 # Neovim binary extraction
├── venv/                 # Python 3.15 virtual environment (active in PATH)
├── yarn-global/          # Yarn global packages (webpack, create-react-app)
├── zsh/                  # Zsh plugins (powerlevel10k, zsh-autosuggestions, etc.)
├── project/              # Default WORKDIR for container execution
├── npm-cache/            # Persistent npm cache
├── yarn-cache/           # Persistent yarn cache
├── pip-cache/            # Persistent pip cache
├── debs -> /var/cache/apt/archives   # APT deb cache symlink
└── apt-lists -> /var/lib/apt/lists   # APT lists symlink
```

## Build Instructions

### Local Build

The image defaults to Westmere-safe compilation flags. 

```bash
docker build -t devbox:local .
```

To override the target CPU architecture (e.g., if building natively on a modern host and you want to utilize AVX2):

```bash
docker build \
  --build-arg TARGET_CPU=native \
  -t devbox:local .
```

### Offline Cache Export

To extract the downloaded artifacts and APT caches for offline rebuilding on another machine:

```bash
docker run --rm -v $(pwd)/offline-cache:/output devbox:local \
  /workspace/bin/export-offline-cache /output
```

## Execution

### Interactive Neovim Session (Default)

Drops into a Zsh shell as the `user` user and launches Neovim. Requires `--privileged` for nested Docker/Podman and systemd capabilities.

```bash
docker run --rm -it \
  --privileged \
  --name devbox \
  devbox:local
```

### Systemd Runtime

To run the image with systemd as PID 1 (starts Docker, Podman, and ClamAV daemons automatically):

```bash
docker run --rm -d \
  --privileged \
  --tmpfs /run \
  --tmpfs /run/lock \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --name devbox \
  devbox:local systemd
```

### Root Shell

Bypass the default user drop-in and execute directly as root:

```bash
docker run --rm -it \
  -e DROP_TO_USER=0 \
  devbox:local bash
```

## GitHub Actions CI/CD

The repository includes a `.github/workflows/build-devbox.yml` workflow. It automatically handles disk space cleanup on GitHub runners, builds the image via `docker/build-push-action`, and runs smoke tests against the resulting binaries and Python imports.

Trigger the workflow manually via the Actions tab or push to `main`/`master`.

## Known Issues & Constraints

1. **Ansible on Python 3.15**: 
   Ansible is excluded from the Python 3.15 virtual environment (`/workspace/venv`) because it relies on monkey-patching internal Python modules (`dataclasses._is_type`) that were removed in Python 3.15. 
   *Resolution*: The system-level `ansible` binary installed via APT (Debian Trixie's system Python) is used instead and functions correctly.

2. **APT Source Bootstrapping**: 
   The base `debian:trixie` image lacks the `ca-certificates` package. The Dockerfile temporarily downgrades APT sources to `http://` to install `ca-certificates`, updates the CA bundle, and then reverts to `https://` for all subsequent operations.

3. **PyTorch / AVX Instructions**: 
   CPU-only PyTorch is disabled by default (`INSTALL_PYTORCH_CPU=0`). Official PyTorch wheels frequently require AVX/AVX2 instructions which are not present on Intel Westmere architectures. If your target hardware supports AVX2, enable it via `--build-arg INSTALL_PYTORCH_CPU=1`.