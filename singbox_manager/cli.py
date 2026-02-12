import argparse
import sys
import logging

try:
    from .config import load_config
    from .manager import Manager
except ImportError as e:
    print(f"Error: Failed to import required modules. {e}")
    print("Please install dependencies using: pip install -r singbox_manager/requirements.txt")
    sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="SingBox Multi-Node Manager")
    parser.add_argument("--config", "-c", default="./singbox_manager/inventory.yaml", help="Path to inventory configuration file")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Deploy command
    deploy_parser = subparsers.add_parser("deploy", help="Deploy configuration to nodes")
    deploy_parser.add_argument("--node", "-n", help="Target specific node by name (default: all)")
    
    # List nodes command
    list_parser = subparsers.add_parser("list", help="List configured nodes")

    args = parser.parse_args()

    try:
        inventory = load_config(args.config)
    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error loading configuration: {e}")
        sys.exit(1)

    manager = Manager(inventory)

    if args.command == "deploy":
        manager.deploy(args.node)
    elif args.command == "list":
        print(f"{'Name':<20} {'Host':<15} {'User':<10} {'Auth Type':<10}")
        print("-" * 60)
        for node in inventory.nodes:
            print(f"{node.name:<20} {node.host:<15} {node.user:<10} {node.auth_type:<10}")
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
