import argparse
from .cli import run as cli_run, CnWallCLI

def main():
    p = argparse.ArgumentParser()
    p.add_argument("command", nargs="?")
    args = p.parse_args()
    if not args.command:
        cli_run()
        return
    c = CnWallCLI()
    getattr(c, f"do_{args.command}")("")

if __name__ == "__main__":
    main()

