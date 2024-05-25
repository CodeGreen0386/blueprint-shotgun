local sqrt, sin, cos = math.sqrt, math.sin, math.cos
local min, max = math.min, math.max
local tau = math.pi * 2

---@class BlueprintShotgun.vector
local vec = {}

function vec.zero() return {x = 0, y = 0} end

function vec.add(a, b) return {x = a.x + b.x, y = a.y + b.y} end
function vec.sub(a, b) return {x = a.x - b.x, y = a.y - b.y} end
function vec.mul(v, n) return {x = v.x * n, y = v.y * n} end
function vec.div(v, n) return {x = v.x / n, y = v.y / n} end

function vec.rotate(v, a)
    local cos_a = cos(a)
    local sin_a = sin(a)
    return {
        x = (v.x * cos_a) - (v.y * sin_a),
        y = (v.x * sin_a) + (v.y * cos_a),
    }
end

function vec.dist(a, b)
    return sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end

function vec.dist2(a, b)
    return (a.x - b.x)^2 + (a.y - b.y)^2
end

function vec.len(v)
    return sqrt(v.x * v.x + v.y * v.y)
end

function vec.norm(v)
    local l = vec.len(v)
    if l == 0 then
        l = 1
    end
    return {x = v.x / l, y = v.y / l}
end

function vec.dot(a, b)
    a = vec.norm(a)
    b = vec.norm(b)
    return a.x * b.x + a.y * b.y
end

function vec.random(n)
    n = n or 1
    return vec.rotate({x = n, y = 0}, math.random() * tau)
end

-- function vec.clamp(v, n, m)
--     return {
--         x = max(min(v.x, n), m),
--         y = max(min(v.y, n), m),
--     }
-- end

return vec