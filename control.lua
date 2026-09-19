---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local e = defines.events

local render = require("scripts/render") ---@module "blueprint-shotgun/scripts/render"
local utils = require("scripts/utils") ---@module "blueprint-shotgun/scripts/utils"
local vec = require("scripts/vector") ---@module "blueprint-shotgun/scripts/vector"

local flying_items = require("scripts/flying-items")
local sound = require("scripts/sound")
local cliffs = require("scripts/build/cliffs")

local build = {
    cliffs = cliffs.process,
    entity_ghosts = require("scripts/build/entity-ghosts").process,
    upgrades = require("scripts/build/upgrades").process,
    proxies = require("scripts/build/proxies").process,
    tile_ghosts = require("scripts/build/tile-ghosts").process,
}

local mine = {
    require("scripts/mine/entities"),
    require("scripts/mine/tiles"),
    require("scripts/mine/item-entities"),
    require("scripts/mine/proxies"),
}

local function setup_storage()
    ---@class Storage
    storage = {
        ---@type table<uint, FlyingItem>
        flying_items = storage.flying_items or {},
        ---@type table<uint, VacuumItem>
        vacuum_items = storage.vacuum_items or {},
        ---@type table<uint, uint[]?>
        remove_explode_queue = storage.remove_explode_queue or {},
        ---@type table<uint, true>
        to_explode = storage.to_explode or {},
        ---@type table<uint, true>
        to_build = storage.to_build or {},
        ---@type table<uint, true>
        to_upgrade = storage.to_upgrade or {},
        ---@type table<uint, BlueprintShotgun.MiningData>
        to_mine = storage.to_mine or {},
        ---@type table<uint, true>
        currently_mining = storage.currently_mining or {},
        ---@type table<uint, BlueprintShotgun.CharacterData>
        characters = storage.characters or {},

        ---@type table<string, true>?
        cubes = script.active_mods["Ultracube"] and remote.call("Ultracube", "cube_item_prototypes")
    }
end

script.on_init(setup_storage)
script.on_configuration_changed(function()
    setup_storage()

    for _, data in pairs(storage.characters) do
        if data.auto_swap == nil then
            data.auto_swap = true
        end
        if data.aim_position == nil then
            data.aim_position = true
        end
    end
end)

---@param event EventData.CustomInputEvent
script.on_event("blueprint-shotgun-shoot", function(event)
    local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
    if not player.character then return end
    local data = utils.get_character_data(player.character)
    if data.auto_swap == false then return end
    if event.tick - data.tick < 30 then return end
    local selected = player.selected
    if not selected then return end
    if player.selected.to_be_deconstructed() then
        data.mode = "mine"
    end
end)

---@param event EventData.CustomInputEvent
script.on_event("blueprint-shotgun-mode-swap", function(event)
    local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
    if not player.character then return end
    local data = utils.get_character_data(player.character)
    local gun_inv = data.character.get_inventory(defines.inventory.character_guns) --[[@as LuaInventory]]
    local gun = gun_inv[data.character.selected_gun_index]
    if not (gun and gun.valid_for_read) then return end
    if gun.name ~= "blueprint-shotgun" then return end
    local text
    local setting = player.mod_settings["blueprint-shotgun-mode-swap"].value
    if setting == "3-way" then
        if data.auto_swap then
            data.auto_swap = false
            data.mode = "build"
            text = "build"
        elseif data.mode == "build" then
            data.mode = "mine"
            text = "mine"
        else
            data.auto_swap = true
            text = "auto"
        end
    else
        data.auto_swap = setting == "auto"
        data.mode = data.mode == "build" and "mine" or "build"
        text = data.mode
    end

    player.play_sound{path = "utility/switch_gun"}
    player.create_local_flying_text{
        color = {1,1,1},
        position = player.position,
        text = {"blueprint-shotgun.mode-swap", {"blueprint-shotgun.mode-" .. text}}
    }
end)

script.on_event(e.on_player_input_method_changed, function(event)
    local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
    if not player.character then return end
    if player.mod_settings["blueprint-shotgun-aim-mode"].value ~= "auto" then return end
    local data = utils.get_character_data(player.character)
    data.aim_position = player.input_method == defines.input_method.keyboard_and_mouse
end)

script.on_event(e.on_runtime_mod_setting_changed, function(event)
    if event.setting_type ~= "runtime-per-user" then return end
    ---@cast event.player_index uint32
    local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
    if not player.character then return end

    local data = utils.get_character_data(player.character)
    if event.setting == "blueprint-shotgun-mode-swap" then
        data.auto_swap = player.mod_settings[event.setting].value ~= "manual"
    elseif event.setting == "blueprint-shotgun-aim-mode" then
        local aim_mode = player.mod_settings["blueprint-shotgun-aim-mode"].value --[[@as string]]
        if aim_mode == "auto" then
            data.aim_position = player.input_method == defines.input_method.keyboard_and_mouse
        else
            data.aim_position = aim_mode == "position"
        end
    end
end)

local direction_to_angle = 1 / defines.direction.south * math.pi

