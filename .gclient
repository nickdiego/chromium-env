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
      "rbe_instance": "projects/rbe-chromium-untrusted/instances/default_instance",
    },
  },
]
target_os=["chromeos"]
