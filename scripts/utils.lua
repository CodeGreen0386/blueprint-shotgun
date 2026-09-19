---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

require("util")
local vec = require("scripts/vector") ---@module "blueprint-shotgun/scripts/vector"

local utils = {}

---@generic T
---@param t T[]
function utils.condense(t)
    local ret = {}
    local c = 0
    for i, v in pairs(t) do
        t[i] = nil
        c = c + 1
        ret[c] = v
    end
    return ret
end

---@param character LuaEntity
function utils.get_character_data(character)
    local unit_number = character.unit_number --[[@as uint64]]
    local data = storage.characters[unit_number]
    if data then return data end
    ---@class CharacterData
    ---@field volume float
    data = {character = character, mode = "build", auto_swap = true, aim_position = true, tick = 0, volume = 0, cooldown = 0}
    storage.characters[unit_number] = data

    local player = character.player
    if player then
        data.auto_swap = player.mod_settings["blueprint-shotgun-mode-swap"].value ~= "manual"
        local aim_mode = player.mod_settings["blueprint-shotgun-aim-mode"].value --[[@as string]]
        if aim_mode == "auto" then
            data.aim_position = player.input_method == defines.input_method.keyboard_and_mouse
        else
            data.aim_position = aim_mode == "position"
        end
    end

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
---@return uint
function utils.get_flying_item_duration(source_pos, target_pos)
    return math.max(1, math.ceil((vec.dist(source_pos, target_pos) * (math.random() / 4 + 1)) * 3))
end

---@return number
function utils.orientation_deviation()
    return (math.random() - 0.5) / 10
end

---@param inventory LuaInventory
---@param item string
---@return int, string?
function utils.get_item_count_aq(inventory, item)
    for quality in pairs(prototypes.quality) do
        local count = inventory.get_item_count{name = item, quality = quality}
        if count > 0 then
            return count, quality
        end
    end
    return 0
end

---@param inventory LuaInventory
---@param items ItemToPlace[]
---@param quality QualityID
---@return ItemToPlace?, LuaItemStack?
function utils.find_place_result_stack(inventory, items, quality)
    for _, item in pairs(items) do
        if inventory.get_item_count{name = item.name, quality = quality} >= item.count then
            local stack = inventory.find_item_stack({name = item.name, quality = quality}) --[[@as LuaItemStack]]
            if stack.count >= item.count then
                return item, stack
            end
        end
    end
end

---@param item FlyingItem
function utils.spill_item(item)
    item.surface.spill_item_stack{
        position = item.target_pos,
        stack = item.slot[1],
        force = item.force,
        allow_belts = false
    }
    game.play_sound{path = "utility/drop_item", position = item.target_pos}
end

-- no fucking clue why it's 88 but it's the magic number I guess
local spill_offset = {x = 88/256, y = 88/256}
---@param surface LuaSurface
---@param position MapPosition
---@param stack LuaItemStack
---@param force? ForceID
function utils.exact_spill(surface, position, stack, force)
    return surface.spill_item_stack{
        position = vec.add(position, spill_offset),
        stack = stack,
        force = force,
        allow_belts = false,
    }
end

---@param surface LuaSurface
---@return LuaEntity
function utils.temp_character(surface, force)
    local character = surface.create_entity{
        name = "blueprint-shotgun-character",
        position = {x = 0, y = 0},
        force = force,
    } ---@cast character LuaEntity
    character.insert("blueprint-shotgun-dummy-armor")
    character.get_inventory(defines.inventory.character_guns).insert{name = "blueprint-shotgun", count = 3}
    character.get_inventory(defines.inventory.character_ammo).insert{name = "item-canister", count = 600}
    return character
end

---@param entity LuaEntity
---@return MapPosition
function utils.get_bounding_box_center(entity)
    local bb = entity.bounding_box
    return vec.div(vec.add(bb.left_top, bb.right_bottom), 2)
end

---@param circle MapPosition
---@param radius number
---@param bb BoundingBox
local function intersects(circle, radius, bb)
    local rect = vec.div(vec.add(bb.left_top, bb.right_bottom), 2)

    local center_distance = vec.abs(vec.sub(circle, rect))
    local width = (bb.right_bottom.x - bb.left_top.x) / 2
    local height = (bb.right_bottom.y - bb.left_top.y) / 2

    if center_distance.x < width and center_distance.y < height then return true end

    if center_distance.x > width + radius then return end
    if center_distance.y > height + radius then return end

    if center_distance.y < height and center_distance.x < width + radius then return true end
    if center_distance.x < width and center_distance.y < height + radius then return true end

    local corner_distance2 = (center_distance.x - width)^2 + (center_distance.y - height)^2
    return corner_distance2 <= radius^2 and {r = 1, b = 1} or nil
end

---@param surface LuaSurface
---@param params EntitySearchFilters
---@param selection boolean?
---@return LuaEntity[]
function utils.find_entities_in_radius(surface, params, selection)
    local position = params.position --[[@as MapPosition]]
    local radius = params.radius --[[@as number]]

    -- rendering.draw_circle{
    --     color = {g = 1},
    --     radius = radius,
    --     surface = surface,
    --     target = position,
    --     time_to_live = 3
    -- }

    params.area = {vec.add(position, {x = -radius - 0.5, y = -radius - 0.5}), vec.add(position, {x = radius + 0.5, y = radius + 0.5})}

    params.position = nil
    params.radius = nil
    local rect_entities = surface.find_entities_filtered(params)
    local c = 0
    local entities = {}
    for _, entity in pairs(rect_entities) do
        local offset = vec.sub(position, entity.position)
        local bb = selection and entity.selection_box or entity.bounding_box
        local orientation = bb.orientation
        if orientation then
            offset = vec.rotate(offset, orientation * math.pi * 2)
        end
        if not intersects(position, radius, bb) then goto continue end

        c = c + 1
        entities[c] = entity

        -- rendering.draw_rectangle{
        --     color = {g = 1, b = 1},
        --     left_top = bb.left_top,
        --     right_bottom = bb.right_bottom,
        --     surface = surface,
        --     target = entity,
        --     time_to_live = 3,
        -- }

        ::continue::
    end
    return entities
end

---@param name string
---@param count uint
---@param surface SurfaceIdentification
---@param position MapPosition
---@param height number
---@param velocity? Vector
function utils.create_ultracube_token(name, count, surface, position, height, velocity)
    return remote.call("Ultracube", "create_ownership_token", name, count, 60, {
        surface = surface,
        position = position,
        spill_position = position,
        velocity = velocity,
        height = height,
    }) --[[@as uint]]
end

return utils