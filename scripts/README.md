# scripts

## create-ubuntu-template.sh

Downloads the newest Ubuntu Server cloud image (resolved via Canonical's image-stream JSON) and creates a Proxmox template VM `ubuntu-latest` with ID `9000`. The Ubuntu version goes in the VM description. The script fails if VM 9000 already exists.

### Auth (environment)

- `PVE_API_URL`, for example `https://technodrome.xhousebreakx.org:8006` (any path is stripped)
- Either `PVE_TOKEN_ID` + `PVE_TOKEN_SECRET`, or `PVE_USER` + `PVE_PASSWORD`

### Options

`--node --image-storage --disk-storage --bridge --disk-size --cores --memory [--insecure]`

The image storage must have the `import` content type enabled.

### Example

```sh
export PVE_API_URL=... PVE_USER=root@pam PVE_PASSWORD=...
./create-ubuntu-template.sh --node technodrome
```
