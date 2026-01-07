local util = require("util")

local aqu = {}

aqu.debug = false

-- Types for storage so the language server warns on unknown fields like `storage.toto`
---@class (exact) Storage
---@field entities LuaEntity[]
---@field current_index integer
---@field qualities LuaQualityPrototype[]
---@field entities_by_run int
---@field networks table<int, table<string, int>>

---@type Storage
storage = storage

-- doesn't work
---@diagnostic disable-next-line: unknown-cast-variable
---@cast storage Storage

---@param entity LuaEntity
function aqu.process_entity_to_be_upgraded(entity)
  local target, quality = entity.get_upgrade_target()
  if not target or not quality then
    return
  end

  local networks = entity.surface.find_logistic_networks_by_construction_area(entity.position, entity.force)
  if #networks == 0 then
    return
  end

  if entity.is_registered_for_upgrade() then
    for _, network in ipairs(networks) do
      for _, item in ipairs(target.items_to_place_this) do
--        local n = math.max(1, aqu.get_used_item_by_network(network, item.name, quality.name))
        if network.can_satisfy_request({ name = item.name, quality = quality }, 1, true) then
          return
        end
      end
    end
    -- if this the same entity prototypes we don't want cancel upgrade that change entity nature
    -- so we just try to find any quality that will build this upgrade
    if target.name ~= entity.name then
      aqu.try_upgrade_entity(entity, networks, target, true)
    else
      entity.cancel_upgrade(entity.force)
    end
  end
end

---@param network LuaLogisticNetwork
---@param item_name string
---@param quality_name string
function aqu.add_used_item_to_network(network, item_name, quality_name)
  local id = network.network_id
  if not storage.networks[id] then
    storage.networks[id] = {}
  end

  local k = item_name .. (quality_name or "normal")
  if not storage.networks[id][k] then
    storage.networks[id][k] = 1
  else
    storage.networks[id][k] = storage.networks[id][k] + 1
  end
end

---@param network LuaLogisticNetwork
---@param item_name string
---@param quality_name string
---@return int
function aqu.get_used_item_by_network(network, item_name, quality_name)
  local id = network.network_id

  if storage.networks[id] then
    local k = item_name .. (quality_name or "normal")
    if storage.networks[id][k] then
      return storage.networks[id][k]
    end
  end

  return 0
end

function aqu.reduce_item_used()
  for _, items in pairs(storage.networks) do
    for name, _ in pairs(items) do
      if items[name] > 1 then
        items[name] = math.floor(items[name] / 2)
      else
        items[name] = nil
      end
    end
  end
end

---@param entity LuaEntity
---@param networks LuaLogisticNetwork[]
---@param prototype LuaEntityPrototype
---@param allow_downgrade boolean
function aqu.try_upgrade_entity(entity, networks, prototype, allow_downgrade)
  for i = #storage.qualities, 1, -1 do
    local quality = storage.qualities[i]
    if not allow_downgrade and quality.name == entity.quality.name then
      return
    end
    for _, item in ipairs(prototype.items_to_place_this) do
      for _, network in ipairs(networks) do
        local n = aqu.get_used_item_by_network(network, item.name, quality.name) + 1
        if network.can_satisfy_request({ name = item.name, quality = quality }, n, true) then
          entity.order_upgrade { target = { name = prototypes.item[item.name].place_result, quality = quality }, force = entity.force }
          aqu.add_used_item_to_network(network, item.name, quality.name)
          return
        end
      end
    end
  end
end

---@param id defines.inventory
---@return boolean
function aqu.is_a_module_inventory(id)
  local modules = {
    [defines.inventory.lab_modules] = true,
    [defines.inventory.mining_drill_modules] = true,
    [defines.inventory.beacon_modules] = true,
    [defines.inventory.crafter_modules] = true,
    [defines.inventory.crafter_modules] = true,
    [defines.inventory.crafter_modules] = true,
  }
  if modules[id] then
    return modules[id]
  else
    return false
  end
end

