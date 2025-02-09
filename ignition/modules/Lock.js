const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");


module.exports = buildModule("DysteraModule", (m) => {

  const lock = m.contract("Dystera");

  return { lock };
});
