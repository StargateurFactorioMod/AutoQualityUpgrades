local watch_types = {
  "accumumator",
  "agricultural-tower",
  "asteroid-collector", -- no idea if there is network in space
  "assembling-machine",
  "beacon",
  "boiler",
  "burner-generator",
  "cargo-bay",
  "cargo-landing-pad",
  "container",
  "electric-turret",
  "furnace",
  "fusion-generator",
  "fusion-reactor",
  "generator",
  "inserter",
  "lab",
  "logistic-container",
  "mining-drill",
  "offshore-pump",
  "pump",
  "radar",
  "reactor",
  "roboport",
  "rocket-silo",
  "solar-panel",
  "storage-tank",
  "thruster", -- no idea if there is network in space
  "turret",
  "valve",
}

data:extend({
  {
      type = "int-setting",
      name = "aqu-ticks-by-cycle",
      setting_type = "runtime-global",
      default_value = 3600,
      minimum_value = 1,
  },
  {
    type = "string-setting",
    name = "aqu-watch-types",
    setting_type = "runtime-global",
    default_value = table.concat(watch_types, ", "),
    allow_blank = true,
  }
})