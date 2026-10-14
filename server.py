"""Stable source launcher. Personal data and installed runtime are separate."""
import bootstrap
runtime = bootstrap.load_runtime()
if __name__ == '__main__':
    runtime.main()
else:
    import sys
    sys.modules[__name__] = runtime