script.on_event(e.on_script_trigger_effect, function(event)
    if event.effect_id ~= "blueprint-shotgun" then return end
    local surface = game.get_surface(event.surface_index) --[[@as LuaSurface]]
    local character = event.source_entity
    if not character then return end

    local character_radius = character.get_radius()
    local radius = 15 + character_radius

    -- render.debug_circle({g = 0.15, a = 0.15}, radius, surface, character)
    -- render.debug_circle({g = 0.15, b = 0.15, a = 0.15}, radius + 3.5, surface, character)

    local data = utils.get_character_data(character)
    if data.mode == "build" and event.tick - data.tick < 30 then return end

    local source_pos = event.source_position --[[@as MapPosition]]
    local target_pos = event.target_position --[[@as MapPosition]]

    local angle = math.atan2(-source_pos.x + target_pos.x, source_pos.y - target_pos.y)
    -- render.debug_line({r = 1, g = 1}, 2, surface,
    --     vec.add(source_pos, vec.rotate({x = 0, y = -1.125}, angle)),
    --     vec.add(source_pos, vec.rotate({x = 0, y = -radius}, angle))
    -- )

    -- render.debug_circle({r = 1}, 1/4, surface, target_pos)

    if vec.dist2(character.position, target_pos) > (15 + character.get_radius())^2 then
        target_pos = vec.add(character.position, vec.rotate({x = 0, y = -radius}, angle))
        -- render.debug_circle({g = 1}, 1/4, surface, target_pos)
    end

    local technologies = character.force.technologies
    local bonus = settings.startup["blueprint-shotgun-cheat-bonus"].value
    if technologies["blueprint-shotgun-upgrade-1"].researched then bonus = bonus + 1 end
    if technologies["blueprint-shotgun-upgrade-2"].researched then bonus = bonus + 1 end

    local inventory = character.get_main_inventory() --[[@as LuaInventory]]
    local gun_index = character.selected_gun_index --[[@as uint32]]
    local ammo_inv = character.get_inventory(defines.inventory.character_ammo) --[[@as LuaInventory]]
    local ammo_item = ammo_inv[gun_index] --[[@as LuaItemStack]]
    local ammo_limit = math.min(4 + 2 * bonus, (ammo_item.count - 1) * ammo_item.prototype.stack_size + ammo_item.ammo) --[[@as uint]]

    local target_direction = math.floor((math.atan2(-source_pos.x + target_pos.x, source_pos.y - target_pos.y) / (2 * math.pi) + 17/16) % 1 * 8) * 2

    ---@class HandlerParams
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

        local i = 1
        local max_tries = 1
        local offset = {x = 0, y = 0}

        if not data.aim_position then
            max_tries = 5
            offset = vec.rotate({x = 0, y = -3.5}, angle)
            params.target_pos = vec.add(character.position, vec.rotate({x = 0, y = -1 - character_radius}, angle))
        end

        local used_item_count = 0

        repeat
            local not_tiles = false
            local tiles = false
            for name, process in pairs(build) do
                if process(params) then
                    if name == "tile_ghosts" then
                        tiles = true
                    else
                        not_tiles = true
                    end
                end
                if not params.ammo_item.valid_for_read then break end
            end

            -- render.debug_circle({g = 0.15, a = 0.15}, params.radius, surface, params.target_pos)

            used_item_count = ammo_limit - params.ammo_limit

            if used_item_count > 0 then
                game.play_sound{path = "blueprint-shotgun-shoot", position = source_pos}
                data.tick = (tiles and not not_tiles) and event.tick - 25 or event.tick
                break
            else
                params.target_pos = vec.add(params.target_pos, offset)
            end

            i = i + 1
        until i > max_tries

        if used_item_count == 0 and data.auto_swap then
            data.mode = "mine"
        end
    end

    if data.mode == "mine" then
        if event.tick - data.tick < 3 then return end

        params.radius = 2

        local i = 1
        local max_tries = 1
        local offset = {x = 0, y = 0}

        if not data.aim_position then
            max_tries = 5
            offset = vec.rotate({x = 0, y = -3.5}, angle)
            params.target_pos = vec.add(character.position, vec.rotate({x = 0, y = -1 - character_radius}, angle))
        else
            params.target_pos = target_pos
        end

        local mined = false

        repeat
            -- render.debug_circle({r = 0.3, a = 0.3}, params.radius, surface, params.target_pos)

            for _, process in pairs(mine) do
                mined = process(params) or mined
                if not params.ammo_item.valid_for_read then break end
            end

            if mined then
                render.smoke(surface, params.target_pos, character)
                data.tick = event.tick
                break
            else
                params.target_pos = vec.add(params.target_pos, offset)
            end

            i = i + 1
        until i > max_tries

        if not mined then
            if data.auto_swap == false then return end
            if event.tick - data.tick < 30 then return end
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
    if not event.useful_id then return end
    storage.characters[event.useful_id] = nil
    storage.to_explode[event.registration_number] = nil
end)

script.on_event(e.on_surface_deleted, function(event)
    for id, item in pairs(storage.flying_items) do
        if item.surface.valid then goto continue end
        storage.flying_items[id] = nil

        local entity = item.target_entity
        if not entity then goto continue end
        storage.to_build[item.unit_number] = nil
        storage.to_upgrade[item.unit_number] = nil

        ::continue::
    end

    for id, item in pairs(storage.vacuum_items) do
        if item.surface.valid then goto continue end
        storage.vacuum_items[id] = nil

        ::continue::
    end
end)