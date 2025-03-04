const { ethers } = require("ethers");

// Replace this with your own private key (for testing only).
// DO NOT use private keys that hold real funds.
const privateKey =
  "0x4646464646464646464646464646464646464646464646464646464646464646";

// Domain parameters for EIP-712
const verifyingContract = "0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f"; // Replace with your contract address
const chainId = 31337; // Mainnet is 1, but you can use another chainId as needed

// Create a signer from the private key
const wallet = new ethers.Wallet(privateKey);

// get the public key
const publicKey = ethers.utils.computeAddress(privateKey);
console.log("publicKey", publicKey);

// Define the EIP-712 domain
const domain = {
  name: "SplitWithLockup",
  version: "1",
  chainId: chainId,
  verifyingContract: verifyingContract,
};

// Define the types
const types = {
  Claim: [
    { name: "recipient", type: "address" },
    { name: "status", type: "bool" },
    { name: "nonce", type: "uint256" },
  ],
};

// Define the values being signed
const value = {
  recipient: publicKey,
  status: true,
  nonce: 0, // Replace with the actual nonce for the user
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
