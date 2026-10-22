JavaScript
const hre = require("hardhat");
async function main() {
  const VestingFactory = await hre.ethers.getContractFactory("ChronosVestingVault");
  const vault = await VestingFactory.deploy();
  await vault.deployed();
  console.log("-> Chronos Vesting Vault active at:", vault.address);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
