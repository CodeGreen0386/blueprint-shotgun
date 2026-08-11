local utils = require("scripts/utils") --[[@as BlueprintShotgun.utils]]
local render = require("scripts/render") --[[@as BlueprintShotgun.render]]

---@class BlueprintShotgun.upgrades
local lib = {}

---@param params BlueprintShotgun.HandlerParams
function lib.process(params)
    if params.ammo_limit == 0 then return end

    local entities = utils.find_entities_in_radius(params.surface, {
        to_be_upgraded = true,
        position = params.target_pos,
        radius = params.radius,
    }, true)
    table.sort(entities, utils.distance_sort(params.target_pos))
    utils.arc_cull(entities, params.character.position, params.target_pos)

    local used = false

    for _, entity in pairs(entities) do
        if storage.to_upgrade[entity.unit_number] then goto continue end
        local upgrade_target, quality = entity.get_upgrade_target()
        ---@cast upgrade_target -?
        ---@cast quality -?

        local item, stack = utils.find_place_result_stack(params.inventory, upgrade_target.items_to_place_this, quality)
        if not item then goto continue end
        ---@cast stack -?

        local connection
        if entity.type == "underground-belt" then
            connection = entity.underground_belt_neighbour
            if connection and connection.type == "underground-belt" then
                -- impossible for connection to not be marked for upgrade so no need to check
                item.count = item.count * 2
                if stack.count < item.count then goto continue end
                storage.to_upgrade[connection.unit_number] = true
            else
                connection = nil
            end
        end

        local slot = game.create_inventory(1)
        slot[1].transfer_stack(stack, item.count)

        local sprite, shadow = render.draw_new_item(params.surface, item.name, params.source_pos)
        local duration = utils.get_flying_item_duration(params.source_pos, entity.position)
        storage.flying_items[sprite.id] = {
            action = "upgrade",
            slot = slot,
            surface = params.surface,
            force = params.force,
            source_pos = params.source_pos,
            target_pos = entity.position,
            start_tick = params.tick,
            end_tick = params.tick + duration,
            orientation_deviation = utils.orientation_deviation(),
            target_entity = entity,
            unit_number = entity.unit_number,
            sprite = sprite,
            shadow = shadow,
            connection = connection,
        } --[[@as FlyingUpgradeItem]]

        storage.to_upgrade[entity.unit_number] = true

        used = true
        params.ammo_item.drain_ammo(1)
        params.ammo_limit = params.ammo_limit - 1
        if params.ammo_limit <= 0 then break end

        ::continue::
    end

    return used
end

---@param item FlyingUpgradeItem
local function upgrade(item)
    local entity = item.target_entity --[[@as LuaEntity]]
    if not entity.valid then return end
    local target = entity.get_upgrade_target()
    if not target then return end

    ---@type {contents: DetailedItemOnLine[], inventory: LuaInventory}[]?
    local lines
    local connection = item.connection
    if connection and connection.valid then
        lines = {}
        local output = entity.belt_to_ground_type == "input" and entity or item.connection --[[@as LuaEntity]]
        for i = 1, 2 do
            local line = output.get_transport_line(i + 2) ---@diagnostic disable-line: param-type-mismatch
            local contents = line.get_detailed_contents()
            local inventory = game.create_inventory(#contents)
            for j = #contents, 1, -1 do
                inventory[j].transfer_stack(contents[j].stack)
            end
            lines[i] = {
                contents = contents,
                inventory = inventory,
            }
        end
    end

    local stack = item.slot[1]
    local quality = stack.quality
    local surface = entity.surface
    local force = entity.force
    local position = entity.position
    local etype = entity.type
    local belt_to_ground_type = etype == "underground-belt" and entity.belt_to_ground_type or nil
    local loader_type = (etype == "loader" or etype == "loader-1x1") and entity.loader_type or nil

    local character = utils.temp_character(surface)
    local success = surface.create_entity{
        name = target.name,
        position = position,
        direction = entity.direction,
        mirror = entity.mirroring,
        quality = quality,
        force = force,
        fast_replace = true,
        character = character,
        create_build_effect_smoke = true,
        raise_built = true,
        type = belt_to_ground_type or loader_type,
    }

    if lines then
        connection = surface.create_entity{
            name = target.name,
            position = connection.position,
            direction = connection.direction,
            mirror = connection.mirroring, -- technically unnecessary but doesn't hurt
            quality = quality,
            force = force,
            fast_replace = true,
            character = character,
            create_build_effect_smoke = true,
            raise_built = true,
            type = connection.belt_to_ground_type
        } ---@cast connection -?

        if connection ~= success then
            stack.count = stack.count / 2
        end
    end

    if success then
        surface.play_sound{path = "entity-build/" .. target.name, position = position}
        surface.spill_inventory{
            inventory = character.get_main_inventory() --[[@as LuaInventory]],
            position = position,
            force = force,
            allow_belts = false,
        }
    end
    character.destroy()

    if lines then
        if success and connection then
            local output = success.belt_to_ground_type == "input" and success or connection --[[@as LuaEntity]]
            for i = 1, 2 do
                local line = lines[i]
                local contents = line.contents
                local inventory = line.inventory
                local insert = output.get_transport_line(i + 2 --[[@as defines.transport_line]]).force_insert_at
                for j = 1, #inventory do
                    insert(contents[j].position, inventory[j])
                end
            end
        else
            for i = 1, 2 do
                surface.spill_inventory{
                    inventory = lines[i].inventory,
                    position = position,
                    force = force,
                    allow_belts = false,
                }
            end
        end
        for i = 1, 2 do
            lines[i].inventory.destroy()
        end
    end

    return success
end

---@param item FlyingUpgradeItem
function lib.action(item)
    if not upgrade(item) then
        utils.spill_item(item)
    end
    storage.to_upgrade[item.unit_number] = nil
end

return lib

---@class FlyingUpgradeItem:FlyingItemBase
---@field action "upgrade"
---@field target_entity LuaEntity
---@field unit_number uint
---@field connection LuaEntity?