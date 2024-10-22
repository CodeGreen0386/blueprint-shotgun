local e = defines.events

local vec = require("scripts/vector")
local render = require("scripts/render")
local utils = require("scripts/utils")

local flying_items = require("scripts/flying-items")
local sound = require("scripts/sound")
local cliffs = require("scripts/build/cliffs")

local build = {
    cliffs.process,
    require("scripts/build/entity-ghosts").process,
    require("scripts/build/upgrades").process,
    require("scripts/build/proxies").process,
    require("scripts/build/tile-ghosts").process,
}

local mine = {
    require("scripts/mine/entities").process,
    require("scripts/mine/tiles").process,
    require("scripts/mine/item-entities").process,
}

local function setup_globals()
    ---@type table<uint, FlyingItem>
    storage.flying_items = storage.flying_items or {}

    ---@type table<uint, VacuumItem>
    storage.vacuum_items = storage.vacuum_items or {}

    ---@type table<uint, uint[]?>
    storage.remove_explode_queue = storage.remove_explode_queue or {}

    ---@type table<uint, true>
    storage.to_explode = storage.to_explode or {}

    ---@type table<uint, true>
    storage.to_build = storage.to_build or {}

    ---@type table<uint, true>
    storage.to_upgrade = storage.to_upgrade or {}

    ---@type table<uint, table<string, uint>>
    storage.to_insert = storage.to_insert or {}

    ---@type table<uint, BlueprintShotgun.MiningData>
    storage.to_mine = storage.to_mine or {}

    ---@type table<uint, true>
    storage.currently_mining = storage.currently_mining or {}

    ---@type table<uint, BlueprintShotgun.CharacterData>
    storage.characters = storage.characters or {}
end

script.on_init(setup_globals)
script.on_configuration_changed(setup_globals)

script.on_event("blueprint-shotgun-shoot", function(event)
    local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
    if player.mod_settings["blueprint-shotgun-disable-auto-swap"].value then return end
    if not player.character then return end
    local data = utils.get_character_data(player.character)
    if event.tick - data.tick < 30 then return end
    local selected = player.selected
    if not selected then return end
    if player.selected.to_be_deconstructed() then
        data.mode = "mine"
    end
end)

script.on_event("blueprint-shotgun-mode-swap", function(event)
    local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
    local data = utils.get_character_data(player.character)
    local gun_inv = data.character.get_inventory(defines.inventory.character_guns) --[[@as LuaInventory]]
    local gun = gun_inv[data.character.selected_gun_index]
    if not (gun and gun.valid_for_read) then return end
    if gun.name ~= "blueprint-shotgun" then return end
    data.mode = data.mode == "build" and "mine" or "build"
    player.play_sound{path = "utility/switch_gun"}
    player.create_local_flying_text{
        color = {1,1,1},
        position = player.position,
        text = {"blueprint-shotgun.mode-" .. data.mode}
    }
end)

local direction_to_angle = 1 / defines.direction.south * math.pi

script.on_event(e.on_script_trigger_effect, function(event)
    if event.effect_id ~= "blueprint-shotgun" then return end
    local surface = game.get_surface(event.surface_index) --[[@as LuaSurface]]
    local character = event.source_entity --[[@as LuaEntity]]
    if not character then return end

    -- if character.player then
    --     rendering.draw_circle{
    --         color = {r = 0.05, g = 0.1, b = 0.05, a = 0.15},
    --         radius = 15,
    --         surface = character.surface,
    --         target = character,
    --         draw_on_ground = true,
    --         filled = true,
    --         players = {character.player},
    --         time_to_live = 3,
    --     }
    -- end

    local data = utils.get_character_data(character)
    if data.mode == "build" and event.tick - data.tick < 30 then return end

    local source_pos = event.source_position --[[@as MapPosition]]
    local target_pos = event.target_position --[[@as MapPosition]]

    local technologies = character.force.technologies
    local bonus = settings.startup["blueprint-shotgun-cheat-bonus"].value
    if technologies["blueprint-shotgun-upgrade-1"].researched then bonus = bonus + 1 end
    if technologies["blueprint-shotgun-upgrade-2"].researched then bonus = bonus + 1 end

    local inventory = character.get_main_inventory() --[[@as LuaInventory]]
    local gun_index = character.selected_gun_index
    local ammo_inv = character.get_inventory(defines.inventory.character_ammo) --[[@as LuaInventory]]
    local ammo_item = ammo_inv[gun_index]
    local ammo_limit = math.min(4 + 2 * bonus, (ammo_item.count - 1) * ammo_item.prototype.stack_size + ammo_item.ammo) --[[@as number]]

    local target_direction = math.floor((math.atan2(-source_pos.x + target_pos.x, source_pos.y - target_pos.y) / (2 * math.pi) + 17/16) % 1 * 8)

    ---@class BlueprintShotgun.HandlerParams
    ---@field ammo_limit integer -- required to be mutable for some stupid reason
    local params = {
        surface = surface,
        character = character,
        force = character.force,
        inventory = inventory,
        ammo_item = ammo_item,
        ammo_limit = ammo_limit,
        bonus = bonus,
        mining_speed = (2 + bonus) * 5/4,
        source_pos = vec.add(source_pos, vec.rotate({x = 0, y = -1.125}, target_direction * direction_to_angle)),
        target_pos = target_pos,
        radius = 3.5,
        tick = event.tick,
    }

    if data.mode == "build" then
        if event.tick - data.tick < 30 then return end

        for _, process in pairs(build) do
            process(params)
            if not params.ammo_item.valid_for_read then break end
        end

        local used_item_count = ammo_limit - params.ammo_limit
        if used_item_count > 0 then
            game.play_sound{path = "blueprint-shotgun-shoot", position = source_pos}
            data.tick = event.tick
        end

        if used_item_count == 0 then
            if character.player and character.player.mod_settings["blueprint-shotgun-disable-auto-swap"].value then return end
            data.mode = "mine"
        end
    end

    if data.mode == "mine" then
        if event.tick - data.tick < 3 then return end

        local mined
        for _, process in pairs(mine) do
            mined = process(params) or mined
            if not params.ammo_item.valid_for_read then break end
        end

        if mined then
            render.smoke(surface, target_pos, character)
            data.tick = event.tick
        else
            if event.tick - data.tick < 30 then return end
            if character.player and character.player.mod_settings["blueprint-shotgun-disable-auto-swap"].value then return end
            data.mode = "build"
        end
    end
end)

script.on_event(e.on_tick, function(event)
    cliffs.on_tick(event)
    render.on_tick(event)
    flying_items.on_tick(event)
    sound.on_tick(event)
end)

script.on_event(e.on_object_destroyed, function(event)
    if not event.unit_number then return end
    storage.characters[event.unit_number] = nil
    storage.to_explode[event.registration_number] = nil
end)

script.on_event(e.on_surface_deleted, function(event)
    for id, item in pairs(storage.flying_items) do
        if item.surface.valid then goto continue end
        storage.flying_items[id] = nil

        local entity = item.target_entity
        if not entity then goto continue end
        storage.to_build[item.unit_number] = nil
        storage.to_insert[item.unit_number] = nil
        storage.to_upgrade[item.unit_number] = nil

        ::continue::
    end

    for id, item in pairs(storage.vacuum_items) do
        if item.surface.valid then goto continue end
        storage.vacuum_items[id] = nil

        ::continue::
    end
end)
