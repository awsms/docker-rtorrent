variable "DEFAULT_TAG" {
  default = "docker-rtorrent:local"
}

variable "LIBTORRENT_VERSION" {
  default = "0.16.13"
}

variable "RTORRENT_VERSION" {
  default = "0.16.13"
}

// Special target: https://github.com/docker/metadata-action#bake-definition
target "docker-metadata-action" {
  tags = ["${DEFAULT_TAG}"]
}

// Default target if none specified
group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    LIBTORRENT_VERSION = "${LIBTORRENT_VERSION}"
    RTORRENT_VERSION   = "${RTORRENT_VERSION}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm/v6",
    "linux/arm/v7",
    "linux/arm64"
  ]
}
