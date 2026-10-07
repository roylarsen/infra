#!/usr/bin/env bash
#
# Create a current Ubuntu Server cloud-image template in Proxmox.

set -euo pipefail

readonly VM_ID=9000
readonly VM_NAME="ubuntu-latest"
readonly UBUNTU_STREAM_URL="https://cloud-images.ubuntu.com/releases/streams/v1/com.ubuntu.cloud:released:download.json"
readonly UBUNTU_IMAGE_BASE_URL="https://cloud-images.ubuntu.com/"

NODE=""
IMAGE_STORAGE=""
DISK_STORAGE=""
BRIDGE=""
DISK_SIZE=""
CORES=""
MEMORY=""
INSECURE=0
AUTH_MODE=""
AUTH_HEADERS=()
CSRF_TOKEN=""
TEMP_DIR=""
REMOTE_IMAGE=""
VM_CREATED=0
IMAGE_UPLOADED=0

usage() {
  cat <<'EOF'
Usage:
  create-ubuntu-template.sh --node NODE --image-storage STORAGE \
    --disk-storage STORAGE --bridge BRIDGE --disk-size SIZE \
    --cores COUNT --memory MIB [--insecure]

Required environment variables:
  PVE_API_URL       Proxmox server URL, for example https://pve.example.test:8006;
                    any path (such as /api2/json) is stripped
  PVE_TOKEN_ID      API token ID, for example automation@pve!template-builder
  PVE_TOKEN_SECRET  API token secret

Alternatively, authenticate with a user ticket by setting PVE_USER (for example
root@pam) and PVE_PASSWORD instead of the token variables.

Options:
  --node NODE              Proxmox node that will own the template
  --image-storage STORAGE  Storage with Import content enabled; it temporarily
                           holds the downloaded Ubuntu cloud image
  --disk-storage STORAGE   Target storage for the template disk and cloud-init disk
  --bridge BRIDGE          Network bridge for the template, for example vmbr0
  --disk-size SIZE         Root disk size, for example 20G
  --cores COUNT            Virtual CPU count
  --memory MIB             Memory in MiB
  --insecure               Disable TLS certificate verification (development only)
  --help                   Show this help

The script always creates VM ID 9000 named ubuntu-latest. It fails before
making changes when that ID or name is already in use.
EOF
}

error() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "required command not found: $1"
}

validate_identifier() {
  local label=$1
  local value=$2

  [[ $value =~ ^[A-Za-z0-9._-]+$ ]] ||
    error "$label must contain only letters, digits, dots, underscores, or hyphens"
}

validate_positive_integer() {
  local label=$1
  local value=$2

  [[ $value =~ ^[1-9][0-9]*$ ]] || error "$label must be a positive integer"
}

api() {
  local method=$1
  local path=$2
  local METHOD_HEADERS=()
  shift 2

  if [[ -n $CSRF_TOKEN && $method != GET ]]; then
    METHOD_HEADERS=(--header "CSRFPreventionToken: ${CSRF_TOKEN}")
  fi

  local output
  output=$(curl --fail-with-body --silent --show-error \
    "${CURL_OPTIONS[@]}" \
    --request "$method" \
    "${AUTH_HEADERS[@]}" \
    "${METHOD_HEADERS[@]}" \
    "$@" \
    "${PVE_API_URL}/api2/json${path}") || {
    printf '%s\n' "$output" >&2
    return 1
  }
  printf '%s\n' "$output"
}

wait_for_task() {
  local upid=$1
  local response status exitstatus

  while true; do
    response=$(api GET "/nodes/${NODE}/tasks/${upid}/status")
    status=$(jq -er '.data.status' <<<"$response")
    exitstatus=$(jq -r '.data.exitstatus // empty' <<<"$response")

    if [[ $status == "stopped" ]]; then
      [[ $exitstatus == "OK" ]] || error "Proxmox task failed: $exitstatus"
      return
    fi

    sleep 2
  done
}

run_task() {
  local response upid

  response=$(api "$@")
  upid=$(jq -r '.data | strings' <<<"$response")
  # Some Proxmox endpoints complete synchronously and return no task.
  [[ -z $upid ]] || wait_for_task "$upid"
}

urlencode() {
  jq -nr --arg value "$1" '$value | @uri'
}

delete_uploaded_image() {
  local encoded_volume

  [[ $IMAGE_UPLOADED -eq 1 ]] || return
  encoded_volume=$(urlencode "import/${REMOTE_IMAGE}")
  if ! api DELETE "/nodes/${NODE}/storage/${IMAGE_STORAGE}/content/${encoded_volume}" >/dev/null; then
    printf 'warning: could not delete temporary Proxmox image %s\n' "$REMOTE_IMAGE" >&2
  fi
  IMAGE_UPLOADED=0
}

