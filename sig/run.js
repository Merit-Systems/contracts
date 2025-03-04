const { ethers } = require("ethers");

// Replace this with your own private key (for testing only).
// DO NOT use private keys that hold real funds.
const privateKey =
  "0x4646464646464646464646464646464646464646464646464646464646464646";

console.log(privateKey);

// Domain parameters for EIP-712
const managerAddress = "0x1000000000000000000000000000000000000013"; // Replace with your contract address
const delegateAddress = "0x1000000000000000000000000000000000000014";
const chainId = 31337; // Mainnet is 1, but you can use another chainId as needed

// Create a signer from the private key
const wallet = new ethers.Wallet(privateKey);

// Define the EIP-712 domain
const domain = {
  name: "Fortis wstETH",
  version: "1",
  chainId: chainId,
  verifyingContract: managerAddress,
};

// Define the types
const types = {
  Unlock: [
    { name: "owner", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "delegate", type: "address" },
  ],
};

// Define the values being signed
const value = {
  owner: wallet.address,
  nonce: 0, // Replace with the actual nonce for the user
  deadline: Math.floor(Date.now() / 1000) + 3600, // 1 hour from now
  delegate: delegateAddress,
};

async function main() {
  // Sign the typed data
  console.log(value);
  const signature = await wallet._signTypedData(domain, types, value);
  const { v, r, s } = ethers.utils.splitSignature(signature);

  console.log("User Address:", wallet.address);
  console.log("Signature:", signature);
  console.log("v:", v);
  console.log("r:", r);
  console.log("s:", s);
}

main().catch(console.error);
