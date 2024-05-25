local vec = require("scripts/vector") --[[@as BlueprintShotgun.vector]]

---@class BlueprintShotgun.render
local render = {}

---@param surface LuaSurface
---@param item string
---@param position MapPosition
---@param height? number
---@param orientation? RealOrientation
function render.draw_new_item(surface, item, position, height, orientation)
    height = height or 1
    local id = rendering.draw_sprite{
        sprite = "item/" .. item,
        surface = surface,
        target = vec.add(position, {x = 0, y = -height}),
        orientation = orientation or math.random(),
        x_scale = 0.5,
        y_scale = 0.5,
    }

    local shadow = rendering.draw_sprite{
        sprite = "item-shadow",
        surface = surface,
        target = vec.add(position, {x = height, y = 0}),
        x_scale = 0.5,
        y_scale = 0.5,
    }

    return id, shadow
end

    local destroy = rendering.destroy
    local set_to = rendering.set_to
    local draw_line = rendering.draw_line

---@param data BlueprintShotgun.MiningData
function render.mining_progress(data)
    local entity = data.entity
    local surface = entity.surface

    if data.progress <= 0 then
        if data.bar then destroy(data.bar) end
        if data.bar_black then destroy(data.bar_black) end
        return
    end

    local bb = entity.bounding_box
    local lt, rb = vec.sub(bb.left_top, entity.position), vec.sub(bb.right_bottom, entity.position)
    local distance = lt.x + (rb.x - lt.x) * data.progress / data.mining_time
    local to_offset = {x = distance, y = rb.y}
    local bar = data.bar
    if bar then
        set_to(bar, entity, to_offset)
    else
        data.bar_black = draw_line{
            color = {0,0,0},
            surface = surface,
            from = entity,
            to = entity,
            from_offset = {x = lt.x, y = rb.y},
            to_offset = {x = rb.x, y = rb.y},
            width = 2,
        }
        data.bar = draw_line{
            color = {250, 168, 56},
            surface = surface,
            from = entity,
            to = entity,
            from_offset = {x = lt.x, y = rb.y},
            to_offset = to_offset,
            width = 2,
        }
    end
end

function render.smoke(surface, source_pos, target)
    for i = 1, 3 do
        local position = vec.add(source_pos, vec.random(math.sqrt(math.random() * 2)))
        surface.create_entity{
            name = "vacuum-smoke",
            position = position,
            speed = 0.05,
            target = target,
            max_range = 2.3,
        } --[[@as LuaSurface.create_entity_param.projectile]]
    end
end

local tick_rate = 3

function render.on_tick(event)
    if event.tick % tick_rate ~= 0 then return end

    for entity_id, data in pairs(global.to_mine) do
        if not data.entity.valid then
            global.to_mine[entity_id] = nil
            goto continue
        end

        if not global.currently_mining[entity_id] then
            data.progress = data.progress - 1/2 * tick_rate
        end
        render.mining_progress(data)
        if data.progress <= 0 then
            global.to_mine[entity_id] = nil
        end

        ::continue::
    end
    global.currently_mining = {}
end

return render