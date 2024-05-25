local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

---@class BlueprintShotgun.upgrades
local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    if params.ammo_limit == 0 then return end

    local entities = utils.find_entities_in_radius(params.surface, {
        position = params.target_pos,
        radius = params.radius,
        to_be_upgraded = true,
    })
    table.sort(entities, utils.distance_sort(params.target_pos))
    utils.arc_cull(entities, params.character.position, params.target_pos)

    for _, entity in pairs(entities) do
        if global.to_upgrade[entity.unit_number] then goto continue end
        local upgrade_target = entity.get_upgrade_target() --[[@as LuaEntityPrototype]]
        if upgrade_target.name == entity.name then goto continue end

        local place_items = upgrade_target.items_to_place_this ---@cast place_items -nil
        local item
        for _, place_item in pairs(place_items) do
            if params.inventory.get_item_count(place_item.name) >= place_item.count then
                item = place_item
                break
            end
        end
        if not item then goto continue end
        local is_underground_belt = entity.type == "underground-belt"
        local connection
        if is_underground_belt then
            connection = entity.neighbours
            if connection then
                -- impossible for connection not be marked for upgrade so no need to check
                item.count = item.count * 2
                global.to_upgrade[connection.unit_number] = true
            end
        end
        params.inventory.remove(item)

        local id, shadow = render.draw_new_item(params.surface, item.name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, entity.position)
        global.flying_items[id] = {
            action = "upgrade",
            surface = params.surface,
            force = params.force,
            name = item.name,
            count = item.count,
            source_pos = params.source_pos,
            target_pos = entity.position,
            start_tick = params.tick,
            end_tick = params.tick + duration,
            orientation_deviation = utils.orientation_deviaiton(),
            target_entity = entity,
            unit_number = entity.unit_number,
            shadow = shadow,
            connection = connection,
        } --[[@as FlyingUpgradeItem]]

        global.to_upgrade[entity.unit_number] = true

        params.ammo_item.drain_ammo(1)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end
end

---@param item FlyingUpgradeItem
function lib.action(item)
    local target_entity = item.target_entity --[[@as LuaEntity]]
    if target_entity.valid and utils.upgrade_entity(target_entity) then
        local connection = item.connection
        if connection and connection.valid then
            if not utils.upgrade_entity(connection, item.target_pos) then
                item.count = item.count / 2
                utils.spill_item(item)
            end
        end
    else
        utils.spill_item(item)
    end
    global.to_upgrade[item.unit_number] = nil
end

return lib

---@class FlyingUpgradeItem:FlyingItemBase
---@field action "upgrade"
---@field count uint
---@field target_entity LuaEntity
---@field unit_number uint
---@field connection LuaEntity?