---@param plans BlueprintInsertPlan[]
---@return boolean
function aqu.check_plan(plans)
  if not plans or not plans[1] or #plans ~= 1
      or not plans[1].items.in_inventory or not plans[1].items.in_inventory[1] or #plans[1].items.in_inventory ~= 1 then
    return false
  end
  if not aqu.is_a_module_inventory(plans[1].items.in_inventory[1].inventory) then
    return false
  end

  return true
end



---@param item_request_proxy LuaEntity
---@param networks LuaLogisticNetwork[]
function aqu.handle_cancel_request(item_request_proxy, networks)
  local insert_plan = item_request_proxy.insert_plan
  local removal_plan = item_request_proxy.removal_plan
  if item_request_proxy.is_registered_for_construction() then
    if aqu.check_plan(insert_plan) and aqu.check_plan(removal_plan) then
      if insert_plan[1].id.name == removal_plan[1].id.name then
        local module = insert_plan[1].id
        for _, network in ipairs(networks) do
--          local n = math.max(1, aqu.get_used_item_by_network(network, module.name, module.quality))
          if network.can_satisfy_request({ name = module.name, quality = module.quality }, 1, true) then
            return
          end
        end
        item_request_proxy.destroy()
      end
    end
  end
end

-- ---@param entity LuaEntity
-- ---@return defines.inventory.beacon_modules|defines.inventory.crafter_modules|defines.inventory.lab_modules|defines.inventory.mining_drill_modules
-- function aqu.get_module_inventory_type(entity)
--   local modules = {
--     ["lab"] = defines.inventory.lab_modules,
--     ["mining-drill"] = defines.inventory.mining_drill_modules,
--     ["beacon"] = defines.inventory.beacon_modules,
--     ["rocket-silo"] = defines.inventory.crafter_modules,
--     ["assembling-machine"] = defines.inventory.crafter_modules,
--     ["furnace"] = defines.inventory.crafter_modules,
--   }

--   return modules[entity.type]
-- end

---@param entity LuaEntity
---@param module LuaItemStack
---@param stack int
---@param networks LuaLogisticNetwork[]
---@param inventory defines.inventory
function aqu.module_quality(entity, module, stack, networks, inventory)
  if module.valid_for_read then
    for j = #storage.qualities, 1, -1 do
      local quality = storage.qualities[j]
      if quality.name == module.quality.name then
        return
      end
      for _, network in ipairs(networks) do
        local n = aqu.get_used_item_by_network(network, module.name, quality.name) + 1
        if network.can_satisfy_request({ name = module.name, quality = quality }, n, true) then
          if n > 100 then
            log("n = " .. n)
            log(module.name)
            log(serpent.block(quality))
          end
          if entity.surface.create_entity({
                name = "item-request-proxy",
                position = entity.position,
                target = entity,
                force = entity.force,
                modules = { {
                  id = {
                    name = module.name,
                    quality = quality.name,
                  },
                  items = {
                    in_inventory = { {
                      inventory = inventory,
                      stack = stack,
                      count = 1,
                    } }
                  },
                } },
                removal_plan = { {
                  id = {
                    name = module.name,
                    quality = module.quality.name,
                  },
                  items = {
                    in_inventory = { {
                      inventory = inventory,
                      stack = stack,
                      count = 1,
                    } }
                  },
                } },
              }) then
            aqu.add_used_item_to_network(network, module.name, quality.name)
            return
          end
        end
      end
    end
  end
end

---@param entity LuaEntity
---@param networks LuaLogisticNetwork[]
function aqu.try_upgrade_modules(entity, networks)
  if entity.item_request_proxy then
    aqu.handle_cancel_request(entity.item_request_proxy, networks)
    return
  end
  local module_inventory = entity.get_module_inventory()
  if not module_inventory then
    return
  end
  for i = 1, #module_inventory do
    local module = module_inventory[i]
    aqu.module_quality(entity, module, i - 1, networks, module_inventory.index)
  end
end

