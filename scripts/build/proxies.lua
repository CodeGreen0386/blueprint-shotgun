local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

---@class BlueprintShotgun.proxies
local lib = {}

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

    for _, proxy in pairs(proxies) do
        local to_insert = storage.to_insert[proxy.unit_number] or {}
        storage.to_insert = to_insert

        local requests = proxy.item_requests
        for name, count in pairs(to_insert) do
            if requests[name] then
                requests[name] = requests[name] - count
            end
        end

        local inventory = params.inventory
        local item, stack
        for request_name, request_count in pairs(requests) do
            local count = math.min(inventory.get_item_count(request_name), request_count)
            if count > 0 then
                stack = inventory.find_item_stack(request_name) --[[@as LuaItemStack]]
                if proxy.proxy_target.can_insert(stack) then
                    item = {name = request_name, count = count}
                    break
                end
            end
        end
        if not item then goto continue end

        local sprite, shadow = render.draw_new_item(params.surface, item.name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, proxy.position)
        storage.flying_items[sprite] = {
            action = "request",
            surface = params.surface,
            force = params.force,
            name = item.name,
            count = item.count,
            ammo = stack.is_ammo and stack.ammo or nil,
            durability = stack.is_tool and stack.durability or nil,
            source_pos = params.source_pos,
            target_pos = proxy.position,
            start_tick = params.tick,
            end_tick = params.tick + duration,
            orientation_deviation = utils.orientation_deviaiton(),
            shadow = shadow,
            target_entity = proxy.proxy_target,
            unit_number = proxy.unit_number,
        } --[[@as FlyingRequestItem]]

        inventory.remove(item)
        requests[item.name] = requests[item.name] - item.count
        proxy.item_requests = requests

        params.ammo_item.drain_ammo(1)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end
end

---@param item FlyingRequestItem
function lib.action(item)
    local target_entity = item.target_entity
    if target_entity.valid then
        local item_stack = {name = item.name, count = item.count, ammo = item.ammo, durability = item.durability}
        local inventories = {target_entity.get_module_inventory(), target_entity}
        local inserted_count = 0
        for _, inventory in pairs(inventories) do
            inserted_count = inserted_count + inventory.insert(item_stack)
            if inserted_count >= item_stack.count then break end
        end
        if inserted_count > 0 then
            game.play_sound{path = "utility/inventory_move", position = item.target_pos}
        end
        if inserted_count < item_stack.count then
            item.count = item_stack.count - inserted_count
            utils.spill_item(item)
        end
    else
        utils.spill_item(item)
    end
end

return lib

---@class FlyingRequestItem:FlyingItemBase
---@field action "request"
---@field count uint
---@field ammo float?
---@field durability float?
---@field target_entity LuaEntity
---@field unit_number uint
