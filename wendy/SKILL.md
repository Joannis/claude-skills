---
name: wendy
description: 'Expert guidance on WendyOS, development, running, remote debugging and deployment. Use when developers mention: (1) Wendy,WendyOS, NVIDIA Jetson or Edge Computing.'
---

# WendyOS

WendyOS is an Embedded Linux operating system for NVIDIA Jetson devices. It is primarily used for Edge Computing.

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

## Further reading

WendyOS documentation at https://wendy.sh/docs/