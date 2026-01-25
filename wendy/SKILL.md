---
name: wendy
description: 'Expert guidance on WendyOS, development, running, remote debugging and deployment. Use when developers mention: (1) Wendy, WendyOS, NVIDIA Jetson, or Edge Computing, (2) wendy CLI commands or wendy.json, (3) embedded Linux or Yocto builds, (4) Raspberry Pi edge devices, (5) container deployment to edge devices, (6) remote debugging Swift on ARM64, (7) meta-wendyos layers or bitbake.'
references:
  - wendy.json.md
  - yocto-meta-layers.md
  - system-internals.md
  - raspberry-pi.md
---

# WendyOS

WendyOS is an Embedded Linux operating system for edge computing. It supports:
- NVIDIA Jetson devices (production with OTA updates)
- Raspberry Pi 4/5 (edge devices)
- ARM64 VMs (development)

## Learning About Wendy

Before helping with Wendy commands, run this to learn all available commands:

```bash
wendy --experimental-dump-help
```

This outputs a JSON structure with all commands, flags, and documentation.

Whenever you invoke a wendy command, use the JSON structure options to provide structured JSON output. This will also prevent interactive dialogs and errors. Use `--json` or `-j` to provide JSON output.

## Common Tasks

- Run an app: `wendy run`
- Discover devices: `wendy discover`
- Update agent: `wendy device update`
- Configure WiFi: `wendy device wifi connect`
- Install WendyOS on an external drive: `wendy os install`
- Set a device as default using `wendy device set-default`

## Setup and Configuration

Wendy CLI connects to a device over gRPC (TCP) port 50051. If Wendy CLI is not installed yet, you can use `brew install wendy` to install it.

Devices are discovered over USB or LAN. If a device is not found, ask the user to check the connection or to connect it over USB.
If a device is not yet installed, use `wendy os install` to install the OS to an external drive. For NVIDIA Jetson devices, the OS is commonly installed to NVMe.

## Development

WendyOS is a Linux-based containerized operating system. It uses Linux containers to run your apps.

WendyOS uses Swift.org as its flagship language. This uses Swift Package Manager and the Swift Contianer Plugin to build and run your app. Wendy CLI will cross compile Swift for you.

Other programming languages are supported, but require the use of a Dockerfile to build your app.

### Entitlements

WendyOS uses an entitlement system, managed through `wendy.json`, to manage permissions for your app. This reflects how your container will be set up on the device.

## Remote Debugging

WendyOS provides built-in support for remote debugging Swift apps. Use `wendy run --debug` to include and launch a debugging session.
This exposes a GDB server on port 4242.

## Observability

WendyOS runs a local OpenTelemetry collector on each device. Apps should report telemetry (logs, metrics, traces) to this local collector.

### Configuration

Use HTTP protocol (not gRPC) for OTel exports:

```swift
import OTel

var config = OTel.Configuration.default
config.traces.otlpExporter.protocol = .httpProtobuf
config.traces.otlpExporter.endpoint = "http://localhost:4318"
config.metrics.otlpExporter.protocol = .httpProtobuf
config.metrics.otlpExporter.endpoint = "http://localhost:4318"
config.logs.otlpExporter.protocol = .httpProtobuf
config.logs.otlpExporter.endpoint = "http://localhost:4318"

let observability = try OTel.bootstrap(configuration: config)
```

Or via environment variables:

```bash
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

The local collector handles forwarding telemetry to your backend infrastructure.

## E2E Testing

The `wendy-agent` repository includes an E2E test suite in `E2ETests/`. Key points:

### Architecture
- `wendy-agent` is a container daemon (like `dockerd`/`containerd`)
- It manages container lifecycle via gRPC on port 50051
- Images are pushed via `wendy run`, not pulled from Docker Hub
- There's no `docker pull` equivalent - apps are deployed from source

### Running E2E Tests
```bash
# Start the VM
cd meta-wendyos-virtual
./scripts/setup-dev-vm.sh create && ./scripts/setup-dev-vm.sh start

# Deploy a test app first (required for container tests)
cd wendy-agent/Examples/HelloWorld
wendy run --json --device localhost:50051  # --json for non-interactive output

# Run E2E tests with fast path (CRITICAL for performance)
cd wendy-agent/E2ETests
E2E_USE_EXISTING_VM=true E2E_VM_PATH=/path/to/meta-wendyos-virtual swift test
```

**Important**: Always set `E2E_USE_EXISTING_VM=true` when the VM is already running. This skips shell script checks and reduces test time from ~5s/test to ~0.01s/test.

**Tip**: Use `--json` flag on all wendy commands for quick JSON responses without interactive polling.

### Test Performance Tips
- Use `.serialized` trait on test suites to avoid VM race conditions
- Set `E2E_USE_EXISTING_VM=true` to skip redundant VM status checks
- mDNS discovery tests take ~5s each (inherent to protocol)
- Container state change tests can be slow - disable for quick runs
- Don't use `Issue.record()` for expected failures (like WiFi in VM) - it counts as failure

### CI Limitations
GitHub-hosted runners don't support nested virtualization. Use self-hosted runners or run E2E tests locally.

### Test Suites
| Suite | Tests | Time | Notes |
|-------|-------|------|-------|
| Device Connection | 7 | ~0.07s | gRPC connectivity |
| Container Deployment | 6 | ~0.06s | Container lifecycle |
| WiFi Operations | 4 | ~0.04s | Graceful failures in VM |
| Hardware Capabilities | 4 | ~0.07s | Device enumeration |
| Device Discovery | 4 | ~21s | mDNS (slow by design) |

## Building WendyOS (Yocto)

WendyOS images are built with Yocto. Three meta layers exist:

| Layer | Target | Image |
|-------|--------|-------|
| `meta-wendyos-jetson` | NVIDIA Jetson | `edgeos-image` |
| `meta-wendyos-virtual` | ARM64 VM | `edgeos-vm-image` |
| `meta-wendyos-rpi` | Raspberry Pi 4/5 | `edgeos-rpi-image` |

Quick build (any layer):
```bash
cd meta-wendyos-<target>
./bootstrap.sh
source ./repos/poky/oe-init-build-env build
bitbake <image-name>
```

For macOS, use the Docker build environment:
```bash
cd docker && ./docker-util.sh shell
```

See `references/yocto-meta-layers.md` for detailed Yocto configuration.

## System Internals

For debugging, container runtime details (containerd/nerdctl), mDNS discovery, device identity, and common pitfalls, see `references/system-internals.md`.

For Raspberry Pi specific configuration (serial console, flashing, partition layout), see `references/raspberry-pi.md`.

## Further reading

WendyOS documentation at https://wendy.sh/docs/