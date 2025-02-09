require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config()
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.24",
  networks:{
    flow:{
      accounts:[process.env.PRIVATE_KEYS],
      url:process.env.FLOW_RPC
    }
  }
};
