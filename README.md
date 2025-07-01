```
███╗   ███╗███████╗██████╗ ██╗████████╗
████╗ ████║██╔════╝██╔══██╗██║╚══██╔══╝
██╔████╔██║█████╗  ██████╔╝██║   ██║
██║╚██╔╝██║██╔══╝  ██╔══██╗██║   ██║
██║ ╚═╝ ██║███████╗██║  ██║██║   ██║
╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝   ╚═╝
                                                                
 ███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗███████╗
 ██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║██╔════╝
 ███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║███████╗
 ╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
 ███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║███████║
 ╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

```

# Merit Escrow

Escrow contract for secure token distributions with signature-based claims.

## Core Contract

[`Escrow.sol`](src/Escrow.sol) - The main escrow contract supporting both repository-managed and direct distributions.

## Building

```bash
forge build
```

## Testing

```bash
forge test
```

## Audits

Multiple security audits have been conducted. See the [audits directory](audits/) for all audit reports.

## Deployment

The Escrow Contract lives at [0x000000007bca2DC8F121B49457c726B51Adb667a](https://basescan.org/address/0x000000007bca2dc8f121b49457c726b51adb667a) on Base.