---@param entity LuaEntity
---@param networks LuaLogisticNetwork[]
---@param prototype LuaEntityPrototype
---@param allow_downgrade boolean
function aqu.try_upgrade(entity, networks, prototype, allow_downgrade)
  aqu.try_upgrade_entity(entity, networks, prototype, allow_downgrade)
end

---@param entity LuaEntity
function aqu.process_entity(entity)
  if entity.to_be_deconstructed() then
    return
  end

  if entity.to_be_upgraded() then
    aqu.process_entity_to_be_upgraded(entity)
    return
  end

  local networks = entity.surface.find_logistic_networks_by_construction_area(entity.position, entity.force)
  if #networks == 0 then
    return
  end

  if entity.type == "entity-ghost" then
    if entity.is_registered_for_construction() then
      aqu.try_upgrade(entity, networks, entity.ghost_prototype --[[@as LuaEntityPrototype]], true)
    end
  else
    aqu.try_upgrade(entity, networks, entity.prototype, false)
    if settings.global["aqu-modules-upgrades"].value then
      aqu.try_upgrade_modules(entity, networks)
    end
  end
end

function aqu.init_entities_by_run()
  if settings.global["aqu-tick-mode"].value == "cycle" then
    storage.entities_by_run = math.max(1, #storage.entities / settings.global["aqu-ticks-per-cycle"].value)
  else
    storage.entities_by_run = settings.global["aqu-entities-per-on-nth-tick"].value
  end
end

---@param entity LuaEntity
---@return boolean
function aqu.fully_upgraded(entity)
  return entity.type ~= "entity-ghost" and entity.quality.next == nil
end

---@param tick NthTickEventData
function aqu.run(tick)
  for _ = 1, storage.entities_by_run do
    if storage.current_index <= #storage.entities then
      local entity = storage.entities[storage.current_index]

      if entity and entity.valid and not aqu.fully_upgraded(entity) then
        aqu.process_entity(entity)
        storage.current_index = storage.current_index + 1
      else
        storage.entities[storage.current_index] = storage.entities[#storage.entities]
        storage.entities[#storage.entities] = nil
      end
    else
      storage.current_index = 1
      aqu.setup_nth_tick()
      aqu.init_entities_by_run()
      aqu.reduce_item_used()
    end
  end
end

---@param entity LuaEntity
function aqu.add_entity(entity)
  local prototype
  if entity.type == "entity-ghost" then
    prototype = entity.ghost_prototype
  else
    prototype = entity.prototype
  end
  local items_to_place_this = prototype.items_to_place_this
  if items_to_place_this and #items_to_place_this > 0 and not aqu.fully_upgraded(entity) then
    table.insert(storage.entities, entity)
  end
end

---@param command CustomCommandData
function aqu.info(command)
  local player = game.get_player(command.player_index)
  local print
  if player then
    print = player.force.print
  else
    print = game.print
  end

  print(string.format("Entities count: %d, Current index: %d", #storage.entities, storage.current_index))
  print(string.format("Current rate is %d entites every %d ticks", storage.entities_by_run, aqu.tick()))

  ---@type table<string, table<string, int>>
  local entities_count_per_quality = {}
  local entities_ghost_count_per_quality = {}
  for _, entity in ipairs(storage.entities) do
    if entity.valid then
      if entity.type == "entity-ghost" then
        local name = entity.ghost_prototype.name
        if not entities_ghost_count_per_quality[entity.quality.name] then
          entities_ghost_count_per_quality[entity.quality.name] = {}
        end
        if not entities_ghost_count_per_quality[entity.quality.name][name] then
          entities_ghost_count_per_quality[entity.quality.name][name] = 1
        else
          util.increment(entities_ghost_count_per_quality[entity.quality.name], name)
        end
      else
        if not entities_count_per_quality[entity.quality.name] then
          entities_count_per_quality[entity.quality.name] = {}
        end
        if not entities_count_per_quality[entity.quality.name][entity.name] then
          entities_count_per_quality[entity.quality.name][entity.name] = 1
        else
          util.increment(entities_count_per_quality[entity.quality.name], entity.name)
        end
      end
    end
  end
  for quality_name, entities_count in pairs(entities_count_per_quality) do
    local line = string.format("[img=quality.%s]", quality_name)
    for entity_name, count in pairs(entities_count) do
      line = string.format("%s [img=entity.%s] %d", line, entity_name, count)
    end
    print(line)
  end
  for quality_name, entities_count in pairs(entities_ghost_count_per_quality) do
    local line = string.format("[img=entity.entity-ghost][img=quality.%s]", quality_name)
    for entity_name, count in pairs(entities_count) do
      line = string.format("%s [img=entity.%s] %d", line, entity_name, count)
    end
    print(line)
  end
end

---@return LuaPlayerBuiltEntityEventFilter[]
function aqu.event_filters()
  local filters = aqu.filters()
  local event_filters = {}
  for _, type in ipairs(filters) do
    table.insert(event_filters, { filter = "type", type = type })
    table.insert(event_filters, { filter = "ghost_type", type = type })
  end

  return event_filters
end

---@return string[]
function aqu.filters()
  local filters = {}
  for type in settings.global["aqu-watch-types"].value --[[@as string]]:gmatch("([^,]+)") do
    type = type:match("^%s*(.-)%s*$")
    table.insert(filters, type)
  end

  return filters
end

function aqu.init()
  local filters = aqu.filters()

  storage.networks = {}

  storage.entities = {}
  storage.current_index = 1
  for _, surface in pairs(game.surfaces) do
    for _, entity in ipairs(surface.find_entities_filtered({ type = filters })) do
      aqu.add_entity(entity)
    end

    for _, entity in ipairs(surface.find_entities_filtered({ ghost_type = filters })) do
      aqu.add_entity(entity)
    end
  end

  storage.qualities = {}
  local quality = prototypes.quality["normal"]
  while quality do
    table.insert(storage.qualities, quality)
    quality = quality.next
  end

  aqu.init_entities_by_run()
end

---@nodiscard
---@return int
function aqu.tick()
  if settings.global["aqu-tick-mode"].value == "cycle" then
    if storage.entities then
      return math.max(1, settings.global["aqu-ticks-per-cycle"].value / math.max(1, #storage.entities))
    else
      return 1
    end
  else
    return settings.global["aqu-on-nth-tick"].value --[[@as integer]]
  end
end

function aqu.setup_nth_tick()
  script.on_nth_tick(nil)
  script.on_nth_tick(aqu.tick(), aqu.run)
end

function aqu.on_load()
  local event_filters = aqu.event_filters()

  script.on_event(defines.events.on_built_entity, function(event)
    aqu.add_entity(event.entity)
  end, event_filters)

  script.on_event(defines.events.on_robot_built_entity, function(event)
    aqu.add_entity(event.entity)
  end, event_filters)

  script.on_event(defines.events.script_raised_built, function(event)
    aqu.add_entity(event.entity)
  end, event_filters)

  script.on_event(defines.events.script_raised_revive, function(event)
    aqu.add_entity(event.entity)
  end, event_filters)

  script.on_event(defines.events.on_space_platform_built_entity, function(event)
    aqu.add_entity(event.entity)
  end, event_filters)

  script.on_event(defines.events.on_entity_cloned, function(event)
    aqu.add_entity(event.destination)
  end, event_filters)

  script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    local settings = prototypes.get_mod_setting_filtered { { filter = "mod", mod = "AutoQualityUpgrades" } }
    if settings[event.setting] then
      aqu.on_configuration_changed()
    end
  end)

  aqu.setup_nth_tick()
end

function aqu.on_configuration_changed()
  aqu.init()
  aqu.on_load()
end

script.on_init(aqu.on_configuration_changed)

script.on_load(aqu.on_load)

script.on_configuration_changed(aqu.on_configuration_changed)

commands.add_command("aqu_init", "Init storage, feel free to use to refresh entities list", aqu.on_configuration_changed)
commands.add_command("aqu_info", "Show some info about rate and watch entities", aqu.info)

commands.add_command("aqu_log_storage", "Log some storage info for debug", function(command)
  log(serpent.block(storage.networks))
end)
