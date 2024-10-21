local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local vec = require("scripts/vector") --[[@as BlueprintShotgun.vector]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

local tick_rate = 3

---@class BlueprintShotgun.tiles
local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    local entities = utils.find_entities_in_radius(params.surface, {
        position = params.target_pos,
        radius = 2,
        type = "deconstructible-tile-proxy"
    })
    table.sort(entities, utils.distance_sort(params.target_pos))

    if #entities == 0 then return end

    for _, proxy in pairs(entities) do
        local proxy_id = script.register_on_entity_destroyed(proxy)
        local data = storage.to_mine[proxy_id]
        if not data then
            local mineable_properties = proxy.prototype.mineable_properties
            data = {
                entity = proxy,
                progress = 0,
                mining_time = math.max(mineable_properties.mining_time, 0.5) * 60,
            }
            storage.to_mine[proxy_id] = data
        end

        local progress = params.mining_speed / math.max(1, vec.dist(params.target_pos, proxy.position))
        data.progress = data.progress + progress
        storage.currently_mining[proxy_id] = true

        if data.progress < data.mining_time then goto continue end

        local position = proxy.position
        ---@diagnostic disable-next-line: missing-parameter, param-type-mismatch
        local prototype = params.surface.get_tile(proxy.position).prototype

        local sound_path = "tile-mined/" .. prototype.name
        if game.is_valid_sound_path(sound_path) then
            game.play_sound{path = sound_path, position = proxy.position}
        end

        local size = #prototype.mineable_properties.products
        local temp_inventory = game.create_inventory(size)
        local success = proxy.mine{inventory = temp_inventory, force = false, raise_destroyed = true}
        while not success do
            size = size + 1
            temp_inventory.resize(size)
            success = proxy.mine{inventory = temp_inventory, force = false, raise_destroyed = true}
        end
        storage.to_mine[proxy_id] = nil

        for i = 1, #temp_inventory do
            local item = temp_inventory[i]
            if not item.valid_for_read then break end
            local id, shadow = render.draw_new_item(params.surface, item.name, position, 0)
            rendering.move_to_back(id)
            local slot = game.create_inventory(1)
            slot[1].transfer_stack(item)
            storage.vacuum_items[id] = {
                slot = slot,
                surface = params.surface,
                character = params.character,
                time = 0,
                position = position,
                velocity = vec.random(1/15),
                height = 0,
                orientation_deviation = utils.orientation_deviaiton(),
                shadow = shadow,
                deconstruct = params.character.force,
            }
        end
        temp_inventory.destroy()

        params.ammo_item.drain_ammo(1)
        if not params.ammo_item.valid_for_read then break end

        ::continue::
    end

    return true
end

return lib