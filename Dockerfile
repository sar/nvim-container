# syntax=docker/dockerfile:1.7

################################################################################
# Base image
#
# Using official Debian Trixie.
# Python 3.15.2 is built from source to guarantee the absolute latest version.
################################################################################

FROM debian:trixie

LABEL org.opencontainers.image.title="debian-trixie-westmere-web-cpp-python-nvim-devbox" \
      org.opencontainers.image.description="Trixie kitchen-sink dev image: Neovim, Node, Python 3.15 from source, C/C++, Docker, Podman, Zsh, scraping tools, ClamAV, StevenBlack hosts. Sources/caches stored under /workspace." \
      org.opencontainers.image.version="4.1.0"

################################################################################
# Build args
################################################################################

ARG DEBIAN_FRONTEND=noninteractive

ARG APP_USER=user
ARG APP_UID=1000
ARG APP_GID=1000

ARG TARGET_CPU=westmere

# Python latest stable as of late Oct 2026
ARG PYTHON_VERSION=3.15.2

ARG NODE_MAJOR=24
ARG NODE_VERSION=auto
ARG NEOVIM_VERSION=v0.11.5
ARG NERDFONTS_VERSION=v3.3.0
ARG GITUI_VERSION=0.27.0
ARG DOCKER_COMPOSE_VERSION=v2.36.0
ARG PODMAN_COMPOSE_VERSION=1.2.0
ARG INSTALL_PYTORCH_CPU=0
ARG GH_VERSION=latest

ARG ZSH_SYNTAX_HIGHLIGHTING_VERSION=master
ARG ZSH_AUTOSUGGESTIONS_VERSION=master
ARG ZSH_HISTORY_SUBSTRING_SEARCH_VERSION=master
ARG ZSH_COMPLETIONS_VERSION=master
ARG POWERLEVEL10K_VERSION=master
ARG GITSTATUS_VERSION=master

################################################################################
# Global environment
################################################################################

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    TARGET_CPU=${TARGET_CPU} \
    CFLAGS="-march=${TARGET_CPU} -mtune=generic -O2 -pipe" \
    CXXFLAGS="-march=${TARGET_CPU} -mtune=generic -O2 -pipe" \
    PATH="/workspace/venv/bin:/workspace/node/bin:/workspace/yarn-global/bin:/workspace/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PIP_NO_CACHE_DIR=0 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_CACHE_DIR=/workspace/pip-cache \
    VIRTUAL_ENV=/workspace/venv \
    NPM_CONFIG_PREFIX=/workspace/node \
    NPM_CONFIG_CACHE=/workspace/npm-cache \
    YARN_PREFIX=/workspace/yarn-global \
    YARN_CACHE_FOLDER=/workspace/yarn-cache \
    EDITOR=nvim \
    VISUAL=nvim \
    GIT_EDITOR=nvim \
    DOCKER_HOST=unix:///var/run/docker.sock \
    LIBTORCH_ROOT=/workspace/libtorch \
    CMAKE_PREFIX_PATH="/workspace/libtorch:/usr/local" \
    CHROME_BIN=/usr/bin/chromium \
    BROWSER=/usr/bin/chromium \
    APP_USER=user \
    START_CONTAINERD=1 \
    START_DOCKER=1 \
    START_PODMAN_SERVICE=1 \
    START_CLAMAV=1 \
    DROP_TO_USER=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

################################################################################
# Override APT sources (HTTPS only, main + contrib only, no non-free)
#
# Bootstrap ca-certificates over HTTP first, because the base image lacks the
# root CAs required to verify deb.debian.org's HTTPS certificates.
################################################################################

