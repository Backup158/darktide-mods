local mod = get_mod("debuff_indicator")

local BuffSettings = require("scripts/settings/buff/buff_settings")
local BuffTemplates = require("scripts/settings/buff/buff_templates")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local font_size = mod:get("font_size")
local opacity = mod:get("font_opacity")
local distance = mod:get("distance")
local offset_z = mod:get("offset_z") / 10
local display_style = mod:get("display_style")

local template = {}
local size = {
    font_size * 20,
    1
}
local scale_fraction = 0.75

template.size = size
template.unit_node = "root_point"
template.min_size = {
    size[1] * scale_fraction,
    size[2] * scale_fraction
}
template.max_size = {
    size[1],
    size[2]
}
template.name = "debuff_indicator"
template.check_line_of_sight = true
template.screen_clamp = true
template.max_distance = distance
template.position_offset = {
    0,
    0,
    offset_z
}
template.fade_settings = {
    fade_to = 1,
    fade_from = 0,
    default_fade = 1,
    distance_max = template.max_distance,
    distance_min = template.max_distance * 0.5,
    easing_function = math.easeCubic
}

local _update_settings = function(style, template)
    font_size = mod:get("font_size")
    opacity = mod:get("font_opacity")
    distance = mod:get("distance")
    offset_z = mod:get("offset_z") / 10
    display_style = mod:get("display_style")

    size = {
        font_size * 20,
        1
    }

    style.body_text.font_size = font_size
    style.body_text.default_font_size = font_size
    style.body_text.text_color = { opacity, 255, 255, 255 }
    style.body_text.default_text_color = { opacity, 255, 255, 255 }
    style.body_text.offset = {
        size[1] * 0.5,
        -size[2],
        3
    }

    template.size = size
    template.min_size = {
        size[1] * scale_fraction,
        size[2] * scale_fraction
    }
    template.max_size = {
        size[1],
        size[2]
    }
    template.max_distance = distance
    template.position_offset = {
        0,
        0,
        offset_z,
    }
    template.fade_settings = {
        fade_to = 1,
        fade_from = 0,
        default_fade = 1,
        distance_max = template.max_distance,
        distance_min = template.max_distance * 0.5,
        easing_function = math.easeCubic
    }
end

local _apply_display_style_and_color = function(buff_name, label, count)
    local buff_display_text = ""

    if display_style == "label" then
        buff_display_text = label
    elseif display_style == "count" then
        buff_display_text = count
    else
        buff_display_text = label .. ": " .. count
    end

    local custom_color = mod:get("color_" .. buff_name)

    if custom_color and Color[custom_color] then
        local c = Color[custom_color](255, true)
        local color = string.format("{#color(%s,%s,%s)}", c[2], c[3], c[4])

        buff_display_text = string.format("%s%s{#reset()}", color, buff_display_text)
    end

    return buff_display_text
end

local _add_stagger_and_suppression = function(blackboard, content)
    local stagger_component = blackboard.stagger
    local suppression_component = blackboard.suppression

    if mod:get("enable_stagger") and stagger_component then
        local stagger_count = stagger_component.num_triggered_staggers

        if stagger_count > 0 then
            content.body_text = _apply_display_style_and_color("stagger", mod:localize("stagger"), stagger_count)
        end
    end

    if mod:get("enable_suppression") and suppression_component then
        local is_suppressed = suppression_component.is_suppressed

        if is_suppressed then
            local suppression_value = suppression_component.suppress_value

            if content.body_text ~= "" then
                content.body_text = content.body_text .. "\n"
            end

            content.body_text = content.body_text .. _apply_display_style_and_color("suppression", mod:localize("suppression"), suppression_value)
        end
    end
end

local _get_stacks = function(buff_ext, buff_name)
    local buff_template = BuffTemplates[buff_name]
    local max_stacks = buff_template and buff_template.max_stacks
    local stacks = buff_ext:current_stacks(buff_name)

    if max_stacks and stacks > max_stacks then
        stacks = max_stacks
    end

    return stacks
end

