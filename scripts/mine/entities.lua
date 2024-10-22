local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local vec = require("scripts/vector") --[[@as BlueprintShotgun.vector]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

---@class BlueprintShotgun.mine
local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    local entities = utils.find_entities_in_radius(params.surface, {
        position = params.target_pos,
        radius = 2,
        to_be_deconstructed = true,
    })
    table.sort(entities, utils.distance_sort(params.target_pos))

    if #entities == 0 then return end

    for index, entity in pairs(entities) do
        if entity.type == "item-entity" or entity.type == "deconstructible-tile-proxy" or entity.type == "cliff" then
            entities[index] = nil
            goto continue
        end
        if entity.minable == false then goto continue end
        if entity.prototype.mineable_properties.minable == false then goto continue end
        local entity_id = entity.unit_number or script.register_on_object_destroyed(entity)
        local data = storage.to_mine[entity_id]
        if not data then
            local mineable_properties = entity.prototype.mineable_properties
            data = {
                entity = entity,
                progress = 0,
                mining_time = math.max(mineable_properties.mining_time, 0.5) * 60,
            }
            storage.to_mine[entity_id] = data
        end

        local stack
        if entity.type ~= "infinity-container" then
            for i = 1, entity.get_max_inventory_index() do
                local inventory = entity.get_inventory(i) --[[@as LuaInventory]]
                if inventory and not inventory.is_empty() then
                    local name = next(inventory.get_contents())
                    stack = inventory.find_item_stack(name)
                    break
                end
            end
        end

        if stack then
            game.play_sound{path = "utility/picked_up_item", position = entity.position}
            local sprite, shadow = render.draw_new_item(entity.surface, stack.name, entity.position, 0)
            sprite.move_to_back()
            local slot = game.create_inventory(1)
            slot[1].transfer_stack(stack)
            storage.vacuum_items[sprite] = {
                slot = slot,
                surface = params.surface,
                character = params.character,
                time = 0,
                position = entity.position,
                velocity = vec.random(1/15),
                height = 0,
                orientation_deviation = utils.orientation_deviaiton(),
                shadow = shadow,
                deconstruct = params.character.force,
            }
            goto continue
        end

        local progress = params.mining_speed / math.max(1, vec.dist(params.target_pos, entity.position))
        data.progress = data.progress + progress
        storage.currently_mining[entity_id] = true

        if data.progress < data.mining_time then goto continue end

        local sound_path = "entity-mined/" .. entity.name
        if helpers.is_valid_sound_path(sound_path) then
            game.play_sound{path = sound_path, position = entity.position}
        end

        if entity.type == "infinity-container" then
            entity.clear_items_inside()
        end

        local position = entity.position
        local products = entity.prototype.mineable_properties.products
        local size = products and #products or 0
        local temp_inventory = game.create_inventory(size)
        local success = entity.mine{inventory = temp_inventory, force = false, raise_destroyed = true}
        while not success do
            size = size + 1
            temp_inventory.resize(size)
            success = entity.mine{inventory = temp_inventory, force = false, raise_destroyed = true}
        end
        storage.to_mine[entity_id] = nil

        for i = 1, #temp_inventory do
            local item = temp_inventory[i]
            if not item.valid_for_read then break end
            local sprite, shadow = render.draw_new_item(params.surface, item.name, position, 0)
            sprite.move_to_back()
            local slot = game.create_inventory(1)
            slot[1].transfer_stack(item)
            storage.vacuum_items[sprite] = {
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

    return not not next(entities)
end

return lib

---@class BlueprintShotgun.MiningData
---@field entity LuaEntity
---@field progress number
---@field mining_time number
---@field bar uint?
---@field bar_black uint?
