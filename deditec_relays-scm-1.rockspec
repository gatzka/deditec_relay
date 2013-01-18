package = "deditec_relays"
version = "1.0"

source = {
  url = "http://lualibusb1.googlecode.com/files/lualibusb1-1.0.0.tar.gz"
}

description = {
  summary = "binding for Deditec relays",
  homepage = "http://github.com/gatzka/deditec_relay"
  license = "MIT/X11"
}

dependencies = {
  "lua >= 5.1"
}

external_dependencies = {
  LIBUSB = {
    header = "libusb-1.0/libusb.h"
  }
}

supported_platforms = { "linux", "freebsd", "macosx" }

}