RUN set -eux; \
    rm -f /etc/apt/sources.list || true; \
    rm -f /etc/apt/sources.list.d/* || true; \
    . /etc/os-release; \
    CODENAME="${VERSION_CODENAME:-trixie}"; \
    { \
        echo "deb http://deb.debian.org/debian ${CODENAME} main contrib"; \
        echo "deb http://deb.debian.org/debian ${CODENAME}-updates main contrib"; \
        echo "deb http://security.debian.org/debian-security ${CODENAME}-security main contrib"; \
    } > /etc/apt/sources.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    update-ca-certificates; \
    { \
        echo "deb https://deb.debian.org/debian ${CODENAME} main contrib"; \
        echo "deb https://deb.debian.org/debian ${CODENAME}-updates main contrib"; \
        echo "deb https://security.debian.org/debian-security ${CODENAME}-security main contrib"; \
    } > /etc/apt/sources.list; \
    apt-get update

################################################################################
# APT behavior: keep downloaded debs and package lists.
################################################################################

RUN set -eux; \
    rm -f /etc/apt/apt.conf.d/docker-clean /etc/apt/apt.conf.d/docker-gzip-indexes || true; \
    printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\nAPT::Keep-Downloaded-Packages "true";\nAPT::Get::Assume-Yes "true";\nAPT::Install-Recommends "true";\n' > /etc/apt/apt.conf.d/99dev-keep-packages; \
    mkdir -p \
        /workspace /workspace/bin /workspace/downloads /workspace/src /workspace/fonts \
        /workspace/hosts /workspace/node /workspace/nvim /workspace/venv /workspace/yarn-global \
        /workspace/npm-cache /workspace/yarn-cache /workspace/pip-cache /workspace/zsh /workspace/project \
        /var/cache/apt/archives/partial /var/lib/apt/lists; \
    chmod 0755 /workspace; \
    ln -sfn /var/cache/apt/archives /workspace/debs; \
    ln -sfn /var/lib/apt/lists /workspace/apt-lists

################################################################################
# Minimal prerequisites
################################################################################

RUN set -eux; \
    apt-get install -y --no-install-recommends \
        curl gnupg jq unzip xz-utils wget

################################################################################
# Large APT package set with dynamic availability checks.
################################################################################

RUN set -eux; \
    add_all() { \
        for p in "$@"; do \
            if apt-cache show "$p" >/dev/null 2>&1; then PKGS+=("$p"); \
            else echo "WARN: missing package: $p"; fi; \
        done; \
    }; \
    add_any() { \
        for p in "$@"; do \
            if apt-cache show "$p" >/dev/null 2>&1; then PKGS+=("$p"); return 0; fi; \
        done; \
        echo "WARN: none of these packages were available: $*"; return 0; \
    }; \
    PKGS=(); \
    add_all \
        ansible apparmor autoconf automake autotools-dev bash bash-completion bat bc bison \
        bridge-utils build-essential bzip2 ca-certificates ccache chromium clang clang-format \
        clang-tidy clang-tools clamav clamav-daemon clamav-freshclam cmake cmake-extras cmatrix \
        containernetworking-plugins cpio cppcheck cowsay crun curl dbus dbus-user-session \
        dh-autoreconf dirmngr dnsutils dwarves fd-find ffmpeg figlet file findutils flex \
        fontconfig fonts-dejavu fonts-liberation fonts-noto fonts-powerline fortune-mod fzf \
        fuse-overlayfs fuse3 g++ gcc gdb git git-extras git-filter-repo git-flow git-lfs \
        gnupg gnupg2 gosu gpg-agent grep gzip htop html-xml-utils html2text httpie iftop \
        imagemagick iproute2 iptables iputils-ping jo jq kmod ksh less libacl1-dev libapparmor-dev \
        libatk-bridge2.0-dev libatk1.0-dev libattr1-dev libavcodec-dev libavdevice-dev \
        libavfilter-dev libavformat-dev libavutil-dev libbenchmark-dev libboost-all-dev libbpf-dev \
        libbz2-dev libcairo2-dev libcap-dev libclang-dev libc++-dev libc++abi-dev libcrypt-dev \
        libdb-dev libdrm-dev libelf-dev libffi-dev libfmt-dev libgbm-dev libgdk-pixbuf-2.0-dev \
        libgl1-mesa-dev libglib2.0-dev libglu1-mesa-dev libgmock-dev libgdbm-dev libgtest-dev \
        libgtk-3-dev libgrpc++-dev libgrpc-dev liblzma-dev libmagickcore-dev libmagickwand-dev \
        libmsgpack-cxx-dev libmsgpack-dev libncurses-dev libnss3-dev libopencv-dev libpango1.0-dev \
        libpq-dev libprotobuf-dev libreadline-dev libsqlite3-dev libssl-dev libspdlog-dev \
        libswresample-dev libswscale-dev libtool libudev-dev libuuid1 libvips-dev libvips-tools \
        libwebp-dev libx11-dev libx11-xcb-dev libx11-xcb1 libxcb1-dev libxcomposite-dev \
        libxcursor-dev libxdamage-dev libxext-dev libxfixes-dev libxi-dev libxml2-dev \
        libxml2-utils libxrandr-dev libxrender-dev libxslt1-dev libxss-dev libxtst-dev \
        libyaml-cpp-dev libzmq3-dev libzstd-dev links2 linux-base linux-headers-amd64 \
        linux-libc-dev lld lldb llvm llvm-dev locales lolcat lsof ltrace lynx make man-db \
        manpages-dev miller moreutils mtr-tiny nano ncurses-term net-tools netcat-openbsd \
        ninja-build nlohmann-json3-dev openssh-client openssh-server p7zip-full pahole patch \
        pgcli pkg-config podman postgresql-client procps protobuf-compiler protobuf-compiler-grpc \
        proxychains4 psmisc pspg ranger rapidjson-dev ripgrep rsync screen sed shellcheck \
        silversearcher-ag sl slirp4netns socat sshpass strace sudo systemd systemd-sysv tar \
        tig tmux toilet traceroute trash-cli tree uidmap unzip uuid-dev valgrind vim w3m w3m-img \
        wget whois xauth xmlstarlet xz-utils yamllint zip zlib1g-dev zsh; \
    add_all buildah skopeo; \
    add_any docker.io docker-ce; \
    add_any containerd containerd.io; \
    add_any runc; \
    add_any gh; \
    add_any neofetch fastfetch; \
    add_any tidy tidy-html5; \
    add_any libasound2-dev libasound2t64-dev; \
    add_any libcups2-dev libcups2t64-dev; \
    add_any libcurl4-openssl-dev libcurl4t64-dev; \
    if [ "${#PKGS[@]}" -gt 0 ]; then \
        mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | sort -u); \
        apt-get install -y "${PKGS[@]}"; \
    else echo "ERROR: no APT packages resolved" >&2; exit 1; fi; \
    update-alternatives --set editor /usr/bin/vim.basic || true; \
    systemd-machine-id-setup || true; \
    sed -i 's/^# *C.UTF-8 UTF-8/C.UTF-8 UTF-8/' /etc/locale.gen || true; \
    locale-gen || true; \
    ln -sf /usr/bin/fdfind /workspace/bin/fd || true; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd || true; \
    ln -sf /usr/bin/batcat /workspace/bin/bat || true; \
    ln -sf /usr/bin/batcat /usr/local/bin/bat || true; \
    if command -v fastfetch >/dev/null 2>&1 && ! command -v neofetch >/dev/null 2>&1; then \
        ln -sf "$(command -v fastfetch)" /usr/local/bin/neofetch; \
    fi; \
    git config --system init.defaultBranch main; \
    git config --system core.editor nvim; \
    git config --system pull.rebase false; \
    chmod 755 /sbin /usr/sbin /usr/local/sbin || true; \
    chmod 4755 /usr/bin/sudo /usr/bin/passwd /usr/bin/su || true

################################################################################
# GitHub CLI fallback if Debian's gh package was unavailable.
################################################################################

RUN set -eux; \
    if ! command -v gh >/dev/null 2>&1; then \
        GH_TAG="${GH_VERSION}"; \
        if [ "${GH_TAG}" = "latest" ] || [ -z "${GH_TAG}" ]; then \
            GH_TAG="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | jq -r .tag_name | sed 's/^v//')"; \
        fi; \
        GH_TAG="${GH_TAG#v}"; \
        ARCH="$(dpkg --print-architecture)"; \
        curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_TAG}/gh_${GH_TAG}_linux_${ARCH}.tar.gz" \
            -o /workspace/downloads/gh.tar.gz; \
        mkdir -p /tmp/gh; \
        tar -C /tmp/gh --strip-components=1 -xzf /workspace/downloads/gh.tar.gz; \
        install -m 0755 /tmp/gh/bin/gh /workspace/bin/gh; \
        ln -sf /workspace/bin/gh /usr/local/bin/gh; \
        rm -rf /tmp/gh; \
    fi; \
    gh --version

################################################################################
# Build Python latest (3.15.2) from source
################################################################################

RUN set -eux; \
    mkdir -p /workspace/src/python; \
    wget -O /workspace/downloads/Python-${PYTHON_VERSION}.tgz \
        "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz"; \
    tar -C /workspace/src/python --strip-components=1 -xzf /workspace/downloads/Python-${PYTHON_VERSION}.tgz; \
    cd /workspace/src/python; \
    ./configure --prefix=/usr/local; \
    make -j "$(nproc)"; \
    make altinstall; \
    ln -sf /usr/local/bin/python3.15 /usr/local/bin/python; \
    ln -sf /usr/local/bin/pip3.15 /usr/local/bin/pip; \
    python --version; \
    pip --version

################################################################################
# Default user: user
################################################################################

RUN set -eux; \
    if ! getent group "${APP_GID}" >/dev/null 2>&1; then groupadd --gid "${APP_GID}" "${APP_USER}"; fi; \
    if ! id -u "${APP_USER}" >/dev/null 2>&1; then \
        useradd --uid "${APP_UID}" --gid "${APP_GID}" --home-dir "/home/${APP_USER}" \
            --create-home --shell /usr/bin/zsh "${APP_USER}"; \
    fi; \
    usermod -aG sudo "${APP_USER}"; \
    usermod -aG docker "${APP_USER}" || true; \
    echo "${APP_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${APP_USER}"; \
    echo 'Defaults secure_path="/workspace/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' > /etc/sudoers.d/99-secure-path; \
    chmod 0440 "/etc/sudoers.d/${APP_USER}" /etc/sudoers.d/99-secure-path; \
    mkdir -p "/home/${APP_USER}/workspace" "/home/${APP_USER}/.config" \
        "/home/${APP_USER}/.local/share/nvim" "/home/${APP_USER}/.cache"; \
    chown -R "${APP_UID}:${APP_GID}" "/home/${APP_USER}"

################################################################################
# Docker / Podman Setup & Compose
################################################################################

RUN set -eux; \
    mkdir -p /etc/systemd/system/multi-user.target.wants; \
    ln -sf /lib/systemd/system/docker.service /etc/systemd/system/multi-user.target.wants/docker.service || true; \
    ln -sf /lib/systemd/system/containerd.service /etc/systemd/system/multi-user.target.wants/containerd.service || true; \
    COMPOSE_TAG="${DOCKER_COMPOSE_VERSION#v}"; COMPOSE_TAG="v${COMPOSE_TAG}"; \
    curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_TAG}/docker-compose-linux-x86_64" \
        -o /workspace/downloads/docker-compose-linux-x86_64; \
    install -m 0755 /workspace/downloads/docker-compose-linux-x86_64 /workspace/bin/docker-compose; \
    ln -sf /workspace/bin/docker-compose /usr/local/bin/docker-compose; \
    mkdir -p /usr/local/lib/docker/cli-plugins /usr/lib/docker/cli-plugins /usr/libexec/docker/cli-plugins; \
    ln -sf /workspace/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose; \
    ln -sf /workspace/bin/docker-compose /usr/lib/docker/cli-plugins/docker-compose; \
    ln -sf /workspace/bin/docker-compose /usr/libexec/docker/cli-plugins/docker-compose; \
    docker-compose --version; \
    mkdir -p /etc/containers /etc/containers/networks /var/lib/containers /run/containers; \
    printf '[storage]\ndriver = "vfs"\ngraphroot = "/var/lib/containers/storage"\nrunroot = "/run/containers/storage"\n' > /etc/containers/storage.conf; \
    printf '[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' > /etc/containers/containers.conf; \
    printf 'unqualified-search-registries = ["docker.io"]\n\n[[registry]]\nprefix = "docker.io"\nlocation = "docker.io"\n' > /etc/containers/registries.conf; \
    { echo "root:100000:65536"; echo "${APP_USER}:165536:65536"; } > /etc/subuid; \
    { echo "root:100000:65536"; echo "${APP_USER}:165536:65536"; } > /etc/subgid; \
    chown root:root /usr/bin/newuidmap /usr/bin/newgidmap 2>/dev/null || true; \
    chmod 4755 /usr/bin/newuidmap /usr/bin/newgidmap 2>/dev/null || true; \
    podman --version || true

################################################################################
# Neovim, Node, NPM, Yarn, NerdFonts, GitUI, Zsh Plugins
################################################################################

RUN set -eux; \
    NEOVIM_TAG="${NEOVIM_VERSION}"; \
    if [ "${NEOVIM_TAG}" = "latest" ]; then NEOVIM_TAG="$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest | jq -r .tag_name)"; fi; \
    NEOVIM_TAG="${NEOVIM_TAG#v}"; NEOVIM_TAG="v${NEOVIM_TAG}"; \
    curl -fsSL "https://github.com/neovim/neovim/releases/download/${NEOVIM_TAG}/nvim-linux-x86_64.tar.gz" \
        -o /workspace/downloads/nvim-linux-x86_64.tar.gz || curl -fsSL "https://github.com/neovim/neovim/releases/download/${NEOVIM_TAG}/nvim-linux64.tar.gz" -o /workspace/downloads/nvim-linux-x86_64.tar.gz; \
    mkdir -p /workspace/nvim; \
    tar -C /workspace/nvim --strip-components=1 -xzf /workspace/downloads/nvim-linux-x86_64.tar.gz; \
    ln -sf /workspace/nvim/bin/nvim /workspace/bin/nvim; ln -sf /workspace/nvim/bin/nvim /usr/local/bin/nvim; \
    nvim --version; \
    NODE_VERSION_INPUT="${NODE_VERSION}"; NODE_VERSION_INPUT="${NODE_VERSION_INPUT#v}"; \
    if [ -z "${NODE_VERSION_INPUT}" ] || [ "${NODE_VERSION_INPUT}" = "auto" ] || [ "${NODE_VERSION_INPUT}" = "latest" ]; then \
        NODE_URL_BASE="https://nodejs.org/download/release/latest-v${NODE_MAJOR}.x"; \
        RESOLVED_NODE_VERSION="$(curl -fsSL "${NODE_URL_BASE}/SHASUMS256.txt" | awk '/linux-x64\.tar\.xz$/ {print $2; exit}' | sed -E 's/^node-v//; s/-linux-x64\.tar\.xz$//')"; \
        NODE_TAR_URL="${NODE_URL_BASE}/node-v${RESOLVED_NODE_VERSION}-linux-x64.tar.xz"; \
    else RESOLVED_NODE_VERSION="${NODE_VERSION_INPUT}"; NODE_TAR_URL="https://nodejs.org/dist/v${RESOLVED_NODE_VERSION}/node-v${RESOLVED_NODE_VERSION}-linux-x64.tar.xz"; fi; \
    curl -fsSL "${NODE_TAR_URL}" -o /workspace/downloads/node-linux-x64.tar.xz; \
    mkdir -p /workspace/node; \
    tar -xJf /workspace/downloads/node-linux-x64.tar.xz -C /workspace/node --strip-components=1; \
    ln -sf /workspace/node/bin/node /workspace/bin/node; ln -sf /workspace/node/bin/npm /workspace/bin/npm; ln -sf /workspace/node/bin/npx /workspace/bin/npx; \
    ln -sf /workspace/node/bin/node /usr/local/bin/node; ln -sf /workspace/node/bin/npm /usr/local/bin/npm; ln -sf /workspace/node/bin/npx /usr/local/bin/npx; \
    node --version; npm --version; \
    npm config set save-exact true; npm config set save-dev true; npm config set fund false; npm config set audit false; \
    npm install -g npm@latest; \
    npm install --global --save-dev --save-exact @ansible/ansible-language-server @aws-amplify/cli bash-language-server dockerfile-language-server-nodejs eslint eslint_d prettier remark remark-cli remark-language-server typescript typescript-language-server vscode-langservers-extracted yaml-language-server yarn; \
    mkdir -p /workspace/yarn-global; yarn config set prefix /workspace/yarn-global || true; \
    yarn global add webpack webpack-cli create-react-app; \
    if [ -d /workspace/yarn-global/bin ]; then for f in /workspace/yarn-global/bin/*; do [ -e "${f}" ] && ln -sf "${f}" /workspace/bin/; done; fi; \
    NF_TAG="${NERDFONTS_VERSION}"; if [ "${NF_TAG}" = "latest" ]; then NF_TAG="$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | jq -r .tag_name)"; fi; \
    mkdir -p /workspace/downloads/fonts /workspace/fonts /usr/share/fonts/truetype/nerdfonts; \
    for f in JetBrainsMono FiraCode Hack Meslo; do \
        curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NF_TAG}/${f}.zip" -o "/workspace/downloads/fonts/${f}.zip" || continue; \
        unzip -o "/workspace/downloads/fonts/${f}.zip" -d "/workspace/fonts/${f}"; \
        mkdir -p "/usr/share/fonts/truetype/nerdfonts/${f}"; cp -r "/workspace/fonts/${f}/." "/usr/share/fonts/truetype/nerdfonts/${f}/"; \
    done; fc-cache -f || true; \
    GITUI_TAG="${GITUI_VERSION}"; if [ "${GITUI_TAG}" = "latest" ]; then GITUI_TAG="$(curl -fsSL https://api.github.com/repos/extrawurst/gitui/releases/latest | jq -r .tag_name)"; fi; \
    GITUI_TAG="${GITUI_TAG#v}"; \
    curl -fsSL "https://github.com/extrawurst/gitui/releases/download/v${GITUI_TAG}/gitui-linux-musl.tar.gz" -o /workspace/downloads/gitui.tar.gz || curl -fsSL "https://github.com/extrawurst/gitui/releases/download/v${GITUI_TAG}/gitui-linux.tar.gz" -o /workspace/downloads/gitui.tar.gz; \
    tar -xzf /workspace/downloads/gitui.tar.gz -C /workspace/bin; chmod 0755 /workspace/bin/gitui; ln -sf /workspace/bin/gitui /usr/local/bin/gitui; gitui --version; \
    mkdir -p /workspace/zsh/plugins; \
    git clone --depth=1 --branch "${ZSH_SYNTAX_HIGHLIGHTING_VERSION}" https://github.com/zsh-users/zsh-syntax-highlighting.git /workspace/zsh/plugins/zsh-syntax-highlighting; \
    git clone --depth=1 --branch "${ZSH_AUTOSUGGESTIONS_VERSION}" https://github.com/zsh-users/zsh-autosuggestions.git /workspace/zsh/plugins/zsh-autosuggestions; \
    git clone --depth=1 --branch "${ZSH_HISTORY_SUBSTRING_SEARCH_VERSION}" https://github.com/zsh-users/zsh-history-substring-search.git /workspace/zsh/plugins/zsh-history-substring-search; \
    git clone --depth=1 --branch "${ZSH_COMPLETIONS_VERSION}" https://github.com/zsh-users/zsh-completions.git /workspace/zsh/plugins/zsh-completions; \
    git clone --depth=1 --branch "${POWERLEVEL10K_VERSION}" https://github.com/romkatv/powerlevel10k.git /workspace/zsh/plugins/powerlevel10k; \
    rm -rf /workspace/zsh/plugins/powerlevel10k/gitstatus; \
    git clone --depth=1 --branch "${GITSTATUS_VERSION}" https://github.com/romkatv/gitstatus.git /workspace/zsh/plugins/powerlevel10k/gitstatus

################################################################################
# Python venv -> /workspace/venv
################################################################################

RUN set -eux; \
    python -m venv --upgrade-deps /workspace/venv; \
    /workspace/venv/bin/python -m pip install --upgrade pip setuptools wheel; \
    /workspace/venv/bin/python -m pip install \
        aiohttp ansible ansible-core ansible-lint awscli bandit beautifulsoup4 black boto3 botocore click cookiecutter csvkit debugpy docker fastapi fake-useragent flake8 flask gunicorn html2text html5lib httpie httpx ipykernel ipython jupyterlab lxml markdownify matplotlib mechanicalsoup mypy numpy opencv-python-headless pandas pdfminer.six pip-tools playwright plotly podman pre-commit psycopg2-binary pydantic pylint pymongo pyquery pyright pytest pytest-cov pytest-xdist python-docx python-lsp-black python-lsp-server readability-lxml redis requests rich ruff ruff-lsp scrapy scikit-learn scipy seaborn selenium setuptools sphinx statsmodels sympy tqdm trafilatura typer uvicorn virtualenv webdriver-manager wheel openpyxl; \
    if [ "${PODMAN_COMPOSE_VERSION}" = "latest" ] || [ -z "${PODMAN_COMPOSE_VERSION}" ]; then /workspace/venv/bin/python -m pip install podman-compose; \
    else /workspace/venv/bin/python -m pip install "podman-compose==${PODMAN_COMPOSE_VERSION}"; fi

################################################################################
# Optional CPU-only PyTorch inside the venv.
################################################################################

RUN set -eux; \
    if [ "${INSTALL_PYTORCH_CPU}" = "1" ]; then \
        /workspace/venv/bin/python -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu || echo "PyTorch CPU install failed; continuing without torch."; \
        TORCH_DIR="$(/workspace/venv/bin/python -c 'import importlib.util, os; spec=importlib.util.find_spec("torch"); print(os.path.dirname(spec.origin) if spec else "")' 2>/dev/null || true)"; \
        if [ -n "${TORCH_DIR}" ] && [ -d "${TORCH_DIR}" ]; then ln -sfn "${TORCH_DIR}" /workspace/libtorch; fi; \
    fi

################################################################################
# ClamAV + StevenBlack hosts -> /workspace/hosts
################################################################################

RUN set -eux; \
    mkdir -p /run/clamav /var/lib/clamav /workspace/hosts; \
    chown -R clamav:clamav /run/clamav /var/lib/clamav 2>/dev/null || true; \
    freshclam --verbose || true; \
    curl -fsSL https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts -o /workspace/hosts/stevenblack-hosts; \
    cp /workspace/hosts/stevenblack-hosts /etc/hosts.stevenblack; \
    mkdir -p /etc/systemd/system/multi-user.target.wants; \
    ln -sf /lib/systemd/system/clamav-daemon.service /etc/systemd/system/multi-user.target.wants/clamav-daemon.service || true; \
    ln -sf /lib/systemd/system/clamav-freshclam.service /etc/systemd/system/multi-user.target.wants/clamav-freshclam.service || true

COPY <<'EOF' /usr/local/bin/update-stevenblack-hosts
#!/usr/bin/env bash
set -euo pipefail
mkdir -p /workspace/hosts
curl -fsSL https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts -o /workspace/hosts/stevenblack-hosts
cp /workspace/hosts/stevenblack-hosts /etc/hosts.stevenblack
if [ "${1:-apply}" = "apply" ]; then cat /etc/hosts.stevenblack > /etc/hosts || true; fi
echo "StevenBlack hosts updated."
EOF
RUN chmod 0755 /usr/local/bin/update-stevenblack-hosts

COPY <<'EOF' /workspace/bin/westmere-check
#!/usr/bin/env bash
set -euo pipefail
if [ ! -r /proc/cpuinfo ]; then echo "Cannot read /proc/cpuinfo"; exit 0; fi
FLAGS="$(grep -m1 '^flags' /proc/cpuinfo || true)"
for f in sse4_2 avx avx2 avx512f avx512dq avx512cd avx512bw avx512vl; do
    if echo "$FLAGS" | grep -qw "$f"; then echo "present: $f"; else echo "missing: $f"; fi
done
EOF

COPY <<'EOF' /workspace/bin/export-offline-cache
#!/usr/bin/env bash
set -euo pipefail
DEST="${1:-/workspace/offline-cache}"
mkdir -p "$DEST"
cp -a /var/cache/apt/archives "$DEST/apt-archives" || true
cp -a /workspace/downloads "$DEST/downloads" || true
cp -a /workspace/npm-cache "$DEST/npm-cache" || true
cp -a /workspace/yarn-cache "$DEST/yarn-cache" || true
cp -a /workspace/pip-cache "$DEST/pip-cache" || true
echo "Exported offline cache to $DEST"
EOF
RUN chmod 0755 /workspace/bin/westmere-check /workspace/bin/export-offline-cache

COPY <<'EOF' /etc/profile.d/dev.sh
export VIRTUAL_ENV=/workspace/venv
export PATH="/workspace/venv/bin:/workspace/node/bin:/workspace/yarn-global/bin:/workspace/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export EDITOR=nvim
export VISUAL=nvim
export GIT_EDITOR=nvim
export TERM=xterm-256color
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export DOCKER_HOST=unix:///var/run/docker.sock
export LIBTORCH_ROOT=/workspace/libtorch
export CMAKE_PREFIX_PATH="/workspace/libtorch:/usr/local:${CMAKE_PREFIX_PATH:-}"
export CHROME_BIN=/usr/bin/chromium
export BROWSER=/usr/bin/chromium
export PIP_CACHE_DIR=/workspace/pip-cache
export NPM_CONFIG_CACHE=/workspace/npm-cache
export YARN_CACHE_FOLDER=/workspace/yarn-cache
EOF

COPY <<'EOF' /home/user/.zshrc
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"; fi
[[ -f /etc/profile.d/dev.sh ]] && source /etc/profile.d/dev.sh
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=100000
export SAVEHIST=100000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS INTERACTIVE_COMMENTS AUTO_CD
fpath=(/workspace/zsh/plugins/zsh-completions/src $fpath)
autoload -Uz compinit
compinit -u
export POWERLEVEL9K_MODE=nerdfont-v3
export POWERLEVEL9K_INSTANT_PROMPT=verbose
export POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
source /workspace/zsh/plugins/powerlevel10k/powerlevel10k.zsh-theme
source /workspace/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=245'
bindkey '^ ' autosuggest-accept || true
source /workspace/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)
source /workspace/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias fd='fd'
alias cat='bat --paging=never'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"'
alias pps='podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"'
function leet() { if command -v toilet >/dev/null 2>&1 && command -v lolcat >/dev/null 2>&1; then toilet -f mono12 -F gay "${@:-LEET}" | lolcat; else echo "${@:-LEET}"; fi }
function dev() { neofetch --ascii_distro debian 2>/dev/null || true; leet "DEV BOX" }
if [[ -o interactive ]]; then
    if command -v neofetch >/dev/null 2>&1; then neofetch --ascii_distro debian 2>/dev/null || true; fi
    if command -v fortune >/dev/null 2>&1 && command -v cowsay >/dev/null 2>&1 && command -v lolcat >/dev/null 2>&1; then fortune | cowsay -f dragon | lolcat 2>/dev/null || true; fi
fi
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
EOF

COPY <<'EOF' /home/user/.p10k.zsh
typeset -g POWERLEVEL9K_MODE=nerdfont-v3
typeset -g POWERLEVEL9K_ICON_PADDING=moderate
typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon dir vcs newline)
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs python node_version docker_context time)
typeset -g POWERLEVEL9K_DIR_BACKGROUND=4
typeset -g POWERLEVEL9K_DIR_FOREGROUND=0
typeset -g POWERLEVEL9K_VCS_CLEAN_BACKGROUND=2
typeset -g POWERLEVEL9K_VCS_MODIFIED_BACKGROUND=3
typeset -g POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND=2
typeset -g POWERLEVEL9K_STATUS_OK=false
typeset -g POWERLEVEL9K_STATUS_ERROR=true
EOF

RUN set -eux; \
    cp /home/user/.zshrc /root/.zshrc; \
    cp /home/user/.p10k.zsh /root/.p10k.zsh; \
    chown -R "${APP_UID}:${APP_GID}" /home/user

COPY <<'EOF' /usr/local/bin/entrypoint.sh
#!/usr/bin/env bash
set -Eeuo pipefail
export PATH="/workspace/venv/bin:/workspace/node/bin:/workspace/yarn-global/bin:/workspace/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
if [ "${1:-}" = "systemd" ] || [ "${1:-}" = "/sbin/init" ] || [ "${1:-}" = "/lib/systemd/systemd" ]; then exec /lib/systemd/systemd; fi
chmod 755 /sbin /usr/sbin /usr/local/sbin 2>/dev/null || true
chmod 4755 /usr/bin/sudo /usr/bin/passwd /usr/bin/su 2>/dev/null || true
chmod 4755 /usr/bin/newuidmap /usr/bin/newgidmap 2>/dev/null || true
if [ ! -e /dev/fuse ]; then mknod /dev/fuse c 10 229 2>/dev/null || true; fi
chmod 666 /dev/fuse 2>/dev/null || true
if [ "$(id -u)" = "0" ]; then
    if [ "${START_CLAMAV:-1}" = "1" ] && command -v freshclam >/dev/null 2>&1; then
        mkdir -p /run/clamav; chown clamav:clamav /run/clamav 2>/dev/null || true
        freshclam --stdout --verbose 2>/dev/null || true
        if command -v clamd >/dev/null 2>&1; then clamd 2>/dev/null || true; fi
        freshclam --daemon >> /var/log/freshclam.log 2>&1 &
    fi
    if [ "${START_CONTAINERD:-1}" = "1" ] && command -v containerd >/dev/null 2>&1; then
        if ! pgrep -x containerd >/dev/null 2>&1; then containerd >> /var/log/containerd.log 2>&1 & sleep 1; fi
    fi
    if [ "${START_DOCKER:-1}" = "1" ] && command -v dockerd >/dev/null 2>&1; then
        if ! pgrep -x dockerd >/dev/null 2>&1; then dockerd ${DOCKERD_FLAGS:-} >> /var/log/dockerd.log 2>&1 & fi
    fi
    if [ "${START_PODMAN_SERVICE:-1}" = "1" ] && command -v podman >/dev/null 2>&1; then
        mkdir -p /run/podman; chmod 755 /run/podman || true
        if ! pgrep -f "podman system service" >/dev/null 2>&1; then podman system service --time=0 unix:///run/podman/podman.sock >> /var/log/podman-service.log 2>&1 & fi
    fi
fi
if [ "$(id -u)" = "0" ] && [ "${APP_USER:-user}" != "root" ] && [ "${DROP_TO_USER:-1}" = "1" ]; then
    exec gosu "${APP_USER}" env HOME="/home/${APP_USER}" USER="${APP_USER}" SHELL=/usr/bin/zsh "$@"
else exec "$@"; fi
EOF
RUN chmod 0755 /usr/local/bin/entrypoint.sh

RUN set -eux; \
    if ! getent group dev >/dev/null 2>&1; then groupadd --system dev; fi; \
    usermod -aG dev "${APP_USER}" || true; \
    chown root:dev /workspace; chmod 2775 /workspace; \
    for d in bin downloads src fonts hosts node nvim venv yarn-global npm-cache yarn-cache pip-cache zsh project; do \
        chown -R root:dev "/workspace/${d}" 2>/dev/null || true; \
        chmod -R g+rwX "/workspace/${d}" 2>/dev/null || true; \
    done; \
    chown -R "${APP_UID}:${APP_GID}" /workspace/project; \
    chmod 755 /sbin /usr/sbin /usr/local/sbin || true; \
    chmod 4755 /usr/bin/sudo /usr/bin/passwd /usr/bin/su || true; \
    chmod 4755 /usr/bin/newuidmap /usr/bin/newgidmap || true; \
    ln -sfn /var/cache/apt/archives /workspace/debs || true; \
    ln -sfn /var/lib/apt/lists /workspace/apt-lists || true

WORKDIR /workspace/project
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nvim"]