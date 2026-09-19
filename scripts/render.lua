---@namespace BlueprintShotgun
---@type Storage -- emmylua jank
storage = storage --[[@as Storage]]

local vec = require("scripts/vector") ---@module "blueprint-shotgun/scripts/vector"

local render = {}

---@param surface LuaSurface
---@param item string
---@param position MapPosition
---@param height? number
---@param orientation? RealOrientation
function render.draw_new_item(surface, item, position, height, orientation)
    height = height or 1
    local sprite = rendering.draw_sprite{
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

    return sprite, shadow
end

local draw_line = rendering.draw_line

---@param data BlueprintShotgun.MiningData
function render.mining_progress(data)
    local entity = data.entity
    local surface = entity.surface

    if data.progress <= 0 then
        if data.bar then data.bar.destroy() end
        if data.bar_black then data.bar_black.destroy() end
        return
    end

    local bb = entity.bounding_box
    local lt, rb = vec.sub(bb.left_top, entity.position), vec.sub(bb.right_bottom, entity.position)
    local distance = lt.x + (rb.x - lt.x) * data.progress / data.mining_time
    local to_offset = {x = distance, y = rb.y}
    local bar = data.bar
    if bar then
        bar.to = {entity = entity, offset = to_offset}
    else
        data.bar_black = draw_line{
            color = {0,0,0},
            surface = surface,
            from = {entity = entity, offset = {x = lt.x, y = rb.y}},
            to = {entity = entity, offset = {x = rb.x, y = rb.y}},
            width = 2,
        }
        data.bar = draw_line{
            color = {250, 168, 56},
            surface = surface,
            from = {entity = entity, offset = {x = lt.x, y = rb.y}},
            to = {entity = entity, offset = to_offset},
            width = 2,
        }
    end
end

---@param surface LuaSurface
---@param source_pos MapPosition
---@param target ScriptRenderTarget
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

    for entity_id, data in pairs(storage.to_mine) do
        if not data.entity.valid then
            storage.to_mine[entity_id] = nil
            goto continue
        end

        if not storage.currently_mining[entity_id] then
            data.progress = data.progress - 1/2 * tick_rate
        end
        render.mining_progress(data)
        if data.progress <= 0 then
            storage.to_mine[entity_id] = nil
        end

        ::continue::
    end
    storage.currently_mining = {}
end

---@param color Color
---@param radius double
---@param surface SurfaceIdentification
---@param target ScriptRenderTarget
function render.debug_circle(color, radius, surface, target)
    rendering.draw_circle{
        color = color,
        radius = radius,
        surface = surface,
        target = target,
        filled = true,
        time_to_live = 1,
    }
end

function render.debug_line(color, width, surface, from, to)
    rendering.draw_line{
        color = {r = 1, g = 1},
        from = from,
        to = to,
        surface = surface,
        width = 2,
        time_to_live = 1,
    }
end

return render