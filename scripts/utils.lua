require("util")
local vec = require("scripts/vector") --[[@as BlueprintShotgun.vector]]
local sin, cos = math.sin, math.cos

---@class BlueprintShotgun.utils
local utils = {}

---@param character LuaEntity
function utils.get_character_data(character)
    local data = storage.characters[character.unit_number]
    if data then return data end
    ---@class BlueprintShotgun.CharacterData
    ---@field volume float
    data = {character = character, mode = "build", tick = 0, volume = 0}
    storage.characters[character.unit_number] = data
    script.register_on_object_destroyed(character)
    return data
end

local arc = 90/360 * math.pi -- / 2 * 2
---@param entities LuaEntity[]
---@param source_pos MapPosition
---@param target_pos MapPosition
function utils.arc_cull(entities, source_pos, target_pos)
    local target_vector = vec.sub(target_pos, source_pos)

    local spread = math.min(1, 1 / (vec.len(target_vector) + 2) + 0.5)
    local target_arc = spread * arc
    local arc_vector = vec.rotate(target_vector, target_arc)
    local target_dot = vec.dot(target_vector, arc_vector)

    for i = #entities, 1, -1 do
        local entity = entities[i]
        local entity_vector = vec.sub(entity.position, source_pos)
        local entity_dot = vec.dot(target_vector, entity_vector)
        if entity_dot < target_dot then
            table.remove(entities, i)
        end
    end
end

---@param end_pos MapPosition
---@return fun(a: LuaEntity, b: LuaEntity):boolean
function utils.distance_sort(end_pos)
    return function (a, b)
        return vec.dist2(a.position, end_pos) < vec.dist2(b.position, end_pos)
    end
end

---@param source_pos MapPosition
---@param target_pos MapPosition
---@return number
function utils.get_flying_item_duration(source_pos, target_pos)
    return math.ceil((vec.dist(source_pos, target_pos) * (math.random() / 4 + 1)) * 3)
end

---@return number
function utils.orientation_deviaiton()
    return (math.random() - 0.5) / 10
end

---@param item FlyingItem
function utils.spill_item(item)
    item.surface.spill_item_stack(item.target_pos, {name = item.name, count = item.count}, nil, item.force, false)
    game.play_sound{path = "utility/drop_item", position = item.target_pos}
end

-- no fucking clue why it's 88 but it's the magic number I guess
local spill_offset = {x = 88/256, y = 88/256}
function utils.exact_spill(surface, position, stack, force)
    surface.spill_item_stack(vec.add(position, spill_offset), stack, nil, force, false)
end

---@param surface LuaSurface
---@param prototype LuaEntityPrototype|LuaTilePrototype
---@param force ForceIdentification?
function utils.spill_products(surface, position, prototype, force)
    local products = prototype.mineable_properties.products
    if products then
        local stacks = {}
        local c = 0
        for _, product in pairs(products) do
            if product.amount then
                c = c + 1
                stacks[c] = {name = product.name, count = product.amount}
            elseif math.random() <= product.probability then
                c = c + 1
                stacks[c] = {
                    name = product.name,
                    count = math.random(product.amount_min, product.amount_max)
                }
            end
        end
        for _, stack in pairs(stacks) do
            utils.exact_spill(surface, position, stack, force)
        end
    end
end

---@param surface LuaSurface
---@return LuaEntity
function utils.temp_character(surface, force)
    local character = surface.create_entity{
        name = "blueprint-shotgun-character",
        position = {x = 0, y = 0},
        force = force,
    } ---@cast character LuaEntity
    character.insert("light-armor")
    character.get_inventory(defines.inventory.character_guns).insert{name = "blueprint-shotgun", count = 3}
    character.get_inventory(defines.inventory.character_ammo).insert{name = "item-canister", count = 600}
    return character
end

