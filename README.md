## 📦 Installation

AIBOT provides automated installers for Linux, macOS, and Windows.

The installer automatically detects the environment and downloads the correct
release binary.

### 🪟 Windows + Docker Desktop

**Windows installations use Docker Desktop as the runtime environment.**

The installer detects the Docker Desktop Linux architecture and downloads the
corresponding Linux AIBOT binary.

```text
Windows Host
     │
     ▼
Docker Desktop
     │
     ▼
Linux Container
     │
     ├── linux/amd64
     │       ↓
     │   adbot-linux-amd64
     │
     └── linux/arm64
             ↓
         adbot-linux-arm64
```

````

Run the installer from PowerShell:

```powershell
irm https://raw.githubusercontent.com/sorabhyadavpalothar/adbot/v3.1.3/scripts/install.ps1 | iex
```

Or download it first:

```powershell
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/sorabhyadavpalothar/adbot/v3.1.3/scripts/install.ps1" `
  -OutFile "install.ps1"

Set-ExecutionPolicy -Scope Process Bypass

.\install.ps1
```

The installer will:

1. Detect Windows architecture.
2. Detect Docker Desktop.
3. Detect the Docker Linux server architecture.
4. Select `adbot-linux-amd64` or `adbot-linux-arm64`.
5. Download the binary from the selected release.
6. Download `SHA256SUMS`.
7. Verify the binary checksum.
8. Create `dist\`.
9. Install the binary as:

```text
dist\adbot
```

10. Ask for the required configuration.
11. Generate `.env`.
12. Build and start Docker Compose.

---

### 🐧 Linux / Docker

Linux systems can use the shell installer:

```bash
curl -fsSL https://raw.githubusercontent.com/sorabhyadavpalothar/adbot/v3.1.3/scripts/install.sh | bash
```

Or:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/sorabhyadavpalothar/adbot/v3.1.3/scripts/install.sh \
  -o install.sh

chmod +x install.sh

./install.sh
```

If Docker is available, the installer uses the Docker server platform as the
runtime target.

---

### 🍎 macOS / Docker

macOS systems can use:

```bash
curl -fsSL https://raw.githubusercontent.com/sorabhyadavpalothar/adbot/v3.1.3/scripts/install.sh | bash
```

The installer supports:

- Apple Silicon (`arm64`)
- Intel (`amd64`)

When Docker Desktop is available, the Docker Linux platform is used for the
container binary.

---

## 🐳 Docker Runtime

AIBOT runs inside a Linux Docker container.

The Docker image uses:

```dockerfile
FROM debian:trixie-slim

WORKDIR /app

COPY ./dist/adbot ./dist/adbot

COPY .env ./.env

RUN chmod +x ./dist/adbot

ENTRYPOINT ["./dist/adbot"]
```

Therefore the `dist/adbot` binary must be a Linux executable when building
the Docker image.

### Windows example

```text
Windows AMD64
      ↓
Docker Desktop
      ↓
Linux AMD64
      ↓
adbot-linux-amd64
      ↓
dist/adbot
      ↓
Dockerfile
      ↓
AIBOT
```

### ARM64 example

```text
Windows ARM64
      ↓
Docker Desktop
      ↓
Linux ARM64
      ↓
adbot-linux-arm64
      ↓
dist/adbot
      ↓
Dockerfile
      ↓
AIBOT
```

---

## ⚙️ Configuration

The installer asks for:

```text
PostgreSQL database name
PostgreSQL username
PostgreSQL password

Telegram bot token

Admin Telegram ID(s)

Encryption Key

1) Auto generate
2) Manual
```

The installer creates:

```text
.env
```

and uses it with Docker Compose.

---

## 🚀 Start

After installation:

```bash
docker compose up -d --build
```

Check containers:

```bash
docker compose ps
```

View AIBOT logs:

```bash
docker compose logs -f bot
```

---

## 📥 Manual Downloads

Pre-built executables are available from the
[GitHub Releases](https://github.com/sorabhyadavpalothar/adbot/releases).

Available builds:

```text
adbot-linux-amd64
adbot-linux-arm64

adbot-darwin-amd64
adbot-darwin-arm64

adbot-windows-amd64.exe
adbot-windows-arm64.exe

SHA256SUMS
```

For Docker installations, use the Linux binaries:

```text
adbot-linux-amd64
adbot-linux-arm64
```

The Windows binaries are intended for running AIBOT directly on Windows,
not for the Linux Docker container.

---

## 🔐 SHA256 Verification

Every release contains:

```text
SHA256SUMS
```

The installers automatically verify the downloaded binary before installation.

Manual verification on Windows:

```powershell
Get-FileHash .\adbot-windows-amd64.exe -Algorithm SHA256
```

Linux:

```bash
sha256sum adbot-linux-amd64
```

macOS:

```bash
shasum -a 256 adbot-darwin-arm64
```

---

## 🛠️ Installer Files

```text
scripts/
├── install.sh
└── install.ps1
```

### Windows

```text
scripts/install.ps1
```

Designed for:

```text
Windows
   ↓
Docker Desktop
   ↓
Linux container
```

### Linux / macOS

```text
scripts/install.sh
```

Supports native Linux/macOS environments and Docker-based deployments.

---

## 🔒 Security

Never commit:

```text
.env
```

to Git.

The `.env` file contains sensitive values such as:

- Telegram Bot Token
- PostgreSQL Password
- Encryption Key

Add this to `.gitignore`:

```gitignore
.env
```

---

## 📝 License

Distributed under the MIT License.
````
