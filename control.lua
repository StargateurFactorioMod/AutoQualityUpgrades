local util = require("util")

local aqu = {}

aqu.debug = false

-- Types for storage so the language server warns on unknown fields like `storage.toto`
---@class (exact) Storage
---@field entities LuaEntity[]
---@field current_index integer
--- normal not included
---@field qualities LuaQualityPrototype[]
---@field entities_by_run int

---@type Storage
storage = storage

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

  if target.name == entity.name and entity.is_registered_for_upgrade() then
    for _, network in ipairs(networks) do
      for _, item in ipairs(entity.prototype.items_to_place_this) do
        if network.can_satisfy_request({ name = item.name, quality = quality }, 1, true) then
          return
        end
      end
    end

    entity.cancel_upgrade(entity.force)
  end
end

---@param entity LuaEntity
---@param networks LuaLogisticNetwork[]
---@param prototype LuaEntityPrototype
---@param allow_downgrade boolean
function aqu.try_upgrade(entity, networks, prototype, allow_downgrade)
  for i = #storage.qualities, 2, -1 do
    local quality = storage.qualities[i]
    if not allow_downgrade and quality.name == entity.quality.name then
      return
    end
    for _, item in ipairs(prototype.items_to_place_this) do
      for _, network in ipairs(networks) do
        if network.can_satisfy_request({ name = item.name, quality = quality }, 1, true) then
          entity.order_upgrade { target = { name = prototype.name, quality = quality }, force = entity.force }
          return
        end
      end
    end
  end
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
      aqu.try_upgrade(entity, networks, entity.ghost_prototype--[[@as LuaEntityPrototype]], true)
    end
  else
    aqu.try_upgrade(entity, networks, entity.prototype, false)
  end
end

function aqu.init_entities_by_run()
  storage.entities_by_run = math.max(1, #storage.entities / settings.global["aqu-ticks-by-cycle"].value)
end

---@param entity LuaEntity
---@return boolean
function aqu.fully_upgraded(entity)
  return false
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
  for type in settings.global["aqu-watch-types"].value--[[@as string]]:gmatch("([^,]+)") do
    type = type:match("^%s*(.-)%s*$")
    table.insert(filters, type)
  end

  return filters
end

function aqu.init()
  local filters = aqu.filters()

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
  if storage.entities then
    return math.max(1, settings.global["aqu-ticks-by-cycle"].value / math.max(1, #storage.entities))
  else
    return 1
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

script.on_init(aqu.init)

script.on_load(aqu.on_load)


script.on_configuration_changed(aqu.on_configuration_changed)

commands.add_command("aqu_init", "Init storage, feel free to use to refresh entities list", aqu.init)
commands.add_command("aqu_info", "Show some info about rate and watch entities", aqu.info)
