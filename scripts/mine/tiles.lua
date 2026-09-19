---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local render = require("scripts/render") ---@module "blueprint-shotgun/scripts/render"
local utils = require("scripts/utils") ---@module "blueprint-shotgun/scripts/utils"
local vec = require("scripts/vector") ---@module "blueprint-shotgun/scripts/vector"

---@param params BlueprintShotgun.HandlerParams
return function(params)
    local entities = utils.find_entities_in_radius(params.surface, {
        type = "deconstructible-tile-proxy",
        position = params.target_pos,
        radius = params.radius,
    })
    table.sort(entities, utils.distance_sort(params.target_pos))

    if #entities == 0 then return end

    for _, proxy in pairs(entities) do
        local proxy_id = script.register_on_object_destroyed(proxy)
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
        data.progress = math.min(data.mining_time, data.progress + progress)
        storage.currently_mining[proxy_id] = true

        if data.progress < data.mining_time then goto continue end

        local position = proxy.position
        ---@diagnostic disable-next-line: missing-parameter, param-type-mismatch
        local prototype = params.surface.get_tile(proxy.position).prototype

        local size = #prototype.mineable_properties.products
        local temp_inventory = game.create_inventory(size)
        local success = proxy.mine{inventory = temp_inventory, force = false}
        if not success then
            temp_inventory.destroy()
            goto continue
        end
        storage.to_mine[proxy_id] = nil

        local sound_path = "tile-mined/" .. prototype.name
        if helpers.is_valid_sound_path(sound_path) then
            game.play_sound{path = sound_path, position = position}
        end

        for i = 1, #temp_inventory do
            local item = temp_inventory[i] --[[@as LuaItemStack]]
            if not item.valid_for_read then break end
            local sprite, shadow = render.draw_new_item(params.surface, item.name, position, 0)
            sprite.move_to_back()
            local slot = game.create_inventory(1)
            slot[1].transfer_stack(item)
            storage.vacuum_items[sprite.id] = {
                slot = slot,
                surface = params.surface,
                character = params.character,
                time = 0,
                position = position,
                velocity = vec.random(1/15),
                height = 0,
                orientation_deviation = utils.orientation_deviation(),
                sprite = sprite,
                shadow = shadow,
                deconstruct = params.character.force,
            }
        end
        temp_inventory.destroy()

        params.ammo_item.drain_ammo(0.25)
        if not params.ammo_item.valid_for_read then break end

        ::continue::
    end

    return true
end