---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local render = require("scripts/render") ---@module "blueprint-shotgun/scripts/render"
local utils = require("scripts/utils") ---@module "blueprint-shotgun/scripts/utils"
local vec = require("scripts/vector") ---@module "blueprint-shotgun/scripts/vector"

local ultracube_active = script.active_mods["Ultracube"]

---@param params BlueprintShotgun.HandlerParams
return function(params)
    local entities = utils.find_entities_in_radius(params.surface, {
        to_be_deconstructed = true,
        position = params.target_pos,
        radius = params.radius,
    }, true)
    table.sort(entities, utils.distance_sort(params.target_pos))

    if #entities == 0 then return end

    for index, entity in pairs(entities) do
        if not entity.valid then goto continue end
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
                local inventory = entity.get_inventory(i --[[@as defines.inventory]]) --[[@as LuaInventory]]
                if inventory and not inventory.is_empty() then
                    local item = inventory.get_contents()[1]
                    stack = inventory.find_item_stack(item.name)
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
            local vacuum_item = {
                slot = slot,
                surface = params.surface,
                character = params.character,
                time = 0,
                position = entity.position,
                velocity = vec.random(1/15),
                height = 0,
                orientation_deviation = utils.orientation_deviation(),
                sprite = sprite,
                shadow = shadow,
                deconstruct = params.character.force,
            }
            storage.vacuum_items[sprite.id] = vacuum_item
            if ultracube_active then
                local slot_item = slot[1]
                local name = slot_item.name
                if storage.cubes[name] then
                    vacuum_item.ultracube_token = utils.create_ultracube_token(name, slot_item.count, params.surface, entity.position, 0, vacuum_item.velocity)
                end
            end
            goto continue
        end

        local progress = params.mining_speed / math.max(1, vec.dist(params.target_pos, entity.position))
        data.progress = math.min(data.mining_time, data.progress + progress)
        storage.currently_mining[entity_id] = true

        if data.progress < data.mining_time then goto continue end

        if entity.type == "infinity-container" then
            entity.clear_items_inside()
        end

        local sound_path = "entity-mined/" .. entity.name
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
            local vacuum_item = {
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
            storage.vacuum_items[sprite.id] = vacuum_item

            if ultracube_active then
                local slot_item = slot[1]
                local name = slot_item.name
                if storage.cubes[name] then
                    vacuum_item.ultracube_token = utils.create_ultracube_token(name, slot_item.count, params.surface, position, 0, vacuum_item.velocity)
                end
            end
        end
        temp_inventory.destroy()

        params.ammo_item.drain_ammo(1)
        if not params.ammo_item.valid_for_read then break end

        ::continue::
    end

    return not not next(entities)
end

---@class MiningData
---@field entity LuaEntity
---@field progress number
---@field mining_time number
---@field bar LuaRenderObject?
---@field bar_black LuaRenderObject?