cleanup() {
  local exit_code=$?

  set +e
  [[ -n $TEMP_DIR ]] && rm -rf -- "$TEMP_DIR"
  delete_uploaded_image

  if [[ $exit_code -ne 0 && $VM_CREATED -eq 1 ]]; then
    printf 'cleaning up partially created VM %s\n' "$VM_ID" >&2
    api DELETE "/nodes/${NODE}/qemu/${VM_ID}" >/dev/null ||
      printf 'warning: could not delete partially created VM %s\n' "$VM_ID" >&2
  fi

  trap - EXIT
  exit "$exit_code"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --node)
      NODE=${2:-}
      shift 2
      ;;
    --image-storage)
      IMAGE_STORAGE=${2:-}
      shift 2
      ;;
    --disk-storage)
      DISK_STORAGE=${2:-}
      shift 2
      ;;
    --bridge)
      BRIDGE=${2:-}
      shift 2
      ;;
    --disk-size)
      DISK_SIZE=${2:-}
      shift 2
      ;;
    --cores)
      CORES=${2:-}
      shift 2
      ;;
    --memory)
      MEMORY=${2:-}
      shift 2
      ;;
    --insecure)
      INSECURE=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      error "unknown option: $1 (use --help for usage)"
      ;;
  esac
done

for command in curl jq; do
  require_command "$command"
done

[[ -n ${PVE_API_URL:-} ]] || error "PVE_API_URL is required"
if [[ -n ${PVE_TOKEN_ID:-} && -n ${PVE_TOKEN_SECRET:-} ]]; then
  AUTH_MODE=token
elif [[ -n ${PVE_USER:-} && -n ${PVE_PASSWORD:-} ]]; then
  AUTH_MODE=ticket
else
  error "set PVE_TOKEN_ID and PVE_TOKEN_SECRET, or PVE_USER and PVE_PASSWORD"