local _calculate_rending_percentage = function(buff_texts)
    local buff_stat_buffs = BuffSettings.stat_buffs
    local name_sm = "rending_debuff"
    local name_md = "rending_debuff_medium"
    local function _calculate(name)
        local stacks = buff_texts[name] and buff_texts[name].stacks or 0
        local stat_buffs = BuffTemplates[name] and BuffTemplates[name].stat_buffs or {}
        local value = stat_buffs and stat_buffs[buff_stat_buffs.rending_multiplier] or 0

        return value * stacks
    end

    if buff_texts[name_sm] or buff_texts[name_md] then
        local total_sm = _calculate(name_sm)
        local total_md = _calculate(name_md)

        if not buff_texts[name_sm] and buff_texts[name_md] then
            buff_texts[name_sm] = {
                display_name = mod:localize(name_sm),
                stacks = 0
            }
        end

        buff_texts[name_sm].stacks = (total_sm + total_md) * 100 .. "%"
        buff_texts[name_md] = nil
    end

    return buff_texts
end

local _add_buff_and_debuff = function(buff_ext, buffs, content)
    local buff_texts = {}

    for _, buff in ipairs(buffs) do
        local buff_name = buff:template_name()

        if (mod:get("enable_filter") and not table.find(mod.buff_names, buff_name)) or
           (not mod:get("enable_dot") and table.find(mod.dot_names, buff_name)) or
           (not mod:get("enable_debuff") and not table.find(mod.dot_names, buff_name))
        then
            goto continue
        end

        local display_name = table.find(mod.buff_names, buff_name) and mod:localize(buff_name) or buff_name
        local stacks = _get_stacks(buff_ext, buff_name)

        buff_texts[buff_name] = {
            display_name = display_name,
            stacks = stacks
        }

        ::continue::
    end

    buff_texts = _calculate_rending_percentage(buff_texts)

    for name, data in pairs(buff_texts) do
        local buff_display_text = _apply_display_style_and_color(name, data.display_name, data.stacks)

        if content.body_text ~= "" then
            content.body_text = content.body_text .. "\n"
        end

        content.body_text = content.body_text .. buff_display_text
    end
end

function template.create_widget_defintion(template, scenegraph_id)
    local header_font_setting_name = "nameplates"
    local header_font_settings = UIFontSettings[header_font_setting_name]
    local header_font_color = header_font_settings.text_color

    return UIWidget.create_definition({
        {
            value_id = "body_text",
            style_id = "body_text",
            pass_type = "text",
            value = "<body_text>",
            style = {
                vertical_alignment = "center",
                horizontal_alignment = "center",
                text_vertical_alignment = "top",
                text_horizontal_alignment = "left",
                offset = {
                    size[1] * 0.5,
                    -size[2],
                    3
                },
                font_type = header_font_settings.font_type,
                font_size = font_size,
                default_font_size = font_size,
                text_color = { opacity, 255, 255, 255 },
                default_text_color = { opacity, 255, 255, 255 },
                drop_shadow = true,
                size = size,
            },
            visibility_function = function (content, style)
                return not content.is_clamped
            end,
        }
    }, scenegraph_id)
end

function template.on_enter(widget, marker, template)
    local content = widget.content

    content.body_text = ""
    marker.draw = false
    marker.update = true
end

function template.update_function(parent, ui_renderer, widget, marker, template, dt, t)
    local content = widget.content
    local style = widget.style
    local unit = marker.unit

    content.body_text = ""

    if mod._setting_changed then
        _update_settings(style, marker.template)
        mod._setting_changed = false
    end

    if content.distance then
        marker.draw = true
    end

    if not HEALTH_ALIVE[unit] then
        marker.remove = true
        return
    end

    local blackboard = BLACKBOARDS[unit]

    if blackboard then
        _add_stagger_and_suppression(blackboard, content)
    end

    local buff_ext = ScriptUnit.extension(unit, "buff_system")
    local buffs = buff_ext and buff_ext:buffs()

    if buffs then
        _add_buff_and_debuff(buff_ext, buffs, content)
    end

    if display_style == "count" then
        content.body_text = string.gsub(content.body_text, "\n", " ")
    end

    local line_of_sight_progress = content.line_of_sight_progress or 0

    if marker.raycast_initialized then
        local raycast_result = marker.raycast_result
        local line_of_sight_speed = 8

        if raycast_result then
            line_of_sight_progress = math.max(line_of_sight_progress - dt * line_of_sight_speed, 0)
        else
            line_of_sight_progress = math.min(line_of_sight_progress + dt * line_of_sight_speed, 1)
        end
    end

    local draw = marker.draw

    if draw then
        content.line_of_sight_progress = line_of_sight_progress
        widget.alpha_multiplier = line_of_sight_progress
    end
end

return template
