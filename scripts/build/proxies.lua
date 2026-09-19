---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local render = require("scripts/render") ---@module "blueprint-shotgun/scripts/render"
local utils = require("scripts/utils") ---@module "blueprint-shotgun/scripts/utils"

local lib = {}

local ultracube_active = script.active_mods["Ultracube"]

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    if params.ammo_limit == 0 then return end

    local proxies = params.surface.find_entities_filtered{
        type = "item-request-proxy",
        position = params.target_pos,
        radius = params.radius,
        force = params.force,
    }
    table.sort(proxies, utils.distance_sort(params.target_pos))
    utils.arc_cull(proxies, params.character.position, params.target_pos)

    local used = false

    for _, proxy in pairs(proxies) do
        local target = proxy.proxy_target
        if not target then return end
        if target.to_be_upgraded() then goto continue end

        ---@type ItemWithQualityCount?, LuaItemStack, uint
        local item, stack, count
        local requests = proxy.item_requests
        local inventory = params.inventory
        for _, request in pairs(requests) do
            local min_count = math.min(inventory.get_item_count{name = request.name, quality = request.quality}, request.count) --[[@as int]]
            if min_count > 0 then
                stack = inventory.find_item_stack({name = request.name, quality = request.quality}) --[[@as LuaItemStack]]
                if target.can_insert(stack) then
                    item = {name = request.name, count = min_count, quality = request.quality}
                    count = min_count
                    break
                end
            end
        end
        if not item then goto continue end

        local inventory_positions = {} ---@type InventoryPosition[]?
        local grid_positions = {} ---@type EquipmentPosition[]?
        local insert_plan = proxy.insert_plan
        for i, plan in pairs(insert_plan) do
            if plan.id.name == item.name then
                local items = plan.items
                if items.in_inventory then
                    grid_positions = nil

                    for j, inventory_position in pairs(items.in_inventory) do
                        local insert_position = table.deepcopy(inventory_position)
                        inventory_positions[#inventory_positions+1] = insert_position
                        count = count - (inventory_position.count or 1)
                        if count < 0 then
                            insert_position.count = (inventory_position.count or 1) + count
                            inventory_position.count = -count
                        else
                            items.in_inventory[j] = nil
                        end
                        if count <= 0 then break end
                    end

                    items.in_inventory = utils.condense(items.in_inventory)
                else
                    inventory_positions = nil

                    local grid = target.grid --[[@as LuaEquipmentGrid]]
                    local prototype = prototypes.item[item.name].place_as_equipment_result --[[@as LuaEquipmentPrototype]]
                    local name = prototype.name
                    local grid_count = items.grid_count --[[@as ItemCountType]]
                    local equipments = {} ---@type LuaEquipment[]
                    local c = 0
                    for _, equipment in pairs(grid.equipment) do
                        if equipment.type == "equipment-ghost" and equipment.ghost_name == name then
                            c = c + 1
                            equipments[c] = equipment
                            if c == grid_count then break end
                        end
                    end

                    local insert_count = math.min(count, grid_count)
                    for j = 1, insert_count do
                        local equipment = equipments[j]
                        grid_positions[j] = equipment.position
                        grid.take{equipment = equipment}
                    end

                    items.grid_count = grid_count - insert_count
                end

                if not ((items.in_inventory and items.in_inventory[1]) or (items.grid_count and items.grid_count > 0)) then
                    insert_plan[i] = nil
                end
            end
        end
        proxy.insert_plan = insert_plan

        local slot = game.create_inventory(1)
        slot[1].transfer_stack(stack, item.count)

        local sprite, shadow = render.draw_new_item(params.surface, item.name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, proxy.position)
        local flying_item = {
            action = "request",
            slot = slot,
            surface = params.surface,
            force = params.force,
            source_pos = params.source_pos,
            target_pos = proxy.position,
            start_tick = params.tick,
            end_tick = params.tick + duration,
            orientation_deviation = utils.orientation_deviation(),
            sprite = sprite,
            shadow = shadow,
            target_entity = target,
            inventory_positions = inventory_positions,
            grid_positions = grid_positions,
            unit_number = proxy.unit_number --[[@as uint64]],
        } --[[@as FlyingRequestItem]]
        storage.flying_items[sprite.id] = flying_item

        if ultracube_active and storage.cubes[item.name] then
            flying_item.ultracube_token = utils.create_ultracube_token(item.name, item.count, params.surface, proxy.position, 1)
        end

        used = true
        params.ammo_item.drain_ammo(1)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end
    return used
end

---@param target_entity LuaEntity
---@param item_stack LuaItemStack
---@param position InventoryPosition
local function try_insert(target_entity, item_stack, position)
    local inventory = target_entity.get_inventory(position.inventory)
    if not inventory then return end
    local index = position.stack + 1
    if index > #inventory then return end
    local stack = inventory[index] --[[@as LuaItemStack]]
    return stack.transfer_stack(item_stack, index)
end

---@param item FlyingRequestItem
function lib.action(item)
    local target_entity = item.target_entity
    if target_entity.valid then
        local item_stack = item.slot[1]
        if item.inventory_positions then
            local inserted
            for _, position in pairs(item.inventory_positions) do
                if try_insert(target_entity, item_stack, position) then
                    inserted = true
                else
                    utils.spill_item(item)
                end
            end
            if inserted then
                game.play_sound{path = "utility/inventory_move", position = item.target_pos}
            end
        else ---@cast item.grid_positions -?
            local grid = target_entity.grid --[[@as LuaEquipmentGrid]]
            local equipment = item_stack.prototype.place_as_equipment_result --[[@as LuaEquipmentPrototype]]
            local inserted
            for _, position in pairs(item.grid_positions) do
                if grid.put{name = equipment, position = position, quality = item_stack.quality} then
                    item_stack.count = item_stack.count - 1
                    inserted = true
                end
            end
            if item_stack.count > 0 then
                utils.spill_item(item)
            end
            if inserted then
                game.play_sound{path = "utility/armor_insert", position = item.target_pos}
            end
        end
    else
        utils.spill_item(item)
    end
end

return lib

---@class FlyingRequestItem:FlyingItemBase
---@field action "request"
---@field target_entity LuaEntity
---@field inventory_positions? InventoryPosition[]
---@field grid_positions? EquipmentPosition[]
---@field unit_number uint