fi
[[ $PVE_API_URL =~ ^(https://[^/?#]+) ]] ||
  error "PVE_API_URL must be an HTTPS URL"
PVE_API_URL=${BASH_REMATCH[1]}

for option in NODE IMAGE_STORAGE DISK_STORAGE BRIDGE; do
  [[ -n ${!option} ]] || error "--${option,,} is required"
  validate_identifier "--${option,,}" "${!option}"
done

[[ $DISK_SIZE =~ ^[1-9][0-9]*[KMGT]?$ ]] ||
  error "--disk-size must be a positive size such as 20G"
validate_positive_integer "--cores" "$CORES"
validate_positive_integer "--memory" "$MEMORY"

CURL_OPTIONS=()
if [[ $INSECURE -eq 1 ]]; then
  CURL_OPTIONS+=(--insecure)
  printf 'warning: TLS certificate verification is disabled\n' >&2
fi

trap cleanup EXIT

if [[ $AUTH_MODE == token ]]; then
  AUTH_HEADERS=(--header "Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}")
else
  ticket_response=$(curl --fail --silent --show-error "${CURL_OPTIONS[@]}" \
    --data-urlencode "username=${PVE_USER}" \
    --data-urlencode "password=${PVE_PASSWORD}" \
    "${PVE_API_URL}/api2/json/access/ticket") || error "Proxmox authentication failed"
  AUTH_HEADERS=(--header "Cookie: PVEAuthCookie=$(jq -er '.data.ticket' <<<"$ticket_response")")
  CSRF_TOKEN=$(jq -er '.data.CSRFPreventionToken' <<<"$ticket_response")
fi

printf 'Checking Proxmox connectivity and existing VM resources...\n'
resources=$(api GET "/cluster/resources?type=vm")
jq -e --argjson vmid "$VM_ID" '.data[] | select(.vmid == $vmid)' \
  <<<"$resources" >/dev/null &&
  error "VM ID ${VM_ID} is already in use"
jq -e --arg name "$VM_NAME" '.data[] | select(.name == $name)' \
  <<<"$resources" >/dev/null &&
  error "a VM or template named ${VM_NAME} already exists"

storage_info=$(api GET "/nodes/${NODE}/storage?content=import") ||
  error "could not list storages on node ${NODE}"
jq -e --arg storage "$IMAGE_STORAGE" '.data[] | select(.storage == $storage)' \
  <<<"$storage_info" >/dev/null ||
  error "image storage ${IMAGE_STORAGE} is unavailable or lacks Import content on node ${NODE}"
api GET "/nodes/${NODE}/storage/${DISK_STORAGE}/status" >/dev/null ||
  error "disk storage ${DISK_STORAGE} is unavailable on node ${NODE}"

printf 'Resolving the latest Ubuntu Server cloud image...\n'
stream=$(curl --fail --silent --show-error --location "$UBUNTU_STREAM_URL")
image_metadata=$(jq -er '
  [
    .products
    | to_entries[]
    | select(
        (.key | test("^com\\.ubuntu\\.cloud:server:[0-9]+\\.[0-9]+:amd64$"))
        and .value.supported
      )
    | {
        version: .value.version,
        image: (
          .value.versions
          | to_entries
          | max_by(.key)
          | .value.items["disk1.img"]
        )
      }
    | select(.image.path != null)
  ]
  | max_by(.version | split(".") | map(tonumber))
' <<<"$stream") || error "could not find a supported Ubuntu Server amd64 cloud image"
IMAGE_VERSION=$(jq -er '.version' <<<"$image_metadata")
IMAGE_PATH=$(jq -er '.image.path' <<<"$image_metadata")
SOURCE_IMAGE=${IMAGE_PATH##*/}
[[ $SOURCE_IMAGE =~ ^ubuntu-[0-9.]+-server-cloudimg-amd64\.img$ ]] ||
  error "unexpected Ubuntu cloud image filename: ${SOURCE_IMAGE}"
REMOTE_IMAGE="${SOURCE_IMAGE%.img}.qcow2"
IMAGE_URL="${UBUNTU_IMAGE_BASE_URL}${IMAGE_PATH}"

TEMP_DIR=$(mktemp -d)
LOCAL_IMAGE="${TEMP_DIR}/${REMOTE_IMAGE}"  # Canonical .img files are qcow2
printf 'Downloading Ubuntu Server %s...\n' "$IMAGE_VERSION"
curl --fail --silent --show-error --location \
  --output "$LOCAL_IMAGE" "$IMAGE_URL"

printf 'Creating VM %s (%s)...\n' "$VM_ID" "$VM_NAME"
run_task POST "/nodes/${NODE}/qemu" \
  --data-urlencode "vmid=${VM_ID}" \
  --data-urlencode "name=${VM_NAME}" \
  --data-urlencode "ostype=l26" \
  --data-urlencode "cores=${CORES}" \
  --data-urlencode "memory=${MEMORY}" \
  --data-urlencode "net0=virtio,bridge=${BRIDGE}" \
  --data-urlencode "scsihw=virtio-scsi-pci" \
  --data-urlencode "agent=1"
VM_CREATED=1

printf 'Uploading the cloud image to %s...\n' "$IMAGE_STORAGE"
run_task POST "/nodes/${NODE}/storage/${IMAGE_STORAGE}/upload" \
  --form "content=import" \
  --form "filename=@${LOCAL_IMAGE}"
IMAGE_UPLOADED=1

printf 'Importing the cloud image into %s...\n' "$DISK_STORAGE"
run_task PUT "/nodes/${NODE}/qemu/${VM_ID}/config" \
  --data-urlencode "scsi0=${DISK_STORAGE}:0,import-from=${IMAGE_STORAGE}:import/${REMOTE_IMAGE}" \
  --data-urlencode "boot=order=scsi0"
delete_uploaded_image

printf 'Resizing the template disk to %s...\n' "$DISK_SIZE"
run_task PUT "/nodes/${NODE}/qemu/${VM_ID}/resize" \
  --data-urlencode "disk=scsi0" \
  --data-urlencode "size=${DISK_SIZE}"

printf 'Configuring cloud-init and template metadata...\n'
run_task PUT "/nodes/${NODE}/qemu/${VM_ID}/config" \
  --data-urlencode "ide2=${DISK_STORAGE}:cloudinit" \
  --data-urlencode "ipconfig0=ip=dhcp" \
  --data-urlencode "serial0=socket" \
  --data-urlencode "vga=serial0" \
  --data-urlencode "description=Ubuntu Server ${IMAGE_VERSION}"

printf 'Converting VM %s to a template...\n' "$VM_ID"
run_task POST "/nodes/${NODE}/qemu/${VM_ID}/template"
VM_CREATED=0

printf 'Created template %s (VM ID %s, Ubuntu Server %s).\n' \
  "$VM_NAME" "$VM_ID" "$IMAGE_VERSION"