---@param entity LuaEntity
---@param spill_position MapPosition?
---@return LuaEntity?
function utils.upgrade_entity(entity, spill_position)
    local target = entity.get_upgrade_target()
    if not target then return end
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
        force = force,
        fast_replace = true,
        character = character,
        spill = true,
        create_build_effect_smoke = true,
        raise_built = true,
        type = belt_to_ground_type or loader_type,
    }
    if success then
        game.play_sound{path = "entity-build/" .. target.name}
        local inventory = character.get_main_inventory() --[[@as LuaInventory]]
        for i = 1, #inventory do
            local item = inventory[i]
            if not item.valid_for_read then break end
            surface.spill_item_stack(spill_position or position, item, nil, force, false)
        end
    end

    character.destroy()

    return success
end

---@param entity LuaEntity
---@return MapPosition
function utils.get_bounding_box_center(entity)
    local bb = entity.bounding_box
    return vec.div(vec.add(bb.left_top, bb.right_bottom), 2)
end

---@param surface LuaSurface
---@param params LuaSurface.find_entities_filtered_param
---@return LuaEntity[]
function utils.find_entities_in_radius(surface, params)
    -- rendering.draw_circle{
    --     color = {1,1,1},
    --     radius = params.radius,
    --     surface = surface,
    --     target = params.position,
    --     time_to_live = time_to_live,
    -- }

    -- local _params = table.deepcopy(params)
    local radius = params.radius
    local radius_squared = radius^2
    local position = params.position --[[@as MapPosition]]
    params.area = {vec.add(position, {x = -radius, y = -radius}), vec.add(position, {x = radius, y = radius})}
    params.radius = nil
    params.position = nil
    local entities = surface.find_entities_filtered(params)
    for i = #entities, 1, -1 do
        local entity = entities[i]
        if vec.dist2(position, entity.position) < radius_squared then goto continue end
        local bb = entity.bounding_box
        local lt, rb = bb.left_top, bb.right_bottom
        if vec.dist2(position, lt) < radius_squared then goto continue end
        if vec.dist2(position, rb) < radius_squared then goto continue end

        local orientation = bb.orientation or 0
        local center = vec.div(vec.add(lt, rb), 2)
        local offset_vector = vec.sub(lt, center)
        offset_vector.y = -offset_vector.y
        offset_vector = vec.rotate(offset_vector, orientation * math.pi * 2)
        local lb = vec.add(center, offset_vector)
        local rt = vec.add(center, vec.mul(offset_vector, -1))
        if vec.dist2(position, lb) < radius_squared then goto continue end
        if vec.dist2(position, rt) < radius_squared then goto continue end

        local segments = {
            {lt, rt, orientation},
            {lb, rb, orientation},
            {lb, lt, (orientation + 0.25) % 1},
            {rt, rb, (orientation + 0.25) % 1},
        }

        for _, line in pairs(segments) do
            local angle = line[3] * math.pi * 2
            local sin_angle, cos_angle = sin(angle), cos(angle)
            local d = sin_angle * (line[1].x - position.x) - cos_angle * (line[1].y - position.y) -- distance to line
            local point = {x = position.x + sin_angle * d, y = position.y - cos_angle * d}
            local x_index = line[1].x < line[2].x and 1 or 2
            local y_index = line[1].y < line[2].y and 1 or 2
            local x1 = line[x_index].x
            local x2 = line[x_index % 2 + 1].x
            local y1 = line[y_index].y
            local y2 = line[y_index % 2 + 1].y
            local dist2 = vec.dist2(point, position)
            local within_x = point.x >= x1 and point.x <= x2
            local within_y = point.y >= y1 and point.y <= y2
            if dist2 < radius_squared and within_x and within_y then goto continue end
        end
        table.remove(entities, i)
        -- rendering.draw_circle{
        --     color = {1,0,0},
        --     radius = 1/8,
        --     filled = true,
        --     surface = surface,
        --     target = entity,
        --     time_to_live = time_to_live
        -- }

        ::continue::
    end

    -- for _, entity in pairs(entities) do
    --     rendering.draw_circle{
    --         color = {0,1,0},
    --         radius = 1/8,
    --         filled = true,
    --         surface = surface,
    --         target = entity,
    --         time_to_live = time_to_live
    --     }
    -- end

    return entities
end

return utils