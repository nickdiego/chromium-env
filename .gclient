solutions = [
  {
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "name": "src",
    "deps_file": ".DEPS.git",
    "custom_deps": {},
    "custom_vars": {
      "checkout_nacl": True,
      "cros_boards": "amd64-generic",
      "checkout_lacros_sdk": True,
    },
  },
]
target_os=["chromeos"]
